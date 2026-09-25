import type { FastifyPluginAsync } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import type { DeliveryBus } from '../services/bus.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import { requireGroupMembership } from '../services/group_membership.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, uuidSchema } from '../util/validate.js';
import {
  clearKeyRequest,
  clearKeyRequestsFor,
  pendingKeyRequests,
  recordKeyRequest,
  wakeKeyHolders,
} from '../services/key_requests.js';

const MAX_MEMBERS = 512;

/// Shared with the bot routes, which manage a group's bots and must refuse a
/// member exactly as these routes do. See `services/group_membership.ts`.
const requireMembership = requireGroupMembership;

async function membersOf(groupId: string) {
  const { rows } = await pool.query(
    `SELECT a.id, a.username, a.display_name, m.role, m.added_at
     FROM group_members m JOIN accounts a ON a.id = m.account_id
     WHERE m.group_id = $1 AND a.deleted_at IS NULL
     ORDER BY m.added_at ASC`,
    [groupId],
  );
  return rows.map((r) => ({
    id: r.id,
    username: r.username,
    displayName: r.display_name,
    role: r.role,
    addedAt: (r.added_at as Date).toISOString(),
  }));
}

/**
 * The server keeps a membership list because it has to fan messages out, but the
 * group's name, avatar and history live only in `encrypted_metadata` and in the
 * ciphertext the members exchange.
 */
/// Takes the bus so a key request can wake the devices that could answer it.
const groupRoutes = (bus: DeliveryBus): FastifyPluginAsync => async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };
  // Creating something new is gated on a license where the deployment sells
  // access; reading and joining are not.
  const requireLicensedAuth = {
    preHandler: [
      (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
      (r: Parameters<typeof app.requireLicense>[0]) => app.requireLicense(r),
    ],
  };

  app.post('/v1/groups', requireLicensedAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({
        encryptedMetadata: base64Bytes(1, config.MAX_ENVELOPE_BYTES).optional(),
        memberIds: z.array(uuidSchema).max(MAX_MEMBERS - 1).default([]),
      }),
      request.body,
    );

    const invitees = [...new Set(body.memberIds)].filter((id) => id !== accountId);
    const groupId = await withTransaction(async (client) => {
      const { rows } = await client.query<{ id: string }>(
        `INSERT INTO groups (creator_account_id, encrypted_metadata, invite_code)
         VALUES ($1, $2, $3) RETURNING id`,
        [accountId, body.encryptedMetadata ?? null, randomBytes(9).toString('base64url')],
      );
      const id = rows[0]!.id;
      await client.query(
        `INSERT INTO group_members (group_id, account_id, role) VALUES ($1, $2, 'admin')`,
        [id, accountId],
      );
      if (invitees.length) {
        // Members who restrict group invites to contacts are only added when the
        // creator is in their contact list.
        await client.query(
          `INSERT INTO group_members (group_id, account_id)
           SELECT $1, a.id FROM accounts a
           WHERE a.id = ANY($2::uuid[]) AND a.deleted_at IS NULL
             AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.account_id = a.id AND b.blocked_account_id = $3)
             AND (
               COALESCE(a.privacy->>'whoCanAddMeToGroups', 'everyone') <> 'contacts'
               OR EXISTS (SELECT 1 FROM contacts c WHERE c.account_id = a.id AND c.contact_account_id = $3)
             )
           ON CONFLICT DO NOTHING`,
          [id, invitees, accountId],
        );
      }
      return id;
    });

    const { rows: codeRows } = await pool.query<{ invite_code: string }>(
      'SELECT invite_code FROM groups WHERE id = $1',
      [groupId],
    );
    reply.code(201);
    return {
      id: groupId,
      inviteCode: codeRows[0]!.invite_code,
      members: await membersOf(groupId),
    };
  });

  app.get('/v1/groups', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT g.id, g.encrypted_metadata, g.created_at, g.invite_code, m.role,
              (SELECT count(*) FROM group_members x WHERE x.group_id = g.id) AS member_count
       FROM group_members m JOIN groups g ON g.id = m.group_id
       WHERE m.account_id = $1 AND g.deleted_at IS NULL
       ORDER BY g.created_at DESC`,
      [accountId],
    );
    return {
      groups: rows.map((r) => ({
        id: r.id,
        role: r.role,
        inviteCode: r.invite_code,
        memberCount: Number(r.member_count),
        encryptedMetadata: r.encrypted_metadata ? (r.encrypted_metadata as Buffer).toString('base64') : null,
        encryptedDescription: r.encrypted_description
          ? (r.encrypted_description as Buffer).toString('base64')
          : null,
        avatarMediaId: r.avatar_media_id ?? null,
        avatarUpdatedAt: (r.avatar_updated_at as Date | null)?.toISOString() ?? null,
        createdAt: (r.created_at as Date).toISOString(),
      })),
    };
  });

  app.get('/v1/groups/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const role = await requireMembership(params.id, accountId);
    const { rows } = await pool.query(
      `SELECT id, encrypted_metadata, encrypted_description, avatar_media_id,
              avatar_updated_at, created_at, invite_code
         FROM groups WHERE id = $1`,
      [params.id],
    );
    const group = rows[0]!;
    return {
      id: group.id,
      role,
      inviteCode: group.invite_code,
      encryptedMetadata: group.encrypted_metadata ? (group.encrypted_metadata as Buffer).toString('base64') : null,
      encryptedDescription: group.encrypted_description
        ? (group.encrypted_description as Buffer).toString('base64')
        : null,
      avatarMediaId: group.avatar_media_id ?? null,
      avatarUpdatedAt: (group.avatar_updated_at as Date | null)?.toISOString() ?? null,
      createdAt: (group.created_at as Date).toISOString(),
      members: await membersOf(params.id),
    };
  });

  /**
   * Every device that must receive a copy of the next message: all members'
   * active devices, including the sender's *other* devices so multi-device stays
   * in sync, but never the calling device itself. This is exactly the set the
   * send endpoint expects back.
   */
  app.get('/v1/groups/:id/devices', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId);
    const { rows } = await pool.query(
      `SELECT d.id, d.account_id, a.username, d.device_index, d.registration_id, d.identity_key
       FROM group_members m
       JOIN devices d ON d.account_id = m.account_id AND d.revoked_at IS NULL
       JOIN accounts a ON a.id = m.account_id
       WHERE m.group_id = $1 AND d.id <> $2 ORDER BY d.id`,
      [params.id, deviceId],
    );
    return {
      devices: rows.map((r) => ({
        deviceId: r.id,
        accountId: r.account_id,
        // So a sender missing a session can fetch that member's prekey bundle.
        // Bundles are deliberately not returned here: they consume a one-time
        // prekey, and most sends already have a session for every device.
        username: r.username,
        deviceIndex: r.device_index,
        registrationId: r.registration_id,
        identityKey: (r.identity_key as Buffer).toString('base64'),
      })),
    };
  });

  app.patch('/v1/groups/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z
        .object({
          encryptedMetadata: base64Bytes(1, config.MAX_ENVELOPE_BYTES).optional(),
          /**
           * The group's description, sealed with the group key.
           *
           * `null` clears it, which is a different request from leaving the
           * field out — omitting it keeps whatever is there, so a screen that
           * only changes the name cannot wipe the description by not
           * mentioning it.
           */
          encryptedDescription: base64Bytes(1, config.MAX_ENVELOPE_BYTES).nullable().optional(),
        })
        .refine(
          (v) => v.encryptedMetadata !== undefined || v.encryptedDescription !== undefined,
          { message: 'nothing to update' },
        ),
      request.body,
    );
    await requireMembership(params.id, accountId, true);
    // Two optional fields, one statement, and `COALESCE` is deliberately not
    // used for the description: it cannot tell "leave it alone" from "clear
    // it", and those are the two things this route has to keep apart.
    if (body.encryptedMetadata !== undefined) {
      await pool.query('UPDATE groups SET encrypted_metadata = $2 WHERE id = $1', [
        params.id,
        body.encryptedMetadata,
      ]);
    }
    if (body.encryptedDescription !== undefined) {
      await pool.query('UPDATE groups SET encrypted_description = $2 WHERE id = $1', [
        params.id,
        body.encryptedDescription,
      ]);
    }
    return { updated: true };
  });

  /**
   * Sets the group's picture.
   *
   * The bytes went to `/v1/media` first as `kind=group_avatar`, unsealed —
   * see migration 036 for why a picture is not treated like a message. This
   * only points the group at an object the caller already owns, which is what
   * stops one account attaching another's upload.
   *
   * Admins only, like the name and the disappearing timer: a picture everybody
   * can change is a picture somebody changes at three in the morning.
   */
  app.put('/v1/groups/:id/avatar', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ mediaId: uuidSchema }), request.body);
    await requireMembership(params.id, accountId, true);

    const replaced = await withTransaction(async (client) => {
      const { rows: groups } = await client.query<{ avatar_media_id: string | null }>(
        'SELECT avatar_media_id FROM groups WHERE id = $1 AND deleted_at IS NULL FOR UPDATE',
        [params.id],
      );
      const group = groups[0];
      if (!group) throw ApiError.notFound('group_not_found', 'No such group');

      const { rows: media } = await client.query<{ kind: string; owner_account_id: string }>(
        'SELECT kind, owner_account_id FROM media_objects WHERE id = $1',
        [body.mediaId],
      );
      if (!media[0] || media[0].owner_account_id !== accountId) {
        throw ApiError.notFound('media_not_found', 'No such upload');
      }
      if (media[0].kind !== 'group_avatar') {
        throw ApiError.badRequest(
          'wrong_media_kind',
          "A group's picture is uploaded as kind=group_avatar",
        );
      }

      await client.query(
        'UPDATE groups SET avatar_media_id = $2, avatar_updated_at = now() WHERE id = $1',
        [params.id, body.mediaId],
      );
      return group.avatar_media_id;
    });

    // The one it replaced is nobody's picture now. Left to the ordinary
    // retention sweep rather than deleted here: a device that is still drawing
    // the old one should finish doing so.
    void replaced;
    return { avatarMediaId: body.mediaId };
  });

  /** Takes the group's picture away. Admins only, as above. */
  app.delete('/v1/groups/:id/avatar', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId, true);
    await pool.query(
      'UPDATE groups SET avatar_media_id = NULL, avatar_updated_at = now() WHERE id = $1',
      [params.id],
    );
    return { avatarMediaId: null };
  });

  app.post('/v1/groups/:id/members', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ memberIds: z.array(uuidSchema).min(1).max(64) }), request.body);
    await requireMembership(params.id, accountId, true);

    const { rows: sizeRows } = await pool.query<{ count: string }>(
      'SELECT count(*) FROM group_members WHERE group_id = $1',
      [params.id],
    );
    if (Number(sizeRows[0]!.count) + body.memberIds.length > MAX_MEMBERS) {
      throw ApiError.conflict('group_full', `Groups hold at most ${MAX_MEMBERS} members`);
    }

    const { rows } = await pool.query<{ account_id: string }>(
      `INSERT INTO group_members (group_id, account_id)
       SELECT $1, a.id FROM accounts a
       WHERE a.id = ANY($2::uuid[]) AND a.deleted_at IS NULL
         AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.account_id = a.id AND b.blocked_account_id = $3)
         AND (
           COALESCE(a.privacy->>'whoCanAddMeToGroups', 'everyone') <> 'contacts'
           OR EXISTS (SELECT 1 FROM contacts c WHERE c.account_id = a.id AND c.contact_account_id = $3)
         )
       ON CONFLICT DO NOTHING
       RETURNING account_id`,
      [params.id, body.memberIds, accountId],
    );
    return { added: rows.map((r) => r.account_id), members: await membersOf(params.id) };
  });

  /** Admins remove anyone; members can always remove themselves (leave). */
  app.delete('/v1/groups/:id/members/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, accountId: uuidSchema }), request.params);
    await requireMembership(params.id, accountId, params.accountId !== accountId);

    const { rowCount } = await pool.query(
      'DELETE FROM group_members WHERE group_id = $1 AND account_id = $2',
      [params.id, params.accountId],
    );
    if (!rowCount) throw ApiError.notFound('member_not_found', 'Not a member of this group');
    await clearKeyRequestsFor('group', params.id, params.accountId);

    // Never strand a group without an admin: promote the longest-standing member.
    await pool.query(
      `UPDATE group_members SET role = 'admin'
       WHERE (group_id, account_id) IN (
         SELECT group_id, account_id FROM group_members
         WHERE group_id = $1 ORDER BY added_at ASC LIMIT 1
       )
       AND NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = $1 AND role = 'admin')`,
      [params.id],
    );
    return { removed: true };
  });

  app.put('/v1/groups/:id/members/:accountId/role', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, accountId: uuidSchema }), request.params);
    const body = parse(z.object({ role: z.enum(['admin', 'member']) }), request.body);
    await requireMembership(params.id, accountId, true);

    if (body.role === 'member' && params.accountId === accountId) {
      const { rows } = await pool.query<{ count: string }>(
        `SELECT count(*) FROM group_members WHERE group_id = $1 AND role = 'admin'`,
        [params.id],
      );
      if (Number(rows[0]!.count) <= 1) {
        throw ApiError.conflict('last_admin', 'Promote another admin first');
      }
    }
    const { rowCount } = await pool.query(
      'UPDATE group_members SET role = $3 WHERE group_id = $1 AND account_id = $2',
      [params.id, params.accountId, body.role],
    );
    if (!rowCount) throw ApiError.notFound('member_not_found', 'Not a member of this group');
    return { role: body.role };
  });

  /**
   * Look a group up by its invite code.
   *
   * Answers with the sealed metadata and nothing else: the name of the group is
   * encrypted, so this tells a stranger only that the code is valid.
   */
  app.get('/v1/groups/invite/:code', requireAuth, async (request) => {
    auth(request);
    const params = parse(z.object({ code: z.string().min(4).max(64) }), request.params);
    const { rows } = await pool.query(
      `SELECT id, encrypted_metadata, created_at,
              (SELECT count(*) FROM group_members m WHERE m.group_id = groups.id) AS member_count
       FROM groups WHERE invite_code = $1 AND deleted_at IS NULL`,
      [params.code],
    );
    const group = rows[0];
    if (!group) throw ApiError.notFound('group_not_found', 'No such group');
    return {
      id: group.id,
      memberCount: Number(group.member_count),
      encryptedMetadata: group.encrypted_metadata
        ? (group.encrypted_metadata as Buffer).toString('base64')
        : null,
      createdAt: (group.created_at as Date).toISOString(),
    };
  });

  /**
   * Join with an invite code.
   *
   * The code is the whole of the authorisation — a group has no public
   * directory, so holding the link is what it means to have been invited. The
   * key to the group's name is not here; the joining device asks for it below.
   */
  app.post('/v1/groups/:id/join', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ inviteCode: z.string().min(4).max(64) }), request.body);

    const { rows } = await pool.query<{ invite_code: string | null }>(
      'SELECT invite_code FROM groups WHERE id = $1 AND deleted_at IS NULL',
      [params.id],
    );
    if (!rows[0] || rows[0].invite_code !== body.inviteCode) {
      // A wrong code is answered the same way as a group that does not exist.
      throw ApiError.notFound('group_not_found', 'No such group');
    }

    const { rows: sizeRows } = await pool.query<{ count: string }>(
      'SELECT count(*) FROM group_members WHERE group_id = $1',
      [params.id],
    );
    if (Number(sizeRows[0]!.count) >= MAX_MEMBERS) {
      throw ApiError.conflict('group_full', `Groups hold at most ${MAX_MEMBERS} members`);
    }

    const { rowCount } = await pool.query(
      'INSERT INTO group_members (group_id, account_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [params.id, accountId],
    );
    await recordKeyRequest('group', params.id, accountId, deviceId);
    await wakeKeyHolders(bus, 'group', params.id, deviceId);
    return { joined: (rowCount ?? 0) > 0, members: await membersOf(params.id) };
  });

  // --- Key delivery ---------------------------------------------------------

  app.post('/v1/groups/:id/key-requests', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId);
    await recordKeyRequest('group', params.id, accountId, deviceId);
    await wakeKeyHolders(bus, 'group', params.id, deviceId);
    return { requested: true };
  });

  app.get('/v1/groups/:id/key-requests', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId);
    return { requests: await pendingKeyRequests('group', params.id, deviceId) };
  });

  app.delete('/v1/groups/:id/key-requests/:deviceId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, deviceId: uuidSchema }), request.params);
    await requireMembership(params.id, accountId);
    await clearKeyRequest('group', params.id, params.deviceId);
    return { cleared: true };
  });

  app.delete('/v1/groups/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId, true);
    await pool.query('UPDATE groups SET deleted_at = now() WHERE id = $1', [params.id]);
    return { deleted: true };
  });
};

export default groupRoutes;
