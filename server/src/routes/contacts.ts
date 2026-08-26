import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import { findByUsername, publicProfile, type AccountRow } from '../services/accounts.js';
import { ApiError } from '../util/errors.js';
import { parse, usernameSchema, uuidSchema } from '../util/validate.js';

/** Applies the target's last-seen privacy setting from the viewer's perspective. */
async function visibleLastSeen(viewerId: string, target: AccountRow): Promise<string | null> {
  const setting = target.privacy?.lastSeen ?? 'contacts';
  if (setting === 'nobody') return null;
  if (setting === 'everyone') return target.last_seen_at.toISOString();
  const { rowCount } = await pool.query(
    'SELECT 1 FROM contacts WHERE account_id = $1 AND contact_account_id = $2',
    [target.id, viewerId],
  );
  return rowCount ? target.last_seen_at.toISOString() : null;
}

const contactRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  /**
   * Exact-username lookup only. There is no prefix or fuzzy search on purpose:
   * a substring endpoint would let anyone enumerate the user base.
   */
  app.get('/v1/users/:username', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ username: usernameSchema }), request.params);
    const target = await findByUsername(params.username);
    if (!target) throw ApiError.notFound('user_not_found', 'No such user');
    return {
      ...publicProfile(target),
      lastSeenAt: await visibleLastSeen(accountId, target),
    };
  });

  /**
   * Resolve an account id to a profile.
   *
   * Needed so a message from someone not yet in your contacts can show who sent
   * it. This is not an enumeration route: account ids are random UUIDs, and the
   * only way to learn one is to have received something from that account.
   */
  app.get('/v1/users/id/:accountId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ accountId: uuidSchema }), request.params);
    const { rows } = await pool.query<AccountRow>(
      'SELECT * FROM accounts WHERE id = $1 AND deleted_at IS NULL',
      [params.accountId],
    );
    const target = rows[0];
    if (!target) throw ApiError.notFound('user_not_found', 'No such user');
    return {
      ...publicProfile(target),
      lastSeenAt: await visibleLastSeen(accountId, target),
    };
  });

  /** A shareable invite the client renders as a link and a QR code. */
  app.get('/v1/contacts/invite', requireAuth, async (request) => {
    const { username } = auth(request);
    return { username, inviteUrl: `https://privio.app/u/${username}`, deepLink: `privio://u/${username}` };
  });

  app.get('/v1/contacts', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT a.id, a.username, a.display_name, a.avatar_media_id, a.avatar_updated_at,
              c.alias, c.created_at
       FROM contacts c JOIN accounts a ON a.id = c.contact_account_id
       WHERE c.account_id = $1 AND a.deleted_at IS NULL
       ORDER BY COALESCE(c.alias, a.display_name, a.username)`,
      [accountId],
    );
    return {
      contacts: rows.map((r) => ({
        id: r.id,
        username: r.username,
        displayName: r.display_name,
        alias: r.alias,
        avatarMediaId: r.avatar_media_id,
        avatarUpdatedAt: (r.avatar_updated_at as Date | null)?.toISOString() ?? null,
        addedAt: (r.created_at as Date).toISOString(),
      })),
    };
  });

  app.post('/v1/contacts', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({ username: usernameSchema, alias: z.string().trim().min(1).max(64).optional() }),
      request.body,
    );
    const target = await findByUsername(body.username);
    if (!target) throw ApiError.notFound('user_not_found', 'No such user');
    if (target.id === accountId) throw ApiError.badRequest('self_contact', 'You cannot add yourself');

    await pool.query(
      `INSERT INTO contacts (account_id, contact_account_id, alias) VALUES ($1, $2, $3)
       ON CONFLICT (account_id, contact_account_id) DO UPDATE SET alias = EXCLUDED.alias`,
      [accountId, target.id, body.alias ?? null],
    );
    reply.code(201);
    return { ...publicProfile(target), alias: body.alias ?? null };
  });

  app.delete('/v1/contacts/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const { rowCount } = await pool.query(
      'DELETE FROM contacts WHERE account_id = $1 AND contact_account_id = $2',
      [accountId, params.id],
    );
    if (!rowCount) throw ApiError.notFound('contact_not_found', 'Not in your contacts');
    return { removed: true };
  });

  app.get('/v1/blocks', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query(
      `SELECT a.id, a.username, a.display_name, b.created_at
       FROM blocks b JOIN accounts a ON a.id = b.blocked_account_id
       WHERE b.account_id = $1 ORDER BY b.created_at DESC`,
      [accountId],
    );
    return {
      blocked: rows.map((r) => ({
        id: r.id,
        username: r.username,
        displayName: r.display_name,
        blockedAt: (r.created_at as Date).toISOString(),
      })),
    };
  });

  /** Blocking is invisible to the blocked user: their sends still return 202. */
  app.post('/v1/blocks', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ accountId: uuidSchema }), request.body);
    if (body.accountId === accountId) throw ApiError.badRequest('self_block', 'You cannot block yourself');
    const { rowCount } = await pool.query(
      `INSERT INTO blocks (account_id, blocked_account_id)
       SELECT $1, id FROM accounts WHERE id = $2 AND deleted_at IS NULL
       ON CONFLICT DO NOTHING`,
      [accountId, body.accountId],
    );
    if (!rowCount) {
      const { rowCount: exists } = await pool.query('SELECT 1 FROM accounts WHERE id = $1', [body.accountId]);
      if (!exists) throw ApiError.notFound('user_not_found', 'No such user');
    }
    reply.code(201);
    return { blocked: true };
  });

  app.delete('/v1/blocks/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await pool.query('DELETE FROM blocks WHERE account_id = $1 AND blocked_account_id = $2', [
      accountId,
      params.id,
    ]);
    return { blocked: false };
  });
};

export default contactRoutes;
