import type { FastifyPluginAsync } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, uuidSchema } from '../util/validate.js';

const MAX_POST_BYTES = 256 * 1024;

const handleSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9_.]{3,32}$/, 'must be 3-32 characters of a-z, 0-9, underscore or dot');

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
    memberCount: row.member_count,
    createdAt: (row.created_at as Date).toISOString(),
  };
}

async function membership(channelId: string, accountId: string) {
  const { rows } = await pool.query<{ role: string }>(
    `SELECT m.role FROM channel_members m
     JOIN channels c ON c.id = m.channel_id
     WHERE m.channel_id = $1 AND m.account_id = $2 AND c.deleted_at IS NULL`,
    [channelId, accountId],
  );
  return rows[0]?.role ?? null;
}

async function requireRole(channelId: string, accountId: string, roles: string[]) {
  const role = await membership(channelId, accountId);
  if (!role) throw ApiError.forbidden('not_a_member', 'You are not in this channel');
  if (!roles.includes(role)) {
    throw ApiError.forbidden('insufficient_role', 'You do not have permission for that');
  }
  return role;
}

const channelRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  /**
   * Create a channel.
   *
   * The caller generates the channel key and keeps it. Nothing in this request
   * carries it, which is what lets the server host a channel it cannot read.
   */
  app.post('/v1/channels', requireAuth, async (request, reply) => {
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
        `INSERT INTO channel_members (channel_id, account_id, role) VALUES ($1, $2, 'owner')`,
        [rows[0].id, accountId],
      );
      return rows[0];
    });

    reply.code(201);
    return { ...publicView(channel), role: 'owner', inviteCode };
  });

  /** The channels this account is in. */
  app.get('/v1/channels', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT c.*, m.role FROM channel_members m
       JOIN channels c ON c.id = m.channel_id
       WHERE m.account_id = $1 AND c.deleted_at IS NULL
       ORDER BY c.created_at DESC`,
      [accountId],
    );
    return {
      channels: rows.map((row) => ({
        ...publicView(row),
        role: row.role,
        // Only someone who can invite needs the code.
        inviteCode: row.role === 'subscriber' ? null : row.invite_code,
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

    const role = await membership(params.id, accountId);
    // A private channel does not confirm its own existence to a stranger.
    if (channel.visibility === 'private' && !role) {
      throw ApiError.notFound('channel_not_found', 'No such channel');
    }
    return { ...publicView(channel), role };
  });

  /**
   * Join.
   *
   * Joining gets you the membership, not the key: the key travels in the invite
   * link's fragment or from an admin, never through here. A client that joins a
   * public channel it found by search still has to be given the key before any
   * post means anything.
   */
  app.post('/v1/channels/:id/join', requireAuth, async (request) => {
    const { accountId } = auth(request);
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

    if (channel.visibility === 'private' && body.inviteCode !== channel.invite_code) {
      // Same answer as a channel that does not exist.
      throw ApiError.notFound('channel_not_found', 'No such channel');
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
      }
      return (rowCount ?? 0) > 0;
    });

    return { joined, role: await membership(params.id, accountId) };
  });

  app.delete('/v1/channels/:id/members/me', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);

    const role = await membership(params.id, accountId);
    if (!role) throw ApiError.notFound('not_a_member', 'You are not in this channel');
    if (role === 'owner') {
      throw ApiError.conflict('owner_cannot_leave', 'Hand the channel over or delete it');
    }

    await withTransaction(async (client) => {
      await client.query('DELETE FROM channel_members WHERE channel_id = $1 AND account_id = $2', [
        params.id,
        accountId,
      ]);
      await client.query(
        'UPDATE channels SET member_count = greatest(member_count - 1, 0) WHERE id = $1',
        [params.id],
      );
    });
    return { left: true };
  });

  app.get('/v1/channels/:id/members', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireRole(params.id, accountId, ['owner', 'admin', 'subscriber']);

    const { rows } = await pool.query(
      `SELECT a.id, a.username, a.display_name, m.role, m.joined_at
       FROM channel_members m JOIN accounts a ON a.id = m.account_id
       WHERE m.channel_id = $1 AND a.deleted_at IS NULL
       ORDER BY m.joined_at ASC LIMIT 500`,
      [params.id],
    );
    return {
      members: rows.map((r) => ({
        id: r.id,
        username: r.username,
        displayName: r.display_name,
        role: r.role,
        joinedAt: (r.joined_at as Date).toISOString(),
      })),
    };
  });

  app.put('/v1/channels/:id/members/:accountId/role', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, accountId: uuidSchema }), request.params);
    const body = parse(z.object({ role: z.enum(['admin', 'subscriber']) }), request.body);
    // Only the owner changes roles: an admin promoting admins is how a channel
    // gets taken over.
    await requireRole(params.id, accountId, ['owner']);

    const { rowCount } = await pool.query(
      `UPDATE channel_members SET role = $3
       WHERE channel_id = $1 AND account_id = $2 AND role <> 'owner'`,
      [params.id, params.accountId, body.role],
    );
    if (!rowCount) throw ApiError.notFound('member_not_found', 'Not a member of this channel');
    return { role: body.role };
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
        restrictSaving: z.boolean().optional(),
      }),
      request.body,
    );
    await requireRole(params.id, accountId, ['owner', 'admin']);

    const { rows } = await pool.query(
      `UPDATE channels SET
         title = COALESCE($2, title),
         description = COALESCE($3, description),
         category = COALESCE($4, category),
         encrypted_metadata = COALESCE($5, encrypted_metadata),
         restrict_saving = COALESCE($6, restrict_saving)
       WHERE id = $1 RETURNING *`,
      [
        params.id,
        body.title ?? null,
        body.description ?? null,
        body.category ?? null,
        body.encryptedMetadata ?? null,
        body.restrictSaving ?? null,
      ],
    );
    return publicView(rows[0]);
  });

  app.delete('/v1/channels/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireRole(params.id, accountId, ['owner']);
    await pool.query('UPDATE channels SET deleted_at = now() WHERE id = $1', [params.id]);
    return { deleted: true };
  });

  // --- Posts ----------------------------------------------------------------

  /** Publish a post. The content arrives sealed and is stored as it arrives. */
  app.post('/v1/channels/:id/posts', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        content: base64Bytes(1, MAX_POST_BYTES),
        mediaId: uuidSchema.optional(),
      }),
      request.body,
    );
    await requireRole(params.id, accountId, ['owner', 'admin']);

    if (body.mediaId) {
      const { rowCount } = await pool.query(
        'SELECT 1 FROM media_objects WHERE id = $1 AND owner_account_id = $2',
        [body.mediaId, accountId],
      );
      if (!rowCount) throw ApiError.notFound('media_not_found', 'No such upload of yours');
    }

    const { rows } = await pool.query(
      `INSERT INTO channel_posts (channel_id, author_account_id, content, media_id)
       VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
      [params.id, accountId, body.content, body.mediaId ?? null],
    );
    reply.code(201);
    return {
      id: rows[0].id,
      createdAt: (rows[0].created_at as Date).toISOString(),
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
      }),
      request.query,
    );
    await requireRole(params.id, accountId, ['owner', 'admin', 'subscriber']);

    const { rows } = await pool.query(
      `SELECT p.id, p.author_account_id, a.username AS author_username,
              p.content, p.media_id, p.pinned, p.created_at
       FROM channel_posts p
       LEFT JOIN accounts a ON a.id = p.author_account_id
       WHERE p.channel_id = $1 AND p.deleted_at IS NULL
         AND ($2::bigint IS NULL OR p.id < $2)
       ORDER BY p.id DESC LIMIT $3`,
      [params.id, query.before ?? null, query.limit],
    );

    return {
      posts: rows.map((r) => ({
        id: r.id,
        authorAccountId: r.author_account_id,
        authorUsername: r.author_username,
        content: (r.content as Buffer).toString('base64'),
        mediaId: r.media_id,
        pinned: r.pinned,
        createdAt: (r.created_at as Date).toISOString(),
      })),
      more: rows.length === query.limit,
    };
  });

  app.put('/v1/channels/:id/posts/:postId/pin', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    const body = parse(z.object({ pinned: z.boolean() }), request.body);
    await requireRole(params.id, accountId, ['owner', 'admin']);

    const { rowCount } = await pool.query(
      'UPDATE channel_posts SET pinned = $3 WHERE channel_id = $1 AND id = $2 AND deleted_at IS NULL',
      [params.id, params.postId, body.pinned],
    );
    if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');
    return { pinned: body.pinned };
  });

  app.delete('/v1/channels/:id/posts/:postId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(
      z.object({ id: uuidSchema, postId: z.coerce.number().int().positive() }),
      request.params,
    );
    await requireRole(params.id, accountId, ['owner', 'admin']);

    const { rowCount } = await pool.query(
      'UPDATE channel_posts SET deleted_at = now(), content = $3 WHERE channel_id = $1 AND id = $2 AND deleted_at IS NULL',
      // Overwrite rather than tombstone the ciphertext: a deleted post should
      // not sit on disk waiting for a key to turn up.
      [params.id, params.postId, Buffer.alloc(0)],
    );
    if (!rowCount) throw ApiError.notFound('post_not_found', 'No such post');
    return { deleted: true };
  });
};

export default channelRoutes;
