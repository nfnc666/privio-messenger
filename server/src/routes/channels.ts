import type { FastifyPluginAsync } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { pool, withTransaction, type PoolClient } from '../db/pool.js';
import type { DeliveryBus } from '../services/bus.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import { ApiError } from '../util/errors.js';
import { verifySecret } from '../util/crypto.js';
import { base64Bytes, parse, uuidSchema } from '../util/validate.js';
import {
  clearKeyRequest,
  clearKeyRequestsFor,
  pendingKeyRequests,
  recordKeyRequest,
  wakeKeyHolders,
} from '../services/key_requests.js';
import {
  DEFAULT_ADMIN_PERMISSIONS,
  NO_PERMISSIONS,
  OWNER_PERMISSIONS,
  permissionsFromRow,
  withinAuthority,
  type ChannelPermission,
  type ChannelPermissions,
} from '../services/channel_permissions.js';

const MAX_POST_BYTES = 256 * 1024;

const handleSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9_.]{3,32}$/, 'must be 3-32 characters of a-z, 0-9, underscore or dot');

/**
 * One reaction emoji.
 *
 * Deliberately not "is this a real emoji": that question needs a Unicode
 * table, the table moves every year, and getting it wrong rejects somebody's
 * flag. What it does instead is refuse anything that could be used as *text* —
 * ASCII letters, digits and whitespace — so the reaction bar under a post
 * cannot be turned into a row of captions in somebody else's channel.
 */
const reactionEmojiSchema = z
  .string()
  .min(1)
  .max(16)
  .refine((value) => !/[A-Za-z0-9\s]/.test(value), {
    message: 'must be a symbol, not text',
  });

/** At most a barful. Twelve already does not fit on a phone. */
const reactionEmojisSchema = z.array(reactionEmojiSchema).min(1).max(12);

/**
 * What a channel looks like from outside.
 *
 * A public channel's title and description are plaintext because discovery
 * cannot search ciphertext; its posts are not. A private channel returns its
 * sealed metadata instead, and the server can say nothing about what is in it.
 */
function publicView(row: Record<string, unknown>) {
  return {
    id: row.id,
    visibility: row.visibility,
    handle: row.handle,
    title: row.title,
    description: row.description,
    category: row.category,
    encryptedMetadata: row.encrypted_metadata
      ? (row.encrypted_metadata as Buffer).toString('base64')
      : null,
    restrictSaving: row.restrict_saving,
    // Which emojis this channel offers under a post.
    reactionEmojis: row.reaction_emojis ?? [],
    // What the invite link is set to. Not the code — that is handed out
    // separately, to members only.
    invite: {
      expiresAt: (row.invite_expires_at as Date | null)?.toISOString() ?? null,
      maxUses: row.invite_max_uses ?? null,
      uses: row.invite_uses ?? 0,
      needsApproval: row.invite_needs_approval ?? false,
    },
    // Whether its posts have threads under them at all.
    commentsEnabled: row.comments_enabled ?? false,
    /**
     * The channel's picture, as a media object id.
     *
     * What the bytes behind it are depends on the channel, and the client has
     * to know which: a **public** channel's picture is stored unsealed, because
     * it is drawn on the invite page and in a messenger's link preview, where
     * nobody holds a key. A **private** channel's is an ordinary sealed
     * attachment whose download token lives inside `encrypted_metadata` beside
     * the title — so the server holds the reference and can open neither.
     */
    avatarMediaId: row.avatar_media_id ?? null,
    // What a cache keys off, so replacing a picture is visible without waiting
    // for something else to evict the old one.
    avatarUpdatedAt: (row.avatar_updated_at as Date | null)?.toISOString() ?? null,
    memberCount: row.member_count,
    // Which key version this channel is on. The server counts these and holds
    // no key for any of them; see migration 015.
    keyEpoch: row.key_epoch ?? 1,
    // And which one opens its name, for a private channel. See migration 016.
    metadataKeyEpoch: row.metadata_key_epoch ?? 1,
    createdAt: (row.created_at as Date).toISOString(),
  };
}

/**
 * Anything that can run a query: the pool, or one transaction's client.
 *
 * The membership helpers take one so a permission check can happen *inside*
 * the transaction that is about to act on it. Reading membership on the pool
 * and then writing on a client is two different points in time, which is
 * exactly the race this file now avoids.
 */
type Queryable = { query: typeof pool.query };

/**
 * Takes the channel's row lock, in the one order everything here uses.
 *
 * Every operation that touches both `channels` and `channel_members` locks the
 * channel row **first**. Not a style preference: publishing needs the channel
 * and then the membership, removing needs the membership and then the channel,
 * and two transactions taking the same two locks in opposite orders is the
 * textbook deadlock. Naming the order in one function is how it stays the same
 * order in six routes.
 *
 * `FOR SHARE` for a reader that must not have the epoch move under it —
 * several posts may be in flight at once and they do not conflict with each
 * other. `FOR UPDATE` for the writer that is about to advance the epoch, which
 * must wait for those posts to land or refuse them.
 */
async function lockChannel(
  client: Queryable,
  channelId: string,
  mode: 'share' | 'update',
): Promise<{ key_epoch: number; comments_enabled: boolean } | null> {
  const { rows } = await client.query<{ key_epoch: number; comments_enabled: boolean }>(
    `SELECT key_epoch, comments_enabled FROM channels
     WHERE id = $1 AND deleted_at IS NULL
     FOR ${mode === 'share' ? 'SHARE' : 'UPDATE'}`,
    [channelId],
  );
  return rows[0] ?? null;
}

/**
 * Moves the channel to the next key version.
 *
 * Called inside the same transaction as the membership delete, so there is no
 * instant in which somebody has been removed and the channel is still on the
 * key they hold. The new key itself does not exist yet and will never exist
 * here: a remaining member's device generates it and claims the epoch below.
 */
async function rotateKeyEpoch(client: PoolClient, channelId: string): Promise<number> {
  const { rows } = await client.query<{ key_epoch: number }>(
    'UPDATE channels SET key_epoch = key_epoch + 1 WHERE id = $1 RETURNING key_epoch',
    [channelId],
  );
  return rows[0]?.key_epoch ?? 1;
}

interface Membership {
  role: string;
  permissions: ChannelPermissions;
}

async function membership(
  channelId: string,
  accountId: string,
  client: Queryable = pool,
): Promise<Membership | null> {
  const { rows } = await client.query(
    `SELECT m.role, m.can_post, m.can_edit_channel, m.can_delete_posts,
            m.can_manage_members, m.can_delete_channel
     FROM channel_members m
     JOIN channels c ON c.id = m.channel_id
     WHERE m.channel_id = $1 AND m.account_id = $2 AND c.deleted_at IS NULL`,
    [channelId, accountId],
  );
  const row = rows[0];
  return row ? { role: row.role, permissions: permissionsFromRow(row) } : null;
}

async function requireMember(
  channelId: string,
  accountId: string,
  client: Queryable = pool,
): Promise<Membership> {
  const member = await membership(channelId, accountId, client);
  if (!member) throw ApiError.forbidden('not_a_member', 'You are not in this channel');
  return member;
}

async function requirePermission(
  channelId: string,
  accountId: string,
  permission: ChannelPermission,
  client: Queryable = pool,
): Promise<Membership> {
  const member = await requireMember(channelId, accountId, client);
  if (!member.permissions[permission]) {
    throw ApiError.forbidden('insufficient_permission', `You need ${permission} for that`);
  }
  return member;
}

const permissionsSchema = z.object({
  canPost: z.boolean().optional(),
  canEditChannel: z.boolean().optional(),
  canDeletePosts: z.boolean().optional(),
  canManageMembers: z.boolean().optional(),
  canDeleteChannel: z.boolean().optional(),
});

function resolvePermissions(
  role: 'admin' | 'subscriber',
  requested: z.infer<typeof permissionsSchema> | undefined,
): ChannelPermissions {
  if (role === 'subscriber') return NO_PERMISSIONS;
  const base = requested ? NO_PERMISSIONS : DEFAULT_ADMIN_PERMISSIONS;
  return { ...base, ...requested };
}

/// Takes the bus so a key request can wake the devices that could answer it.
const channelRoutes = (bus: DeliveryBus): FastifyPluginAsync => async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };
  // Creating something new is gated on a license where the deployment sells
  // access; reading and joining are not.
  const requireLicensedAuth = {
    preHandler: [
      (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
      (r: Parameters<typeof app.requireLicense>[0]) => app.requireLicense(r),
    ],
  };

  /**
   * Create a channel.
   *
   * The caller generates the channel key and keeps it. Nothing in this request
   * carries it, which is what lets the server host a channel it cannot read.
   */
  app.post('/v1/channels', requireLicensedAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(
      z
        .object({
          visibility: z.enum(['public', 'private']),
          handle: handleSchema.optional(),
          title: z.string().trim().min(1).max(64).optional(),
          description: z.string().trim().max(512).optional(),
          category: z.string().trim().max(32).optional(),
          encryptedMetadata: base64Bytes(1, config.MAX_ENVELOPE_BYTES).optional(),
          restrictSaving: z.boolean().default(false),
          /**
           * The label for the key this device just generated, so epoch 1 is
           * claimed at birth like every epoch after it.
           *
           * Optional for a client that predates versioning; without it the
           * epoch is recorded as claimed by an unnamed key, which is honest —
           * the creator does hold one, and saying "nobody has generated it"
           * would make every existing channel look like it was mid-rotation.
           */
          keyId: z.string().regex(/^[A-Za-z0-9_-]{8,64}$/).optional(),
        })
        .refine((v) => v.visibility !== 'public' || (v.handle && v.title), {
          message: 'a public channel needs a handle and a title',
        })
        .refine((v) => v.visibility !== 'private' || v.encryptedMetadata, {
          message: 'a private channel needs sealed metadata',
        }),
      request.body,
    );

    const inviteCode = randomBytes(9).toString('base64url');

    const channel = await withTransaction(async (client) => {
      const { rows } = await client
        .query(
          `INSERT INTO channels
             (owner_account_id, visibility, handle, title, description, category,
              encrypted_metadata, invite_code, restrict_saving, member_count)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 1)
           RETURNING *`,
          [
            accountId,
            body.visibility,
            body.handle ?? null,
            body.title ?? null,
            body.description ?? null,
            body.category ?? null,
            body.encryptedMetadata ?? null,
            inviteCode,
            body.restrictSaving,
          ],
        )
        .catch((err: { code?: string }) => {
          if (err.code === '23505') throw ApiError.conflict('handle_taken', 'That handle is in use');
          throw err;
        });
      await client.query(
        `INSERT INTO channel_members
           (channel_id, account_id, role, can_post, can_edit_channel, can_delete_posts,
            can_manage_members, can_delete_channel)
         VALUES ($1, $2, 'owner', true, true, true, true, true)`,
        [rows[0].id, accountId],
      );
      // Epoch 1, claimed by the device that generated the key. Same table and
      // same rule as every rotation after it, so there is no special case for
      // "the first key" anywhere else.
      await client.query(
        `INSERT INTO channel_key_epochs (channel_id, epoch, key_id, claimed_by)
         VALUES ($1, 1, $2, $3)`,
        [rows[0].id, body.keyId ?? 'created-epoch-1', accountId],
      );
      return rows[0];
    });

    reply.code(201);
    return { ...publicView(channel), role: 'owner', permissions: OWNER_PERMISSIONS, inviteCode };
  });

  /** The channels this account is in. */
  app.get('/v1/channels', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT c.*, m.role, m.can_post, m.can_edit_channel, m.can_delete_posts,
              m.can_manage_members, m.can_delete_channel
       FROM channel_members m
       JOIN channels c ON c.id = m.channel_id
       WHERE m.account_id = $1 AND c.deleted_at IS NULL
       ORDER BY c.created_at DESC`,
      [accountId],
    );
    return {
      channels: rows.map((row) => ({
        ...publicView(row),
        role: row.role,
        // Without these the client cannot tell an owner from a reader, and would
        // hide the controls of someone who holds every permission there is.
        permissions: permissionsFromRow(row),
        // Anyone may pass the link on; it carries no key.
        inviteCode: row.invite_code,
      })),
    };
  });

  /**
   * Find public channels.
   *
   * Search runs over the plaintext title and description of public channels
   * only. A private channel is not listed, not searchable, and not returned by
   * handle — it can only be reached with its invite code.
   */
  app.get('/v1/channels/discover', requireAuth, async (request) => {
    auth(request);
    const query = parse(
      z.object({
        q: z.string().trim().max(64).optional(),
        category: z.string().trim().max(32).optional(),
        limit: z.coerce.number().int().min(1).max(50).default(25),
      }),
      request.query,
    );

    const { rows } = await pool.query(
      `SELECT * FROM channels
       WHERE visibility = 'public' AND deleted_at IS NULL
         AND ($1::text IS NULL OR title ILIKE '%' || $1 || '%'
              OR description ILIKE '%' || $1 || '%'
              OR handle ILIKE '%' || $1 || '%')
         AND ($2::text IS NULL OR category = $2)
       ORDER BY member_count DESC, created_at DESC
       LIMIT $3`,
      [query.q ?? null, query.category ?? null, query.limit],
    );
    return { channels: rows.map(publicView) };
  });

  /** Look a channel up by its invite code, which is how a private one is found. */
  /**
   * A public channel by its handle, which is what a link like
   * `https://privio.channel/houseoftrading` names.
   *
   * Exact rather than a search: discovery ranks by member count and is meant
   * for somebody browsing, while a link names one channel and has to find that
   * one. Public only — a private channel has no handle, and a lookup that
   * could return one would make the handle column a way to find private
   * channels by guessing names.
   */
  app.get('/v1/channels/by-handle/:handle', requireAuth, async (request) => {
    auth(request);
    const params = parse(z.object({ handle: handleSchema }), request.params);
    const { rows } = await pool.query(
      `SELECT * FROM channels
       WHERE handle = $1 AND visibility = 'public' AND deleted_at IS NULL`,
      [params.handle],
    );
    if (!rows[0]) throw ApiError.notFound('channel_not_found', 'No such channel');
    return publicView(rows[0]);
  });

  app.get('/v1/channels/invite/:code', requireAuth, async (request) => {
    auth(request);
    const params = parse(z.object({ code: z.string().min(4).max(64) }), request.params);
    const { rows } = await pool.query(
      'SELECT * FROM channels WHERE invite_code = $1 AND deleted_at IS NULL',
      [params.code],
    );
    if (!rows[0]) throw ApiError.notFound('channel_not_found', 'No such channel');
    return publicView(rows[0]);
  });

  app.get('/v1/channels/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const { rows } = await pool.query('SELECT * FROM channels WHERE id = $1 AND deleted_at IS NULL', [
      params.id,
    ]);
    const channel = rows[0];
    if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');

    const member = await membership(params.id, accountId);
    // A private channel does not confirm its own existence to a stranger.
    if (channel.visibility === 'private' && !member) {
      throw ApiError.notFound('channel_not_found', 'No such channel');
    }
    return {
      ...publicView(channel),
      role: member?.role ?? null,
      permissions: member?.permissions ?? null,
    };
  });

  /**
   * Join.
   *
   * Joining gets you the membership, not the key. An invite link is meant to be
   * shared in public, so it carries no key; the joining device records a key
   * request instead, and a member who already holds the key answers it with an
   * ordinary sealed message. Until that lands, the posts stay unreadable — to
   * the joiner and to the server alike.
   */
  app.post('/v1/channels/:id/join', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({ inviteCode: z.string().min(4).max(64).optional() }),
      request.body ?? {},
    );

    const { rows } = await pool.query('SELECT * FROM channels WHERE id = $1 AND deleted_at IS NULL', [
      params.id,
    ]);
    const channel = rows[0];
    if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');

    const usedTheLink = body.inviteCode === channel.invite_code;
    if (channel.visibility === 'private' && !usedTheLink) {
      // Same answer as a channel that does not exist.
      throw ApiError.notFound('channel_not_found', 'No such channel');
    }

    // Already in, and nothing below should run again for them — not the
    // counter, not the queue.
    const existing = await membership(params.id, accountId);
    if (existing) {
      return { joined: false, role: existing.role, permissions: existing.permissions };
    }

    /*
     * The link's own limits, checked only for somebody who arrived on it. A
     * public channel is joinable without one, and an expired link is not a
     * reason to close a public channel to everybody.
     *
     * The checks answer `invite_expired` rather than "no such channel": the
     * person holding the link already knows the channel exists — they are
     * looking at its preview — so hiding it now would only be confusing. For a
     * private channel a wrong code still answers 404 above, which is the case
     * where the existence is the secret.
     */
    if (usedTheLink) {
      if (channel.invite_expires_at && channel.invite_expires_at.getTime() <= Date.now()) {
        throw ApiError.conflict('invite_expired', 'That invite link has expired');
      }
      if (
        channel.invite_max_uses !== null &&
        channel.invite_uses >= channel.invite_max_uses
      ) {
        throw ApiError.conflict('invite_used_up', 'That invite link has been used up');
      }
    }

    // A channel that asks first puts them in a queue instead of in the room.
    // Only for somebody who came on the link: a public channel's front door is
    // not governed by the link's settings.
    if (usedTheLink && channel.invite_needs_approval) {
      await pool.query(
        `INSERT INTO channel_join_requests (channel_id, account_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [params.id, accountId],
      );
      // No key request and no wake: they are not a member, hold no key, and
      // asking key-holders to seal one to them now would hand the channel to
      // somebody an admin has not let in.
      return { joined: false, pending: true, role: null, permissions: null };
    }

    const joined = await withTransaction(async (client) => {
      const { rowCount } = await client.query(
        `INSERT INTO channel_members (channel_id, account_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [params.id, accountId],
      );
      if (rowCount) {
        await client.query('UPDATE channels SET member_count = member_count + 1 WHERE id = $1', [
          params.id,
        ]);
        // Counted inside the same transaction as the join, so a link with one
        // use left cannot let two people through at once.
        if (usedTheLink) {
          await client.query('UPDATE channels SET invite_uses = invite_uses + 1 WHERE id = $1', [
            params.id,
          ]);
        }
      }
      return (rowCount ?? 0) > 0;
    });

    const member = await membership(params.id, accountId);
    // Ask for the key straight away rather than waiting for the client to think
    // of it: a member who cannot read the channel is the common case here.
    await recordKeyRequest('channel', params.id, accountId, deviceId);
    await wakeKeyHolders(bus, 'channel', params.id, deviceId);
    return { joined, role: member?.role ?? null, permissions: member?.permissions ?? null };
  });

  app.delete('/v1/channels/:id/members/me', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);

    const member = await membership(params.id, accountId);
    if (!member) throw ApiError.notFound('not_a_member', 'You are not in this channel');
    if (member.role === 'owner') {
      throw ApiError.conflict('owner_cannot_leave', 'Hand the channel over or delete it');
    }

    const epoch = await withTransaction(async (client) => {
      // Channel first, then membership — the same order publishing uses, so
      // the two can only queue behind each other and never deadlock.
      await lockChannel(client, params.id, 'update');
      await client.query('DELETE FROM channel_members WHERE channel_id = $1 AND account_id = $2', [
        params.id,
        accountId,
      ]);
      await client.query(
        'UPDATE channels SET member_count = greatest(member_count - 1, 0) WHERE id = $1',
        [params.id],
      );
      // Leaving rotates for the same reason removal does. Someone who walks out
      // still holds the key, and "I left" is not a promise to stop reading.
      return rotateKeyEpoch(client, params.id);
    });
    await clearKeyRequestsFor('channel', params.id, accountId);
    // The remaining members' devices are told, so one of them generates the new
    // key rather than the channel sitting on a rotation nobody has completed.
    await wakeKeyHolders(bus, 'channel', params.id, deviceId);
    return { left: true, keyEpoch: epoch };
  });

  /**
   * Who is in the channel.
   *
   * The audience is not the audience's business. Anyone may join a public
   * channel, so answering every subscriber with the whole list would make
   * "join" the enumeration route this API deliberately does not have — one
   * request and you hold the username of everyone who reads it. A private
   * channel is no better off: its link is meant to be passed around, and the
   * roster should not travel with it.
   *
   * So the full list goes only to a member who can act on it. Everyone else
   * sees the people who run the channel — whose names are already on every
   * post they publish — and their own row, which is what the screen needs to
   * say "you are a subscriber here". `complete` tells the client which of the
   * two it got, so it can label the list honestly instead of presenting a
   * staff list as if it were everybody.
   */
  app.get('/v1/channels/:id/members', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const viewer = await requireMember(params.id, accountId);
    const complete = viewer.permissions.canManageMembers;

    const { rows } = await pool.query(
      `SELECT a.id, a.username, a.display_name, m.role, m.joined_at,
              m.can_post, m.can_edit_channel, m.can_delete_posts,
              m.can_manage_members, m.can_delete_channel
       FROM channel_members m JOIN accounts a ON a.id = m.account_id
       WHERE m.channel_id = $1 AND a.deleted_at IS NULL
         AND ($2::boolean OR m.role <> 'subscriber' OR a.id = $3)
       ORDER BY m.joined_at ASC LIMIT 500`,
      [params.id, complete, accountId],
    );
    return {
      complete,
      members: rows.map((r) => ({
        id: r.id,
        username: r.username,
        displayName: r.display_name,
        role: r.role,
        permissions: permissionsFromRow(r),
        joinedAt: (r.joined_at as Date).toISOString(),
      })),
    };
  });

  /**
   * Set a member's role and what they may do.
   *
   * An admin with `canManageMembers` may appoint other admins — but only with
   * permissions they hold themselves, and only over members who are not already
   * more privileged than they are. Without those two rules, "may appoint
   * admins" is simply "may take the channel over, one step later".
   */
  app.put('/v1/channels/:id/members/:accountId/role', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, accountId: uuidSchema }), request.params);
    const body = parse(
      z.object({
        role: z.enum(['admin', 'subscriber']),
        permissions: permissionsSchema.optional(),
      }),
      request.body,
    );

    if (params.accountId === accountId) {
      throw ApiError.badRequest('cannot_change_own_role', 'You cannot change your own role');
    }

    /*
     * Under the channel lock, and in the same transaction as the write.
     *
     * The two authority rules below — you cannot grant what you do not hold,
     * and you cannot rewrite somebody who outranks you — are read-then-write,
     * which means they were checked against a membership row that another
     * request could change before the UPDATE landed. Two admins demoting each
     * other at the same moment is the shape of it: both read the other as
     * demotable, both write, and the channel ends with neither able to manage
     * anybody.
     *
     * Same lock and same order as publishing and removal, so a permission
     * change and a rotation queue behind one another rather than interleaving.
     */
    const granted = resolvePermissions(body.role, body.permissions);

    await withTransaction(async (client) => {
      await lockChannel(client, params.id, 'update');

      const actor = await requirePermission(
        params.id,
        accountId,
        'canManageMembers',
        client,
      );

      const target = await membership(params.id, params.accountId, client);
      if (!target) throw ApiError.notFound('member_not_found', 'Not a member of this channel');
      if (target.role === 'owner') {
        throw ApiError.forbidden('owner_is_fixed', 'The owner cannot be changed');
      }
      // Nobody may demote or rewrite someone who holds more than they do.
      if (!withinAuthority(actor.permissions, target.permissions)) {
        throw ApiError.forbidden(
          'target_outranks_you',
          'That member holds permissions you do not',
        );
      }
      if (!withinAuthority(actor.permissions, granted)) {
        throw ApiError.forbidden(
          'cannot_grant_what_you_lack',
          'You cannot grant a permission you do not hold',
        );
      }

      await client.query(
        `UPDATE channel_members
         SET role = $3, can_post = $4, can_edit_channel = $5, can_delete_posts = $6,
             can_manage_members = $7, can_delete_channel = $8
         WHERE channel_id = $1 AND account_id = $2 AND role <> 'owner'`,
        [
          params.id,
          params.accountId,
          body.role,
          granted.canPost,
          granted.canEditChannel,
          granted.canDeletePosts,
          granted.canManageMembers,
          granted.canDeleteChannel,
        ],
      );
    });

    return { role: body.role, permissions: granted };
  });

  /** Remove someone from the channel. */
  app.delete('/v1/channels/:id/members/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, accountId: uuidSchema }), request.params);
    const actor = await requirePermission(params.id, accountId, 'canManageMembers');

    const target = await membership(params.id, params.accountId);
    if (!target) throw ApiError.notFound('member_not_found', 'Not a member of this channel');
    if (target.role === 'owner') {
      throw ApiError.forbidden('owner_is_fixed', 'The owner cannot be removed');
    }
    if (!withinAuthority(actor.permissions, target.permissions)) {
      throw ApiError.forbidden('target_outranks_you', 'That member holds permissions you do not');
    }

    const epoch = await withTransaction(async (client) => {
      // Waits for any post already in flight to land at the old epoch, and
      // blocks any that starts after this — which is what makes "no new posts
      // under the old key" true rather than usually true.
      await lockChannel(client, params.id, 'update');
      // Re-checked inside the lock. Two admins removing the same person at the
      // same moment would otherwise both pass the check outside it and advance
      // the epoch twice for one removal.
      const { rowCount } = await client.query(
        'SELECT 1 FROM channel_members WHERE channel_id = $1 AND account_id = $2',
        [params.id, params.accountId],
      );
      if (!rowCount) return null;
      await client.query('DELETE FROM channel_members WHERE channel_id = $1 AND account_id = $2', [
        params.id,
        params.accountId,
      ]);
      await client.query(
        'UPDATE channels SET member_count = greatest(member_count - 1, 0) WHERE id = $1',
        [params.id],
      );
      // In the same transaction as the delete, so there is no moment where the
      // member is gone and the channel is still on the key they hold. Two
      // admins removing two people at once both land here and the epoch simply
      // advances twice; which of them generates the key is settled by the claim
      // below, not by who got here first.
      return rotateKeyEpoch(client, params.id);
    });
    if (epoch === null) {
      // Somebody else removed them first. Their removal did the rotation; doing
      // it again would spend an epoch nobody has a key for and leave the
      // channel unwritable until a device generates one.
      throw ApiError.notFound('member_not_found', 'Not a member of this channel');
    }
    // A request from someone who is no longer a member must not be answered.
    await clearKeyRequestsFor('channel', params.id, params.accountId);
    await wakeKeyHolders(bus, 'channel', params.id, '00000000-0000-0000-0000-000000000000');
    // What removal now takes away is the future, and only the future: the posts
    // they could already read were sealed under an epoch they still hold, and
    // no rotation reaches back into somebody's own storage.
    return { removed: true, keyEpoch: epoch };
  });

  /** Channel settings. Only the parts that are the server's to hold. */
  app.patch('/v1/channels/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        title: z.string().trim().min(1).max(64).optional(),
        description: z.string().trim().max(512).optional(),
        category: z.string().trim().max(32).optional(),
        encryptedMetadata: base64Bytes(1, config.MAX_ENVELOPE_BYTES).optional(),
        /**
         * Which key sealed the metadata being uploaded.
         *
         * A private channel's name is sealed like a post, and until this
         * existed it stayed sealed under epoch 1 forever — so a member who
         * joined after a rotation, and was given only the current key, could
         * read every new post and not the channel's own name. Re-sealing under
         * the current key fixes that without handing over the old message keys.
         */
        metadataKeyEpoch: z.number().int().min(1).optional(),
        restrictSaving: z.boolean().optional(),
        /**
         * The emojis offered under a post. Changing the menu does not touch
         * what is already on a post: taking an emoji off the list is not a
         * reason to silently discard what people have already said with it.
         */
        reactionEmojis: reactionEmojisSchema.optional(),
        /**
         * Whether posts have threads under them.
         *
         * Off by default: a channel is a broadcast, and turning its posts into
         * threads changes what the thing is. Turning it off later hides the
         * threads rather than deleting them — see the comments routes.
         */
        commentsEnabled: z.boolean().optional(),
      }),
      request.body,
    );
    await requirePermission(params.id, accountId, 'canEditChannel');

    // The metadata epoch moves only with the metadata, and only forwards.
    // A re-seal that arrives out of order — two devices re-sealing after the
    // same rotation, one of them slow — must not put the channel's name back
    // under a key that fewer members hold.
    const { rows } = await pool.query(
      `UPDATE channels SET
         title = COALESCE($2, title),
         description = COALESCE($3, description),
         category = COALESCE($4, category),
         encrypted_metadata = COALESCE($5, encrypted_metadata),
         metadata_key_epoch = CASE
           WHEN $5::bytea IS NULL THEN metadata_key_epoch
           WHEN COALESCE($7::int, 1) > metadata_key_epoch THEN COALESCE($7::int, 1)
           ELSE metadata_key_epoch
         END,
         restrict_saving = COALESCE($6, restrict_saving),
         reaction_emojis = COALESCE($8, reaction_emojis),
         comments_enabled = COALESCE($9, comments_enabled)
       WHERE id = $1 RETURNING *`,
      [
        params.id,
        body.title ?? null,
        body.description ?? null,
        body.category ?? null,
        body.encryptedMetadata ?? null,
        body.restrictSaving ?? null,
        body.metadataKeyEpoch ?? null,
        body.reactionEmojis ?? null,
        body.commentsEnabled ?? null,
      ],
    );
    return publicView(rows[0]);
  });

  /**
   * Point the channel at a picture.
   *
   * The bytes went to `/v1/media` first, and **which kind they went up as is
   * the decision**, not a detail:
   *
   *   - a *public* channel uploads `kind=channel_avatar`, unsealed. Its picture
   *     is drawn on the invite page and inside whatever messenger the link was
   *     pasted into, and neither holds a key. Sealing it would mean a public
   *     channel with no picture in any of the places one is looked for — and
   *     its title, description and handle are already plaintext for exactly the
   *     same reason.
   *   - a *private* channel uploads `kind=attachment`, sealed with the channel
   *     key like its name and its posts. The download token travels inside
   *     `encrypted_metadata`, which key rotation already re-seals, so the
   *     picture follows the name without a second mechanism.
   *
   * The server enforces the pairing rather than trusting it: an unsealed
   * `channel_avatar` is readable by anyone who asks (see `mayDownload`), so
   * letting a private channel point at one would quietly publish a picture its
   * owner believes is sealed.
   *
   * The upload has to belong to the caller. Without that check anyone could
   * adopt anyone else's object id and learn, from which error came back,
   * whether it exists.
   */
  app.put('/v1/channels/:id/avatar', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ mediaId: uuidSchema }), request.body);
    await requirePermission(params.id, accountId, 'canEditChannel');

    const { rows: media } = await pool.query<{ kind: string }>(
      'SELECT kind FROM media_objects WHERE id = $1 AND owner_account_id = $2',
      [body.mediaId, accountId],
    );
    if (!media[0]) throw ApiError.notFound('media_not_found', 'No such upload of yours');

    const previous = await withTransaction(async (client) => {
      const { rows: old } = await client.query<{
        visibility: string;
        avatar_media_id: string | null;
      }>(
        'SELECT visibility, avatar_media_id FROM channels WHERE id = $1 AND deleted_at IS NULL FOR UPDATE',
        [params.id],
      );
      const channel = old[0];
      if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');

      const wanted = channel.visibility === 'public' ? 'channel_avatar' : 'attachment';
      if (media[0]!.kind !== wanted) {
        throw ApiError.badRequest(
          'wrong_media_kind',
          channel.visibility === 'public'
            ? "A public channel's picture is uploaded as kind=channel_avatar"
            : "A private channel's picture is sealed and uploaded as kind=attachment",
        );
      }

      await client.query(
        'UPDATE channels SET avatar_media_id = $2, avatar_updated_at = now() WHERE id = $1',
        [params.id, body.mediaId],
      );
      // A picture outlives the attachment retention window. The sweep skips
      // referenced objects too; this keeps the expiry itself honest rather than
      // relying on one of the two.
      await client.query(
        `UPDATE media_objects SET expires_at = now() + interval '100 years' WHERE id = $1`,
        [body.mediaId],
      );
      return channel.avatar_media_id;
    });

    // The old picture is nobody's now: let it fall into the next sweep.
    if (previous && previous !== body.mediaId) {
      await pool.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [previous]);
    }
    return { avatarMediaId: body.mediaId };
  });

  app.delete('/v1/channels/:id/avatar', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requirePermission(params.id, accountId, 'canEditChannel');
    // The CTE is not decoration: `UPDATE ... RETURNING avatar_media_id` hands
    // back the *new* value, which this statement has just set to NULL — so the
    // picture being removed would never be named and would sit in storage
    // until the hundred years ran out. Reading the row first is the only way to
    // learn what was there.
    const { rows } = await pool.query<{ previous: string | null }>(
      `WITH prev AS (
         SELECT id, avatar_media_id FROM channels
          WHERE id = $1 AND deleted_at IS NULL
          FOR UPDATE
       )
       UPDATE channels SET avatar_media_id = NULL, avatar_updated_at = now()
         FROM prev WHERE channels.id = prev.id
       RETURNING prev.avatar_media_id AS previous`,
      [params.id],
    );
    if (!rows[0]) throw ApiError.notFound('channel_not_found', 'No such channel');
    const removed = rows[0].previous;
    if (removed) {
      await pool.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [removed]);
    }
    return { avatarMediaId: null };
  });

  app.delete('/v1/channels/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    // The one action nothing undoes. The owner always may; an admin only with
    // the permission deliberately granted for it.
    await requirePermission(params.id, accountId, 'canDeleteChannel');
    const { rows } = await pool.query<{ avatar_media_id: string | null }>(
      'UPDATE channels SET deleted_at = now() WHERE id = $1 RETURNING avatar_media_id',
      [params.id],
    );
    // The picture was kept alive by being somebody's channel picture, and this
    // is the moment it stops being one. Without this it would sit in storage
    // for a hundred years because nothing was ever going to ask for it again.
    const orphan = rows[0]?.avatar_media_id;
    if (orphan) {
      await pool.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [orphan]);
    }
    return { deleted: true };
  });

  // --- Key versions ---------------------------------------------------------

  /**
   * Claims the current epoch for a key this device has just generated.
   *
   * Two admins removing two people at the same moment is not an exotic case —
   * it is a moderation queue on a busy afternoon. Both devices see the epoch go
   * up, both generate a key, and without something to arbitrate, half the
   * members end up holding one key and half the other, with posts that nobody
   * can read and no error anywhere.
   *
   * So the claim is an insert whose primary key is (channel, epoch), and the
   * database settles it: the first writer wins, the loser is handed the
   * winner's label, throws its own key away and asks for the real one. No
   * locking, no leader election, and no way for the two to disagree.
   *
   * `keyId` is a random label the device invents. It is not derived from the
   * key and reveals nothing about it — its only purpose is to let a device tell
   * "the key I hold for this epoch" from "the key everybody else agreed on".
   * The server still holds no channel key, before or after this call.
   */
  app.post('/v1/channels/:id/key-epochs', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        epoch: z.number().int().min(1),
        keyId: z.string().regex(/^[A-Za-z0-9_-]{8,64}$/),
      }),
      request.body,
    );
    // Only somebody who could have caused a rotation may complete one. A
    // subscriber generating keys would be a subscriber deciding who can read
    // the channel next.
    await requirePermission(params.id, accountId, 'canManageMembers');

    const { rows: channel } = await pool.query<{ key_epoch: number }>(
      'SELECT key_epoch FROM channels WHERE id = $1 AND deleted_at IS NULL',
      [params.id],
    );
    if (channel.length === 0) throw ApiError.notFound('channel_not_found', 'No such channel');
    const current = channel[0]!.key_epoch;

    // Claiming anything but the current epoch is refused. An old one would be a
    // replayed or stale event trying to reinstate a superseded key; a future
    // one does not exist, because only a removal creates an epoch.
    if (body.epoch !== current) {
      throw ApiError.conflict(
        'not_the_current_epoch',
        `This channel is on epoch ${current}`,
      );
    }

    await pool.query(
      `INSERT INTO channel_key_epochs (channel_id, epoch, key_id, claimed_by)
       VALUES ($1, $2, $3, $4) ON CONFLICT (channel_id, epoch) DO NOTHING`,
      [params.id, body.epoch, body.keyId, accountId],
    );

    // Read back rather than trusting the insert: on a conflict nothing was
    // written, and the caller has to be told whose key won.
    //
    // Idempotent by construction. A device whose claim succeeded but whose
    // reply was lost sends the same keyId again, sees `claimed: true` a second
    // time, and carries on — which is the whole point of the keyId being
    // chosen and stored by the client before the request goes out.
    const { rows } = await pool.query<{ key_id: string; claimed_by: string | null }>(
      'SELECT key_id, claimed_by FROM channel_key_epochs WHERE channel_id = $1 AND epoch = $2',
      [params.id, body.epoch],
    );
    const winner = rows[0]!;
    return {
      epoch: body.epoch,
      keyId: winner.key_id,
      claimed: winner.key_id === body.keyId,
    };
  });

  /**
   * Moves past an epoch whose key nobody has.
   *
   * The failure this recovers from: a device advanced the epoch, claimed it,
   * and then died — dropped in a river, wiped, uninstalled — before the key it
   * generated reached anybody, or even before it managed to write the key down.
   * The channel is then stuck. Nobody can publish, because publishing needs a
   * key for the current epoch; nobody can claim it, because claiming it again
   * with a different key would split the channel into two halves holding two
   * keys; and nobody may fall back to the previous key, because that is the one
   * the removed member still has.
   *
   * So the epoch is not reused and not rolled back. It is marked abandoned and
   * the channel moves *forward* to a fresh one, which the caller then claims
   * through the ordinary route.
   *
   * What makes that safe is a check the server can make with no key at all: an
   * abandoned epoch must have no posts. Publishing at epoch N requires holding
   * N's key and the server refuses any other epoch, so an epoch nobody ever
   * held cannot have anything published under it. That is enforced here rather
   * than argued, because "there cannot be any" and "there are none" are
   * different statements and only the second is checkable.
   */
  app.post('/v1/channels/:id/key-epochs/abandon', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ epoch: z.number().int().min(1) }), request.body);
    await requirePermission(params.id, accountId, 'canManageMembers');

    const result = await withTransaction(async (client) => {
      const channel = await lockChannel(client, params.id, 'update');
      if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');

      // Under the lock, so this cannot race a rotation or a publish. The epoch
      // named has to be the one that is actually stuck; anything else is a
      // stale request from a device that has not caught up.
      if (body.epoch !== channel.key_epoch) {
        throw ApiError.conflict('not_the_current_epoch', `This channel is on epoch ${channel.key_epoch}`);
      }

      const { rows: posts } = await client.query<{ count: string }>(
        `SELECT count(*) FROM channel_posts
         WHERE channel_id = $1 AND key_epoch = $2 AND deleted_at IS NULL`,
        [params.id, body.epoch],
      );
      if (Number(posts[0]!.count) > 0) {
        // Somebody does hold this key and has been using it. Abandoning it now
        // would strand posts that people can read, which is the one outcome
        // this whole mechanism exists to avoid.
        throw ApiError.conflict(
          'epoch_has_posts',
          'That key version has posts under it, so somebody holds it',
        );
      }

      await client.query(
        `UPDATE channel_key_epochs SET abandoned_at = now()
         WHERE channel_id = $1 AND epoch = $2 AND abandoned_at IS NULL`,
        [params.id, body.epoch],
      );
      return rotateKeyEpoch(client, params.id);
    });

    return { abandoned: body.epoch, keyEpoch: result };
  });

  /** Which key version is current, and whether anybody has generated it yet. */
  app.get('/v1/channels/:id/key-epochs/current', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMember(params.id, accountId);

    const { rows } = await pool.query<{
      key_epoch: number;
      key_id: string | null;
      claimed_at: Date | null;
      metadata_key_epoch: number;
      posts_at_epoch: string;
    }>(
      `SELECT c.key_epoch, c.metadata_key_epoch, e.key_id, e.claimed_at,
              (SELECT count(*) FROM channel_posts p
                WHERE p.channel_id = c.id AND p.key_epoch = c.key_epoch
                  AND p.deleted_at IS NULL) AS posts_at_epoch
       FROM channels c
       LEFT JOIN channel_key_epochs e
         ON e.channel_id = c.id AND e.epoch = c.key_epoch AND e.abandoned_at IS NULL
       WHERE c.id = $1 AND c.deleted_at IS NULL`,
      [params.id],
    );
    if (rows.length === 0) throw ApiError.notFound('channel_not_found', 'No such channel');
    const row = rows[0]!;
    return {
      epoch: row.key_epoch,
      // Null means the rotation has happened and nobody has generated the new
      // key yet. That is a real state the app has to show, not an error.
      keyId: row.key_id,
      // When it was claimed, so a device can tell "somebody generated this a
      // second ago and it is on its way" from "somebody generated this last
      // week and has not been seen since".
      claimedAt: row.claimed_at ? row.claimed_at.toISOString() : null,
      // Which key opens the channel's own name. Usually the same as the
      // current epoch; behind it only between a rotation and the re-seal.
      metadataKeyEpoch: row.metadata_key_epoch,
      // Whether abandoning this epoch could strand anything readable. Zero is
      // what an orphaned epoch looks like, and it is not a coincidence: you
      // cannot publish at an epoch whose key nobody holds.
      postsAtEpoch: Number(row.posts_at_epoch),
    };
  });

  // --- Key delivery ---------------------------------------------------------

  /** "My device still has no key for this channel." */
  app.post('/v1/channels/:id/key-requests', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMember(params.id, accountId);
    await recordKeyRequest('channel', params.id, accountId, deviceId);
    await wakeKeyHolders(bus, 'channel', params.id, deviceId);
    return { requested: true };
  });

  /**
   * Who is waiting for the key.
   *
   * Open to any member, not just admins: the key is held by everyone who can
   * read the channel, and making delivery wait for an admin to open the app
   * would leave new members staring at padlocks for days.
   */
  app.get('/v1/channels/:id/key-requests', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMember(params.id, accountId);
    return { requests: await pendingKeyRequests('channel', params.id, deviceId) };
  });

  /** Called by whoever answered the request, once the sealed key is on its way. */
  app.delete('/v1/channels/:id/key-requests/:deviceId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, deviceId: uuidSchema }),
      request.params,
    );
    await requireMember(params.id, accountId);
    await clearKeyRequest('channel', params.id, params.deviceId);
    return { cleared: true };
  });

  // --- Posts ----------------------------------------------------------------

  /** Publish a post. The content arrives sealed and is stored as it arrives. */
  app.post('/v1/channels/:id/posts', requireLicensedAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        content: base64Bytes(1, MAX_POST_BYTES),
        mediaId: uuidSchema.optional(),
        /**
         * Which key sealed this. Optional only so that a client from before
         * versioning existed still works; it is treated as epoch 1, which is
         * what such a client's key is.
         */
        keyEpoch: z.number().int().min(1).optional(),
        /**
         * When it becomes visible. Absent means now.
         *
         * A scheduled post is an ordinary row the feed does not select yet —
         * there is no queue and no worker, so there is nothing to fall over
         * and leave a channel silent. See migration 018 for why that works
         * here and what would have to change if a post ever raised a push.
         */
        publishAt: z.coerce.date().optional(),
        /**
         * The *shape* of a poll, never its content.
         *
         * The question and the answers travel inside the sealed payload with
         * the post's text, so the server never learns what was asked. These
         * three numbers are what it needs to enforce a vote being in range,
         * nobody picking four answers in a two-answer poll, and a closed poll
         * staying closed — see migration 020.
         */
        poll: z
          .object({
            optionCount: z.number().int().min(2).max(12),
            maxChoices: z.number().int().min(1).max(12).default(1),
            closesAt: z.coerce.date().optional(),
          })
          .refine((value) => value.maxChoices <= value.optionCount, {
            message: 'maxChoices cannot exceed optionCount',
          })
          .optional(),
      }),
      request.body,
    );
    const postEpoch = body.keyEpoch ?? 1;

    // A time in the past is not scheduling, it is back-dating: it would put a
    // post above ones people have already read. Treated as "now" rather than
    // refused, because a client whose clock is a minute slow is not an error.
    const publishAt =
      body.publishAt && body.publishAt.getTime() > Date.now() ? body.publishAt : null;

    /*
     * The rule that makes a removal mean anything: nothing new under the old
     * key once the rotation has happened.
     *
     * All of it in one transaction, holding the channel's row lock, because
     * the three steps used to be three separate statements and the gap between
     * them was real. The sequence that got through it:
     *
     *   1. the author's permission is checked — still a member, may post
     *   2. an admin removes somebody; the epoch goes 1 → 2 and commits
     *   3. the author's `SELECT key_epoch` had already returned 1
     *   4. the post is inserted at epoch 1 — readable by the person just removed
     *
     * A transaction on its own does not close that: at READ COMMITTED the
     * SELECT would simply see whichever value was committed when it ran, and
     * the INSERT would still land afterwards. What closes it is the lock. The
     * publisher holds the channel row `FOR SHARE` from before the epoch is read
     * until after the post is written, so a rotation — which needs `FOR UPDATE`
     * on the same row — either commits before the read, in which case the stale
     * epoch is refused below, or waits until the post is safely at the epoch
     * that was current when it was checked.
     *
     * The permission check moved inside the same transaction for the same
     * reason: an author whose right to post is revoked in step 2 must not get
     * through on a membership read from step 1.
     *
     * The server still cannot read the post and cannot tell whether the epoch
     * claimed is the epoch actually used. It can only refuse one that admits to
     * a superseded version.
     */
    const created = await withTransaction(async (client) => {
      // Channel first, then membership. Every route in this file takes these
      // two in this order; see lockChannel.
      const channel = await lockChannel(client, params.id, 'share');
      if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');

      await requirePermission(params.id, accountId, 'canPost', client);

      const channelEpoch = channel.key_epoch;
      if (postEpoch < channelEpoch) {
        throw ApiError.conflict(
          'stale_key_epoch',
          `This channel has rotated its key. Seal the post under epoch ${channelEpoch}.`,
        );
      }
      if (postEpoch > channelEpoch) {
        // Ahead of the server is not a thing a correct client can be: the epoch
        // only moves when the server moves it. Refused rather than accepted,
        // because storing a post nobody can place is worse than a failed
        // publish.
        throw ApiError.conflict('unknown_key_epoch', 'That key version does not exist yet');
      }

      if (body.mediaId) {
        const { rowCount } = await client.query(
          'SELECT 1 FROM media_objects WHERE id = $1 AND owner_account_id = $2',
          [body.mediaId, accountId],
        );
        if (!rowCount) throw ApiError.notFound('media_not_found', 'No such upload of yours');
      }

      const { rows } = await client.query(
        `INSERT INTO channel_posts
           (channel_id, author_account_id, content, media_id, key_epoch, publish_at)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, created_at, key_epoch, publish_at`,
        [params.id, accountId, body.content, body.mediaId ?? null, postEpoch, publishAt],
      );
      const created = rows[0];
      if (body.poll) {
        // In the same transaction as the post: a post that claims a poll and
        // has no row for it is a question nobody can answer.
        await client.query(
          `INSERT INTO channel_polls (post_id, option_count, max_choices, closes_at)
           VALUES ($1, $2, $3, $4)`,
          [
            created.id,
            body.poll.optionCount,
            body.poll.maxChoices,
            body.poll.closesAt ?? null,
          ],
        );
      }
      return created;
    });

    reply.code(201);
    return {
      id: created.id,
      keyEpoch: created.key_epoch,
      createdAt: (created.created_at as Date).toISOString(),
      publishAt: (created.publish_at as Date | null)?.toISOString() ?? null,
    };
  });

  /** The feed, newest first. Members only — including for a public channel. */
  app.get('/v1/channels/:id/posts', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const query = parse(
      z.object({
        before: z.coerce.number().int().positive().optional(),
        limit: z.coerce.number().int().min(1).max(100).default(50),
        /**
         * The author's own waiting room: posts whose time has not come.
         *
         * Only for someone who may publish. A subscriber has no business
         * knowing that something is queued, and the ordinary feed never shows
         * it — a scheduled post is invisible until it is due, to everyone.
         */
        scheduled: z.coerce.boolean().optional(),
      }),
      request.query,
    );
    const member = await requireMember(params.id, accountId);
    if (query.scheduled && !member.permissions.canPost) {
      throw ApiError.forbidden('insufficient_permission', 'You need canPost for that');
    }

    /*
     * The counts come back with the feed rather than from a second call: fifty
     * posts would otherwise be fifty round trips, and a reaction bar that
     * appears a second after the post it belongs to is worse than none.
     *
     * Two aggregates, and the difference between them matters. `reactions` is
     * a total per emoji and says nothing about who; `mine` is this reader's
     * own, which they are entitled to because they put it there. Nobody is
     * ever served the list of who reacted — see migration 017 for what the
     * server does and does not hold here.
     */
    const { rows } = await pool.query(
      `SELECT p.id, p.author_account_id, a.username AS author_username,
              p.content, p.media_id, p.pinned, p.created_at, p.key_epoch,
              p.edited_at, p.publish_at,
              COALESCE(r.counts, '{}'::jsonb) AS reactions,
              COALESCE(m.mine, ARRAY[]::text[]) AS mine,
              COALESCE(c.n, 0) AS comment_count,
              poll.option_count, poll.max_choices, poll.closes_at,
              v.counts AS vote_counts, vp.voters,
              COALESCE(mv.mine, ARRAY[]::smallint[]) AS my_votes
       FROM channel_posts p
       LEFT JOIN accounts a ON a.id = p.author_account_id
       LEFT JOIN LATERAL (
         SELECT jsonb_object_agg(emoji, n) AS counts
         FROM (
           SELECT emoji, count(*) AS n
           FROM channel_post_reactions
           WHERE post_id = p.id
           GROUP BY emoji
         ) AS per_emoji
       ) AS r ON true
       LEFT JOIN LATERAL (
         SELECT array_agg(emoji) AS mine
         FROM channel_post_reactions
         WHERE post_id = p.id AND account_id = $4
       ) AS m ON true
       -- How many replies, so a post can say "3 comments" without the screen
       -- fetching every thread it scrolls past.
       LEFT JOIN LATERAL (
         SELECT count(*)::int AS n
         FROM channel_post_comments
         WHERE post_id = p.id AND deleted_at IS NULL
       ) AS c ON true
       LEFT JOIN channel_polls poll ON poll.post_id = p.id
       -- A tally per option, and how many people took part. Two laterals and
       -- not one: folding them together needs a UNION whose other half has no
       -- option_index, and jsonb_object_agg throws on a null key rather than
       -- skipping the row. The feed died for every poll until a test asked for
       -- one. (No backticks in here: this is a template literal.)
       LEFT JOIN LATERAL (
         SELECT jsonb_object_agg(option_index, n) AS counts
         FROM (
           SELECT option_index, count(*)::int AS n
           FROM channel_poll_votes WHERE post_id = p.id GROUP BY option_index
         ) AS per_option
       ) AS v ON poll.post_id IS NOT NULL
       -- Not the sum of the above: in a poll that takes several answers one
       -- person is several votes, and "42 people voted" is what a reader means.
       LEFT JOIN LATERAL (
         SELECT count(DISTINCT account_id)::int AS voters
         FROM channel_poll_votes WHERE post_id = p.id
       ) AS vp ON poll.post_id IS NOT NULL
       LEFT JOIN LATERAL (
         SELECT array_agg(option_index) AS mine
         FROM channel_poll_votes
         WHERE post_id = p.id AND account_id = $4
       ) AS mv ON poll.post_id IS NOT NULL
       WHERE p.channel_id = $1 AND p.deleted_at IS NULL
         AND ($2::bigint IS NULL OR p.id < $2)
         AND CASE WHEN $5::boolean
                  THEN p.publish_at IS NOT NULL AND p.publish_at > now()
                  ELSE p.publish_at IS NULL OR p.publish_at <= now()
             END
       ORDER BY p.id DESC LIMIT $3`,
      [params.id, query.before ?? null, query.limit, accountId, query.scheduled ?? false],
    );

    return {
      posts: rows.map((r) => ({
        id: r.id,
        authorAccountId: r.author_account_id,
        authorUsername: r.author_username,
        content: (r.content as Buffer).toString('base64'),
        mediaId: r.media_id,
        pinned: r.pinned,
        reactions: r.reactions,
        myReactions: r.mine,
        // Null unless somebody changed it after people could already read it.
        commentCount: r.comment_count,
        // Null unless this post is a poll. The question and the answers are
        // not here — they are inside `content`, sealed.
        poll:
          r.option_count === null
            ? null
            : {
                optionCount: r.option_count,
                maxChoices: r.max_choices,
                closesAt: (r.closes_at as Date | null)?.toISOString() ?? null,
                counts: r.vote_counts ?? {},
                voters: r.voters ?? 0,
                myVotes: r.my_votes ?? [],
              },
        editedAt: (r.edited_at as Date | null)?.toISOString() ?? null,
        publishAt: (r.publish_at as Date | null)?.toISOString() ?? null,
        // So a reader knows which key a post needs, rather than inferring it
        // from a decryption that failed. A padlock that can say "waiting for
        // the key from 12 March" is a different thing from one that cannot.
        keyEpoch: r.key_epoch ?? 1,
        createdAt: (r.created_at as Date).toISOString(),
      })),
      more: rows.length === query.limit,
    };
  });

  /**
   * Changing a post after it is out.
   *
   * **Only the author.** An admin who can delete a post cannot rewrite it:
   * every post carries its author's name, so editing somebody else's words
   * would be putting words in their mouth under their own byline. Deleting is
   * the moderation tool, and it is honest about what it is.
   *
   * The new text arrives sealed, like the old one, and under the same epoch
   * rule — an edit prepared before a rotation must not land under the key
   * somebody was just removed from. Same lock, same refusal as publishing.
   *
   * `edited_at` is set only when the post was already visible. Changing one
   * that is still scheduled leaves no mark, because nobody read the earlier
   * version and there is nothing to disclose.
   */
  app.patch('/v1/channels/:id/posts/:postId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(
      z.object({
        content: base64Bytes(1, MAX_POST_BYTES),
        keyEpoch: z.number().int().min(1).optional(),
        /** Moves a scheduled post. Null publishes it now. */
        publishAt: z.coerce.date().nullable().optional(),
      }),
      request.body,
    );
    const postEpoch = body.keyEpoch ?? 1;

    const updated = await withTransaction(async (client) => {
      const channel = await lockChannel(client, params.id, 'share');
      if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');
      await requirePermission(params.id, accountId, 'canPost', client);

      if (postEpoch < channel.key_epoch) {
        throw ApiError.conflict(
          'stale_key_epoch',
          `This channel has rotated its key. Seal the post under epoch ${channel.key_epoch}.`,
        );
      }
      if (postEpoch > channel.key_epoch) {
        throw ApiError.conflict('unknown_key_epoch', 'That key version does not exist yet');
      }

      const { rows: existing } = await client.query<{
        author_account_id: string | null;
        publish_at: Date | null;
      }>(
        `SELECT author_account_id, publish_at FROM channel_posts
         WHERE id = $1 AND channel_id = $2 AND deleted_at IS NULL`,
        [params.postId, params.id],
      );
      const post = existing[0];
      if (!post) throw ApiError.notFound('post_not_found', 'No such post');
      if (post.author_account_id !== accountId) {
        throw ApiError.forbidden('not_the_author', 'Only the author can change a post');
      }

      // Was it already out? That is what decides whether this leaves a mark.
      const wasVisible = post.publish_at === null || post.publish_at.getTime() <= Date.now();

      // `publishAt` absent leaves the schedule alone; null publishes now; a
      // future time moves it. A past time is "now", for the same reason as
      // when publishing.
      const reschedule = body.publishAt !== undefined;
      const nextPublishAt = !reschedule
        ? post.publish_at
        : body.publishAt && body.publishAt.getTime() > Date.now()
          ? body.publishAt
          : null;

      const { rows } = await client.query(
        `UPDATE channel_posts
         SET content = $3, key_epoch = $4, publish_at = $5,
             edited_at = CASE WHEN $6::boolean THEN now() ELSE edited_at END
         WHERE id = $1 AND channel_id = $2
         RETURNING id, created_at, edited_at, publish_at, key_epoch`,
        [params.postId, params.id, body.content, postEpoch, nextPublishAt, wasVisible],
      );
      return rows[0];
    });

    return {
      id: updated.id,
      keyEpoch: updated.key_epoch,
      createdAt: (updated.created_at as Date).toISOString(),
      editedAt: (updated.edited_at as Date | null)?.toISOString() ?? null,
      publishAt: (updated.publish_at as Date | null)?.toISOString() ?? null,
    };
  });

  /**
   * Handing the channel to somebody else.
   *
   * **The password, not the session.** Every other admin action here trusts
   * the signed-in device, and that is right for actions an owner can undo.
   * This one they cannot: afterwards they are an admin in somebody else's
   * channel, and the person who now owns it can remove them. A phone left
   * unlocked on a table should not be able to give a channel away.
   *
   * The new owner has to be a member already. Handing a channel to somebody
   * who is not in it would put a stranger in charge of a key they do not hold.
   *
   * The old owner stays as an admin with everything they had. They are not
   * removed and not demoted to a reader: a handover is not an ejection, and
   * whoever takes over can do either afterwards if that is what was meant.
   */
  app.post('/v1/channels/:id/owner', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        accountId: uuidSchema,
        currentPassword: z.string().min(1),
      }),
      request.body,
    );

    if (body.accountId === accountId) {
      throw ApiError.badRequest('already_the_owner', 'You already own this channel');
    }

    const { rows: accounts } = await pool.query<{ password_hash: string }>(
      'SELECT password_hash FROM accounts WHERE id = $1 AND deleted_at IS NULL',
      [accountId],
    );
    const hash = accounts[0]?.password_hash;
    if (!hash || !(await verifySecret(hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'That password is not right');
    }

    await withTransaction(async (client) => {
      // Same lock and same order as every other two-row change in this file.
      await lockChannel(client, params.id, 'update');

      const actor = await membership(params.id, accountId, client);
      if (actor?.role !== 'owner') {
        throw ApiError.forbidden('not_the_owner', 'Only the owner can hand a channel on');
      }
      const target = await membership(params.id, body.accountId, client);
      if (!target) {
        throw ApiError.notFound('member_not_found', 'They are not in this channel');
      }

      await client.query(
        `UPDATE channel_members
         SET role = 'owner', can_post = true, can_edit_channel = true,
             can_delete_posts = true, can_manage_members = true, can_delete_channel = true
         WHERE channel_id = $1 AND account_id = $2`,
        [params.id, body.accountId],
      );
      // Everything they had, minus the one thing that is now somebody else's.
      await client.query(
        `UPDATE channel_members
         SET role = 'admin', can_delete_channel = false
         WHERE channel_id = $1 AND account_id = $2`,
        [params.id, accountId],
      );
      await client.query(
        'UPDATE channels SET owner_account_id = $2 WHERE id = $1',
        [params.id, body.accountId],
      );
      // Who gave it away and when. A role column cannot answer that, and it is
      // the first question an owner who loses a channel asks.
      await client.query(
        `INSERT INTO channel_ownership_transfers (channel_id, from_account_id, to_account_id)
         VALUES ($1, $2, $3)`,
        [params.id, accountId, body.accountId],
      );
    });

    return { owner: body.accountId };
  });

  /**
   * Reporting a channel.
   *
   * The reason is one of a fixed set, not free text — and that is the
   * interesting decision. A free field is a place for somebody to paste the
   * content they are reporting, which would put the very thing the encryption
   * protects into a readable column, written by a person with every reason to.
   *
   * What a report can deliver is limited by the same design: the server cannot
   * read the posts, so an operator gets the channel's id and the reason. For a
   * public channel there is also the title, description and handle, which are
   * plaintext for search. For a private one there is nothing to look at. The
   * screen says so rather than implying an investigation that cannot happen.
   */
  app.post('/v1/channels/:id/report', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        reason: z.enum(['spam', 'abuse', 'illegal', 'impersonation', 'other']),
      }),
      request.body,
    );

    const { rowCount } = await pool.query(
      'SELECT 1 FROM channels WHERE id = $1 AND deleted_at IS NULL',
      [params.id],
    );
    if (!rowCount) throw ApiError.notFound('channel_not_found', 'No such channel');

    // One standing report per person per channel: reporting twice is not twice
    // as true, and a counter somebody can run up is a way to brigade a channel.
    await pool.query(
      `INSERT INTO channel_reports (channel_id, account_id, reason)
       VALUES ($1, $2, $3)
       ON CONFLICT (channel_id, account_id) DO UPDATE SET reason = $3, reported_at = now()`,
      [params.id, accountId, body.reason],
    );
    return { reported: true };
  });

  /**
   * What a channel amounts to, for whoever runs it.
   *
   * Everything here is counted from rows that exist for their own reasons —
   * members, posts, reactions, comments, votes. **There is no view count**, and
   * that is a decision rather than an omission: counting who has read a post,
   * deduplicated, means a row per reader per post, which is a record of what
   * each person read. That is a larger disclosure than anything else in a
   * channel and it would be made by people who are only reading. See
   * docs/security-model.md.
   */
  app.get('/v1/channels/:id/stats', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requirePermission(params.id, accountId, 'canEditChannel');

    const { rows } = await pool.query(
      `SELECT
         (SELECT member_count FROM channels WHERE id = $1) AS members,
         (SELECT count(*)::int FROM channel_posts
           WHERE channel_id = $1 AND deleted_at IS NULL
             AND (publish_at IS NULL OR publish_at <= now())) AS posts,
         (SELECT count(*)::int FROM channel_posts
           WHERE channel_id = $1 AND deleted_at IS NULL
             AND publish_at > now()) AS scheduled,
         (SELECT count(*)::int FROM channel_post_reactions r
            JOIN channel_posts p ON p.id = r.post_id
           WHERE p.channel_id = $1) AS reactions,
         (SELECT count(*)::int FROM channel_post_comments c
            JOIN channel_posts p ON p.id = c.post_id
           WHERE p.channel_id = $1 AND c.deleted_at IS NULL) AS comments,
         (SELECT count(DISTINCT v.account_id)::int FROM channel_poll_votes v
            JOIN channel_posts p ON p.id = v.post_id
           WHERE p.channel_id = $1) AS poll_voters,
         (SELECT count(*)::int FROM channel_bans WHERE channel_id = $1) AS silenced,
         (SELECT count(*)::int FROM channel_join_requests WHERE channel_id = $1) AS waiting`,
      [params.id],
    );
    const row = rows[0] ?? {};
    return {
      members: row.members ?? 0,
      posts: row.posts ?? 0,
      scheduled: row.scheduled ?? 0,
      reactions: row.reactions ?? 0,
      comments: row.comments ?? 0,
      pollVoters: row.poll_voters ?? 0,
      silenced: row.silenced ?? 0,
      waiting: row.waiting ?? 0,
    };
  });

  /**
   * What the invite link is allowed to do.
   *
   * `canManageMembers`, because that is the right that decides who is in the
   * channel, and a link is a standing offer of membership. Every field is
   * optional and absent means "leave it"; null clears a limit.
   */
  app.put('/v1/channels/:id/invite', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        expiresAt: z.coerce.date().nullable().optional(),
        maxUses: z.number().int().min(1).max(100_000).nullable().optional(),
        needsApproval: z.boolean().optional(),
      }),
      request.body ?? {},
    );
    await requirePermission(params.id, accountId, 'canManageMembers');

    // A time already gone is not a setting, it is a revocation with extra
    // steps — and rotating the code is the honest way to do that.
    if (body.expiresAt && body.expiresAt.getTime() <= Date.now()) {
      throw ApiError.badRequest('expiry_in_the_past', 'Pick a time that has not gone yet');
    }

    const { rows } = await pool.query(
      `UPDATE channels SET
         invite_expires_at = CASE WHEN $2::boolean THEN $3 ELSE invite_expires_at END,
         invite_max_uses   = CASE WHEN $4::boolean THEN $5 ELSE invite_max_uses END,
         invite_needs_approval = COALESCE($6, invite_needs_approval)
       WHERE id = $1 AND deleted_at IS NULL RETURNING *`,
      [
        params.id,
        body.expiresAt !== undefined,
        body.expiresAt ?? null,
        body.maxUses !== undefined,
        body.maxUses ?? null,
        body.needsApproval ?? null,
      ],
    );
    if (!rows[0]) throw ApiError.notFound('channel_not_found', 'No such channel');
    return { ...publicView(rows[0]), inviteCode: rows[0].invite_code };
  });

  /**
   * Revoking the link, which is rotating it.
   *
   * There is no list of past codes and no grace period: the old one stops
   * resolving the moment this returns, wherever it was pasted. The counter
   * goes back to zero with it, because a use limit belongs to the link that
   * was handed out and not to the channel.
   */
  app.post('/v1/channels/:id/invite/rotate', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requirePermission(params.id, accountId, 'canManageMembers');

    const { rows } = await pool.query(
      `UPDATE channels SET invite_code = $2, invite_uses = 0
       WHERE id = $1 AND deleted_at IS NULL RETURNING *`,
      [params.id, randomBytes(9).toString('base64url')],
    );
    if (!rows[0]) throw ApiError.notFound('channel_not_found', 'No such channel');
    return { ...publicView(rows[0]), inviteCode: rows[0].invite_code };
  });

  /**
   * Who is waiting at the door.
   *
   * `canManageMembers` — and it is a queue of people who are *not* in the
   * channel, so unlike the members list there is no version of this for
   * everybody else.
   */
  app.get('/v1/channels/:id/join-requests', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requirePermission(params.id, accountId, 'canManageMembers');

    const { rows } = await pool.query(
      `SELECT r.account_id, a.username, a.display_name, r.requested_at
       FROM channel_join_requests r
       LEFT JOIN accounts a ON a.id = r.account_id
       WHERE r.channel_id = $1
       ORDER BY r.requested_at ASC`,
      [params.id],
    );
    return {
      requests: rows.map((r) => ({
        accountId: r.account_id,
        username: r.username,
        displayName: r.display_name,
        requestedAt: (r.requested_at as Date).toISOString(),
      })),
    };
  });

  /** Letting somebody in. The link's use counter moves here, not at the knock. */
  app.post('/v1/channels/:id/join-requests/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, accountId: uuidSchema }),
      request.params,
    );
    await requirePermission(params.id, accountId, 'canManageMembers');

    const admitted = await withTransaction(async (client) => {
      const { rowCount: knocked } = await client.query(
        'DELETE FROM channel_join_requests WHERE channel_id = $1 AND account_id = $2',
        [params.id, params.accountId],
      );
      if (!knocked) return false;

      const { rowCount } = await client.query(
        `INSERT INTO channel_members (channel_id, account_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [params.id, params.accountId],
      );
      if (rowCount) {
        await client.query(
          `UPDATE channels SET member_count = member_count + 1, invite_uses = invite_uses + 1
           WHERE id = $1`,
          [params.id],
        );
      }
      return true;
    });
    if (!admitted) throw ApiError.notFound('no_such_request', 'Nobody is waiting under that name');

    // No key request recorded here, and no wake. A key is sealed to a *device*,
    // and the admin approving this is not at the new member's — so the asking
    // is theirs to do, which their client already does for every channel it is
    // in without a key.
    return { admitted: true };
  });

  /** Turning somebody away. They are told nothing; the queue simply empties. */
  app.delete('/v1/channels/:id/join-requests/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, accountId: uuidSchema }),
      request.params,
    );
    await requirePermission(params.id, accountId, 'canManageMembers');

    await pool.query(
      'DELETE FROM channel_join_requests WHERE channel_id = $1 AND account_id = $2',
      [params.id, params.accountId],
    );
    return { admitted: false };
  });

  /** One poll's tallies, for the answer a vote gets. */
  async function tallyOf(
    postId: number,
    accountId: string,
  ): Promise<{ counts: Record<number, number>; voters: number; myVotes: number[] }> {
    const { rows } = await pool.query<{ option_index: number; n: number; mine: boolean }>(
      `SELECT option_index, count(*)::int AS n,
              bool_or(account_id = $2) AS mine
       FROM channel_poll_votes WHERE post_id = $1
       GROUP BY option_index`,
      [postId, accountId],
    );
    const { rows: people } = await pool.query<{ voters: number }>(
      'SELECT count(DISTINCT account_id)::int AS voters FROM channel_poll_votes WHERE post_id = $1',
      [postId],
    );
    const counts: Record<number, number> = {};
    const myVotes: number[] = [];
    for (const row of rows) {
      counts[row.option_index] = row.n;
      if (row.mine) myVotes.push(row.option_index);
    }
    return { counts, voters: people[0]?.voters ?? 0, myVotes };
  }

  /**
   * Voting, and changing your mind.
   *
   * The whole of this account's answer is sent each time and replaces what was
   * there — not "add one vote", because changing a single-choice answer is
   * otherwise two calls with a moment in between where the person has voted
   * twice or not at all. An empty list takes the vote back.
   *
   * The server checks the shape it is holding: every index inside the poll's
   * options, no more picks than the poll allows, and nothing after it closed.
   * It is doing that without knowing what any of the options say.
   */
  app.put('/v1/channels/:id/posts/:postId/votes', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(
      z.object({
        options: z.array(z.number().int().min(0).max(11)).max(12),
      }),
      request.body,
    );
    await requireMember(params.id, accountId);
    // A silenced member does not get a vote either: it is the same voice.
    await requireNotBanned(params.id, accountId);

    await withTransaction(async (client) => {
      const { rows } = await client.query<{
        option_count: number;
        max_choices: number;
        closes_at: Date | null;
      }>(
        `SELECT poll.option_count, poll.max_choices, poll.closes_at
         FROM channel_polls poll
         JOIN channel_posts p ON p.id = poll.post_id
         WHERE poll.post_id = $1 AND p.channel_id = $2 AND p.deleted_at IS NULL
           AND (p.publish_at IS NULL OR p.publish_at <= now())`,
        [params.postId, params.id],
      );
      const poll = rows[0];
      if (!poll) throw ApiError.notFound('poll_not_found', 'No such poll');

      if (poll.closes_at && poll.closes_at.getTime() <= Date.now()) {
        throw ApiError.conflict('poll_closed', 'This poll has closed');
      }

      // Duplicates in the request would otherwise buy extra picks past the
      // limit, and the primary key would silently swallow them.
      const chosen = [...new Set(body.options)];
      if (chosen.some((index) => index >= poll.option_count)) {
        throw ApiError.badRequest('option_out_of_range', 'That is not one of the answers');
      }
      if (chosen.length > poll.max_choices) {
        throw ApiError.badRequest(
          'too_many_choices',
          `This poll takes ${poll.max_choices} answer${poll.max_choices === 1 ? '' : 's'}`,
        );
      }

      // Replace rather than add: the request is the whole answer.
      await client.query(
        'DELETE FROM channel_poll_votes WHERE post_id = $1 AND account_id = $2',
        [params.postId, accountId],
      );
      for (const index of chosen) {
        await client.query(
          `INSERT INTO channel_poll_votes (post_id, account_id, option_index)
           VALUES ($1, $2, $3)`,
          [params.postId, accountId, index],
        );
      }
    });

    return tallyOf(params.postId, accountId);
  });

  /**
   * Whether this account is barred from speaking in a channel.
   *
   * Separate from membership on purpose: removing somebody rotates the key and
   * cuts them off from everything, which is the right answer to "should not be
   * here" and far too heavy an answer to "will not stop arguing under every
   * post". A ban silences; it does not blind.
   */
  async function isBanned(
    channelId: string,
    accountId: string,
    client: Queryable = pool,
  ): Promise<boolean> {
    const { rowCount } = await client.query(
      'SELECT 1 FROM channel_bans WHERE channel_id = $1 AND account_id = $2',
      [channelId, accountId],
    );
    return (rowCount ?? 0) > 0;
  }

  /** Refuses a member who has been silenced, saying so rather than pretending. */
  async function requireNotBanned(
    channelId: string,
    accountId: string,
    client: Queryable = pool,
  ): Promise<void> {
    if (await isBanned(channelId, accountId, client)) {
      throw ApiError.forbidden('banned', 'An admin has stopped you posting in this channel');
    }
  }

  /**
   * A comment on a post.
   *
   * Sealed exactly like the post it hangs under: same channel key, same epoch,
   * same refusal under a superseded one. The server stores ciphertext and
   * cannot read a word of it, which is why moderation here can only ever be
   * "remove this row" and "stop this account writing more" — there is no
   * filtering a server cannot read.
   *
   * Any member may comment, not only those who may post. That is the point of
   * turning threads on at all.
   */
  app.post('/v1/channels/:id/posts/:postId/comments', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(
      z.object({
        content: base64Bytes(1, MAX_POST_BYTES),
        keyEpoch: z.number().int().min(1).optional(),
      }),
      request.body,
    );
    const commentEpoch = body.keyEpoch ?? 1;

    const created = await withTransaction(async (client) => {
      const channel = await lockChannel(client, params.id, 'share');
      if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');
      if (!channel.comments_enabled) {
        throw ApiError.conflict('comments_disabled', 'This channel has comments turned off');
      }
      await requireMember(params.id, accountId, client);
      await requireNotBanned(params.id, accountId, client);

      if (commentEpoch < channel.key_epoch) {
        throw ApiError.conflict(
          'stale_key_epoch',
          `This channel has rotated its key. Seal the comment under epoch ${channel.key_epoch}.`,
        );
      }
      if (commentEpoch > channel.key_epoch) {
        throw ApiError.conflict('unknown_key_epoch', 'That key version does not exist yet');
      }

      // Within the channel, and only a post that is actually out: a thread
      // under something still scheduled would tell a subscriber it exists.
      const { rowCount } = await client.query(
        `SELECT 1 FROM channel_posts
         WHERE id = $1 AND channel_id = $2 AND deleted_at IS NULL
           AND (publish_at IS NULL OR publish_at <= now())`,
        [params.postId, params.id],
      );
      if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');

      const { rows } = await client.query(
        `INSERT INTO channel_post_comments (post_id, author_account_id, content, key_epoch)
         VALUES ($1, $2, $3, $4) RETURNING id, created_at, key_epoch`,
        [params.postId, accountId, body.content, commentEpoch],
      );
      return rows[0];
    });

    reply.code(201);
    return {
      id: created.id,
      keyEpoch: created.key_epoch,
      createdAt: (created.created_at as Date).toISOString(),
    };
  });

  /** The thread, oldest first — a conversation reads forwards. */
  app.get('/v1/channels/:id/posts/:postId/comments', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const query = parse(
      z.object({
        after: z.coerce.number().int().positive().optional(),
        limit: z.coerce.number().int().min(1).max(200).default(100),
      }),
      request.query,
    );
    await requireMember(params.id, accountId);

    const { rows } = await pool.query(
      `SELECT c.id, c.author_account_id, a.username AS author_username,
              c.content, c.key_epoch, c.created_at
       FROM channel_post_comments c
       JOIN channel_posts p ON p.id = c.post_id AND p.channel_id = $1
       LEFT JOIN accounts a ON a.id = c.author_account_id
       WHERE c.post_id = $2 AND c.deleted_at IS NULL
         AND ($3::bigint IS NULL OR c.id > $3)
       ORDER BY c.id ASC LIMIT $4`,
      [params.id, params.postId, query.after ?? null, query.limit],
    );

    return {
      comments: rows.map((r) => ({
        id: r.id,
        authorAccountId: r.author_account_id,
        authorUsername: r.author_username,
        content: (r.content as Buffer).toString('base64'),
        keyEpoch: r.key_epoch ?? 1,
        createdAt: (r.created_at as Date).toISOString(),
      })),
      more: rows.length === query.limit,
    };
  });

  /**
   * Removing a comment: its author, or an admin who may delete posts.
   *
   * Overwritten rather than tombstoned, like a post, so a removed comment does
   * not sit on disk waiting for a key to turn up.
   */
  app.delete(
    '/v1/channels/:id/posts/:postId/comments/:commentId',
    requireAuth,
    async (request) => {
      const { accountId } = auth(request);
      const params = parse(
        z.object({
          id: uuidSchema,
          postId: z.coerce.number().int().positive(),
          commentId: z.coerce.number().int().positive(),
        }),
        request.params,
      );
      const member = await requireMember(params.id, accountId);

      const { rows } = await pool.query<{ author_account_id: string | null }>(
        `SELECT c.author_account_id
         FROM channel_post_comments c
         JOIN channel_posts p ON p.id = c.post_id AND p.channel_id = $1
         WHERE c.id = $2 AND c.post_id = $3 AND c.deleted_at IS NULL`,
        [params.id, params.commentId, params.postId],
      );
      const comment = rows[0];
      if (!comment) throw ApiError.notFound('comment_not_found', 'No such comment');

      const isAuthor = comment.author_account_id === accountId;
      if (!isAuthor && !member.permissions.canDeletePosts) {
        throw ApiError.forbidden('insufficient_permission', 'You need canDeletePosts for that');
      }

      await pool.query(
        'UPDATE channel_post_comments SET deleted_at = now(), content = $2 WHERE id = $1',
        [params.commentId, Buffer.alloc(0)],
      );
      return { deleted: true };
    },
  );

  /**
   * Silencing somebody, and letting them speak again.
   *
   * Needs `canManageMembers`, the same right that removes people, because it
   * is the lighter half of the same decision. An owner cannot be silenced —
   * there would be no way back — and neither can you silence yourself into a
   * channel you run.
   */
  app.put('/v1/channels/:id/bans/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, accountId: uuidSchema }),
      request.params,
    );
    const actor = await requirePermission(params.id, accountId, 'canManageMembers');

    const target = await membership(params.id, params.accountId);
    if (!target) throw ApiError.notFound('not_a_member', 'They are not in this channel');
    if (target.role === 'owner') {
      throw ApiError.forbidden('cannot_ban_owner', 'The owner cannot be silenced');
    }
    // An admin silencing another admin would be a way around the permission
    // system: whoever may manage members may remove them, and that is the
    // decision with a record.
    if (target.role === 'admin' && actor.role !== 'owner') {
      throw ApiError.forbidden('cannot_ban_admin', 'Only the owner can silence an admin');
    }

    await pool.query(
      `INSERT INTO channel_bans (channel_id, account_id, banned_by)
       VALUES ($1, $2, $3) ON CONFLICT (channel_id, account_id) DO NOTHING`,
      [params.id, params.accountId, accountId],
    );
    return { banned: true };
  });

  app.delete('/v1/channels/:id/bans/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, accountId: uuidSchema }),
      request.params,
    );
    await requirePermission(params.id, accountId, 'canManageMembers');

    await pool.query('DELETE FROM channel_bans WHERE channel_id = $1 AND account_id = $2', [
      params.id,
      params.accountId,
    ]);
    return { banned: false };
  });

  /** Who is silenced. Admins only — it is a moderation record, not a roster. */
  app.get('/v1/channels/:id/bans', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requirePermission(params.id, accountId, 'canManageMembers');

    const { rows } = await pool.query(
      `SELECT b.account_id, a.username, b.created_at
       FROM channel_bans b
       LEFT JOIN accounts a ON a.id = b.account_id
       WHERE b.channel_id = $1
       ORDER BY b.created_at DESC`,
      [params.id],
    );
    return {
      banned: rows.map((r) => ({
        accountId: r.account_id,
        username: r.username,
        since: (r.created_at as Date).toISOString(),
      })),
    };
  });

  app.put('/v1/channels/:id/posts/:postId/pin', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(z.object({ pinned: z.boolean() }), request.body);
    await requirePermission(params.id, accountId, 'canEditChannel');

    const { rowCount } = await pool.query(
      'UPDATE channel_posts SET pinned = $3 WHERE channel_id = $1 AND id = $2 AND deleted_at IS NULL',
      [params.id, params.postId, body.pinned],
    );
    if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');
    return { pinned: body.pinned };
  });

  /**
   * The counts on one post, for the reply to a reaction that just changed.
   *
   * Returned rather than leaving the client to reload the feed: a tap that
   * needs fifty posts fetched again to show a number going up is a tap that
   * looks broken on a slow connection.
   */
  async function reactionsOn(
    postId: number,
    accountId: string,
    client: Queryable = pool,
  ): Promise<{ reactions: Record<string, number>; myReactions: string[] }> {
    const { rows } = await client.query(
      `SELECT emoji, count(*)::int AS n,
              bool_or(account_id = $2) AS mine
       FROM channel_post_reactions
       WHERE post_id = $1
       GROUP BY emoji`,
      [postId, accountId],
    );
    const reactions: Record<string, number> = {};
    const myReactions: string[] = [];
    for (const row of rows as { emoji: string; n: number; mine: boolean }[]) {
      reactions[row.emoji] = row.n;
      if (row.mine) myReactions.push(row.emoji);
    }
    return { reactions, myReactions };
  }

  /**
   * Reacting to a post.
   *
   * Any member may, including one who cannot publish — that is the point of a
   * channel's audience having a voice at all. The emoji has to be one the
   * channel offers: an unchecked value here is a way to write arbitrary text
   * under somebody else's post.
   *
   * The post is looked up **within the channel** rather than by id alone, so a
   * member of one channel cannot react to a post in another by guessing a
   * number. Post ids are a global sequence; they are not a secret and are not
   * treated as one.
   */
  app.put('/v1/channels/:id/posts/:postId/reactions', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(z.object({ emoji: reactionEmojiSchema }), request.body);
    await requireMember(params.id, accountId);
    // A reaction is a way of speaking too. An admin who silenced somebody
    // would not expect them to go on stamping emojis on every post.
    await requireNotBanned(params.id, accountId);

    const { rows: channels } = await pool.query<{ reaction_emojis: string[] }>(
      'SELECT reaction_emojis FROM channels WHERE id = $1 AND deleted_at IS NULL',
      [params.id],
    );
    const offered = channels[0]?.reaction_emojis ?? [];
    if (!offered.includes(body.emoji)) {
      throw ApiError.badRequest('emoji_not_offered', 'That is not one of this channel\'s reactions');
    }

    const { rowCount } = await pool.query(
      'SELECT 1 FROM channel_posts WHERE id = $1 AND channel_id = $2 AND deleted_at IS NULL',
      [params.postId, params.id],
    );
    if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');

    // Idempotent: a double tap on a slow connection is one reaction, not an
    // error the screen has to explain.
    await pool.query(
      `INSERT INTO channel_post_reactions (post_id, account_id, emoji)
       VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
      [params.postId, accountId, body.emoji],
    );
    return reactionsOn(params.postId, accountId);
  });

  /** Taking one back. Only ever your own — there is no route to remove anyone else's. */
  app.delete('/v1/channels/:id/posts/:postId/reactions', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const query = parse(z.object({ emoji: reactionEmojiSchema }), request.query);
    await requireMember(params.id, accountId);

    await pool.query(
      `DELETE FROM channel_post_reactions r
       USING channel_posts p
       WHERE r.post_id = p.id AND p.channel_id = $1
         AND r.post_id = $2 AND r.account_id = $3 AND r.emoji = $4`,
      [params.id, params.postId, accountId, query.emoji],
    );
    // No 404 for a reaction that was not there: the end state is the same, and
    // saying which it was tells a caller what somebody else's row contains.
    return reactionsOn(params.postId, accountId);
  });

  app.delete('/v1/channels/:id/posts/:postId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    await requirePermission(params.id, accountId, 'canDeletePosts');

    const rowCount = await withTransaction(async (client) => {
      const { rowCount: deleted } = await client.query(
        'UPDATE channel_posts SET deleted_at = now(), content = $3 WHERE channel_id = $1 AND id = $2 AND deleted_at IS NULL',
        // Overwrite rather than tombstone the ciphertext: a deleted post should
        // not sit on disk waiting for a key to turn up.
        [params.id, params.postId, Buffer.alloc(0)],
      );
      // And the reactions with it. The row stays — the id is a foreign key
      // several things point at — so the `ON DELETE CASCADE` on those rows
      // never fires, and without this the record of who responded to a post
      // outlives the post itself. That is the one piece of metadata a channel
      // holds in the clear (migration 017); it has no business surviving the
      // thing it was about.
      if (deleted) {
        await client.query('DELETE FROM channel_post_reactions WHERE post_id = $1', [
          params.postId,
        ]);
        // And the thread under it, for the same reason and then one more: a
        // comment is ciphertext, and a removed post must not leave a pile of
        // it on disk waiting for a key. Hard-deleted rather than tombstoned,
        // because the post they hang under is gone and nothing will ever ask
        // for them again.
        await client.query('DELETE FROM channel_post_comments WHERE post_id = $1', [
          params.postId,
        ]);
        // And the poll, if it was one. Third time this list has grown, and
        // always for the same reason: the post delete is a soft delete, so
        // nothing that hangs off the row goes with it on its own. Anything
        // added here later has to be added here too.
        await client.query('DELETE FROM channel_polls WHERE post_id = $1', [params.postId]);
      }
      return deleted;
    });
    if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');
    return { deleted: true };
  });
};

export default channelRoutes;
