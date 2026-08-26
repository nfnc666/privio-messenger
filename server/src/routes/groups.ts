import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, uuidSchema } from '../util/validate.js';

const MAX_MEMBERS = 512;

async function requireMembership(groupId: string, accountId: string, mustBeAdmin = false) {
  const { rows } = await pool.query<{ role: string }>(
    `SELECT m.role FROM group_members m JOIN groups g ON g.id = m.group_id
     WHERE m.group_id = $1 AND m.account_id = $2 AND g.deleted_at IS NULL`,
    [groupId, accountId],
  );
  const role = rows[0]?.role;
  if (!role) throw ApiError.forbidden('not_a_member', 'You are not a member of this group');
  if (mustBeAdmin && role !== 'admin') throw ApiError.forbidden('not_an_admin', 'Admin role required');
  return role;
}

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
const groupRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  app.post('/v1/groups', requireAuth, async (request, reply) => {
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
        'INSERT INTO groups (creator_account_id, encrypted_metadata) VALUES ($1, $2) RETURNING id',
        [accountId, body.encryptedMetadata ?? null],
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

    reply.code(201);
    return { id: groupId, members: await membersOf(groupId) };
  });

  app.get('/v1/groups', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT g.id, g.encrypted_metadata, g.created_at, m.role,
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
        memberCount: Number(r.member_count),
        encryptedMetadata: r.encrypted_metadata ? (r.encrypted_metadata as Buffer).toString('base64') : null,
        createdAt: (r.created_at as Date).toISOString(),
      })),
    };
  });

  app.get('/v1/groups/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const role = await requireMembership(params.id, accountId);
    const { rows } = await pool.query(
      'SELECT id, encrypted_metadata, created_at FROM groups WHERE id = $1',
      [params.id],
    );
    const group = rows[0]!;
    return {
      id: group.id,
      role,
      encryptedMetadata: group.encrypted_metadata ? (group.encrypted_metadata as Buffer).toString('base64') : null,
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
      z.object({ encryptedMetadata: base64Bytes(1, config.MAX_ENVELOPE_BYTES) }),
      request.body,
    );
    await requireMembership(params.id, accountId, true);
    await pool.query('UPDATE groups SET encrypted_metadata = $2 WHERE id = $1', [
      params.id,
      body.encryptedMetadata,
    ]);
    return { updated: true };
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

  app.delete('/v1/groups/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await requireMembership(params.id, accountId, true);
    await pool.query('UPDATE groups SET deleted_at = now() WHERE id = $1', [params.id]);
    return { deleted: true };
  });
};

export default groupRoutes;
