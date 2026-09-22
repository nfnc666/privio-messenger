import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { rateLimitFactor } from '../config.js';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import { findByUsername, publicProfile, type AccountRow } from '../services/accounts.js';
import { lastSeenFor } from '../services/presence.js';
import { statusFor, ownStatus, NO_STATUS } from '../services/status.js';
import { ApiError } from '../util/errors.js';
import { parse, usernameSchema, uuidSchema } from '../util/validate.js';

/** Whether the target has the viewer in *their* address book. */
async function viewerIsContactOf(viewerId: string, target: AccountRow): Promise<boolean> {
  const { rowCount } = await pool.query(
    'SELECT 1 FROM contacts WHERE account_id = $1 AND contact_account_id = $2',
    [target.id, viewerId],
  );
  return rowCount === 1;
}

/**
 * The two things a profile lookup has to decide, decided together.
 *
 * Together only because they need the same `contacts` lookup and doing it twice
 * would be two round trips for one answer — not because they are one setting.
 * `lastSeenFor` and `statusFor` read different keys and have different
 * defaults, and a viewer who may see one may well not see the other.
 */
async function visibleProfile(viewerId: string, target: AccountRow) {
  if (viewerId === target.id) {
    return { lastSeenAt: null, status: ownStatus(target) };
  }
  const blocked = await pool.query(
    `SELECT 1 FROM blocks WHERE
      (account_id = $1 AND blocked_account_id = $2) OR
      (account_id = $2 AND blocked_account_id = $1) LIMIT 1`,
    [viewerId, target.id],
  );
  if (blocked.rowCount) return { lastSeenAt: null, status: NO_STATUS };
  const needsContactCheck =
    (target.privacy?.lastSeen ?? 'contacts') === 'contacts' ||
    (target.privacy?.profileStatus ?? 'everyone') === 'contacts';
  const isContact = needsContactCheck ? await viewerIsContactOf(viewerId, target) : false;
  return {
    lastSeenAt: lastSeenFor(target, isContact),
    status: statusFor(target, isContact),
  };
}

/**
 * The viewer's own relationship to the account they are looking at.
 *
 * Deliberately separate from [visibleProfile], which decides what the *target*
 * lets this viewer see. Nothing here is the target's to withhold: whether you
 * have somebody in your address book, and whether you have blocked them, are
 * facts about you. That is also why blocking is safe to report — it is the
 * blocker asking, never the blocked.
 *
 * The profile screen needs both to draw its buttons, and one query is what
 * stops it opening with "Add contact" and correcting itself a moment later.
 */
async function viewerRelationship(viewerId: string, targetId: string) {
  // Looking at yourself: neither fact means anything, and neither query needs
  // running. The screen knows whose profile it is from the signed-in account id
  // it already has, so there is nothing here for it to be told.
  if (viewerId === targetId) return { isContact: false, isBlocked: false };
  const { rows } = await pool.query<{ is_contact: boolean; is_blocked: boolean }>(
    `SELECT EXISTS (
              SELECT 1 FROM contacts WHERE account_id = $1 AND contact_account_id = $2
            ) AS is_contact,
            EXISTS (
              SELECT 1 FROM blocks WHERE account_id = $1 AND blocked_account_id = $2
            ) AS is_blocked`,
    [viewerId, targetId],
  );
  return {
    isContact: rows[0]?.is_contact ?? false,
    isBlocked: rows[0]?.is_blocked ?? false,
  };
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
      ...(await visibleProfile(accountId, target)),
      ...(await viewerRelationship(accountId, target.id)),
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
      ...(await visibleProfile(accountId, target)),
      ...(await viewerRelationship(accountId, target.id)),
    };
  });

  /** A shareable invite the client renders as a link and a QR code. */
  app.get('/v1/contacts/invite', requireAuth, async (request) => {
    const { username } = auth(request);
    return { username, inviteUrl: `https://privio.app/u/${username}`, deepLink: `privio://u/${username}` };
  });

  app.get('/v1/contacts', requireAuth, async (request) => {
    const { accountId } = auth(request);
    // `mutual` answers the last-seen rule for every row at once: does the
    // contact have the viewer in *their* address book. Done here rather than
    // per row, because a query per contact is a query per contact.
    const { rows } = await pool.query(
      `SELECT a.id, a.username, a.display_name, a.avatar_media_id, a.avatar_updated_at,
              a.privacy, a.last_seen_at, c.created_at,
              a.status_text, a.status_emoji, a.status_expires_at, a.status_updated_at,
              EXISTS (
                SELECT 1 FROM contacts back
                WHERE back.account_id = a.id AND back.contact_account_id = $1
              ) AS mutual
       FROM contacts c JOIN accounts a ON a.id = c.contact_account_id
       WHERE c.account_id = $1 AND a.deleted_at IS NULL
       ORDER BY COALESCE(a.display_name, a.username)`,
      [accountId],
    );
    return {
      contacts: rows.map((r) => ({
        id: r.id,
        username: r.username,
        displayName: r.display_name,
        avatarMediaId: r.avatar_media_id,
        avatarUpdatedAt: (r.avatar_updated_at as Date | null)?.toISOString() ?? null,
        addedAt: (r.created_at as Date).toISOString(),
        lastSeenAt: lastSeenFor(
          { privacy: r.privacy, last_seen_at: r.last_seen_at as Date },
          r.mutual as boolean,
        ),
        status: statusFor(
          {
            privacy: r.privacy,
            status_text: r.status_text as string | null,
            status_emoji: r.status_emoji as string | null,
            status_expires_at: r.status_expires_at as Date | null,
            status_updated_at: r.status_updated_at as Date | null,
          },
          r.mutual as boolean,
        ),
      })),
    };
  });

  app.post('/v1/contacts', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({ username: usernameSchema.optional(), accountId: uuidSchema.optional() })
        .refine((value) => Boolean(value.username) !== Boolean(value.accountId)),
      request.body,
    );
    const target = body.accountId
      ? (await pool.query<AccountRow>('SELECT * FROM accounts WHERE id = $1 AND deleted_at IS NULL', [body.accountId])).rows[0]
      : await findByUsername(body.username!);
    if (!target) throw ApiError.notFound('user_not_found', 'No such user');
    if (target.id === accountId) throw ApiError.badRequest('self_contact', 'You cannot add yourself');

    await pool.query(
      // A nickname for a contact is the user's own business and stays on their
      // device; the server holds the fact of the contact and nothing about how
      // they think of them. See migration 013.
      `INSERT INTO contacts (account_id, contact_account_id) VALUES ($1, $2)
       ON CONFLICT (account_id, contact_account_id) DO NOTHING`,
      [accountId, target.id],
    );
    reply.code(201);
    return publicProfile(target);
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

  /**
   * Report an account.
   *
   * What this can carry is limited by what the server knows, which is nothing
   * about what anybody said: there is no message to attach, because the server
   * never held one in the clear. A report is therefore a reason and a reporter,
   * and `docs/moderation.md` states that rather than leaving a reviewer to
   * assume evidence that does not exist.
   *
   * Reporting is deliberately **not** blocking. The two are offered together on
   * the profile screen and a user may well want both, but a report that
   * silently blocked would make an accusation into a change to your own
   * account, and a block that silently reported would send your address book to
   * a moderator. Each does one thing.
   *
   * Rate-limited well below anything a person does by hand: the primary key
   * already stops the same complaint twice, and this stops one account walking
   * a list of ids.
   */
  app.post(
    '/v1/users/:id/report',
    {
      ...requireAuth,
      config: { rateLimit: { max: 20 * rateLimitFactor, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const body = parse(
        z.object({ reason: z.enum(['spam', 'abuse', 'illegal', 'impersonation', 'other']) }),
        request.body,
      );
      if (params.id === accountId) {
        throw ApiError.badRequest('self_report', 'You cannot report yourself');
      }

      const { rowCount } = await pool.query(
        `INSERT INTO account_reports (account_id, reporter_id, reason)
         SELECT $1, $2, $3 FROM accounts WHERE id = $1 AND deleted_at IS NULL
         ON CONFLICT (account_id, reporter_id) DO NOTHING`,
        [params.id, accountId, body.reason],
      );
      if (!rowCount) {
        // Either there is no such account, or this reporter already has a
        // standing report. Told apart, because the second is not a failure and
        // the screen should say the report is already on file rather than
        // pretending to have filed a new one.
        const { rowCount: exists } = await pool.query(
          'SELECT 1 FROM accounts WHERE id = $1 AND deleted_at IS NULL',
          [params.id],
        );
        if (!exists) throw ApiError.notFound('user_not_found', 'No such user');
        return { reported: true, alreadyReported: true };
      }
      reply.code(201);
      return { reported: true, alreadyReported: false };
    },
  );

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
