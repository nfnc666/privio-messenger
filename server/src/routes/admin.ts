import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { authenticator } from 'otplib';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { rateLimitFactor } from '../config.js';
import * as admin from '../services/admin.js';
import {
  ADMIN_ROLES,
  type AdminContext,
  type AdminRole,
  type Capability,
  adminById,
  can,
  createAdminUser,
  login,
  resolveAdminSession,
  revokeAdminSession,
  revokeAllAdminSessions,
} from '../services/admin_auth.js';
import { audit, auditFailedLogin, readAuditLog } from '../services/admin_audit.js';
import * as licenses from '../services/licenses.js';
import { canStoreSecrets, openSecret, sealSecret } from '../services/totp.js';
import { hashSecret, verifySecret } from '../util/crypto.js';
import { ApiError } from '../util/errors.js';
import { booleanQuery, parse, uuidSchema } from '../util/validate.js';

/**
 * The operator API behind the admin panel.
 *
 * WHAT IS NOT HERE, and will not be added:
 *
 *   - Reading a message, a channel post, a backup or an attachment. The server
 *     holds no key that opens one; a route that returned the ciphertext would
 *     be a route that leaked who is talking to whom in bulk, for bytes nobody
 *     can read anyway.
 *   - Acting as an account: no impersonation, no session minting, no password
 *     reset. An operator who could sign in as somebody could read everything
 *     that person's device can, which is the whole thing this design refuses.
 *   - Deleting an account or its data on an operator's say-so. Erasure is the
 *     account holder's own action, from their own device, at
 *     `DELETE /v1/accounts/me`.
 *   - Reading a private channel's title, members or posts.
 *
 * What is here is lookups over routing metadata, licensing, and the one
 * moderation action the server can take honestly — removing a *public* channel
 * from discovery. Every write lands in `admin_audit_log`.
 *
 * The panel is a server-rendered Next.js app that holds the operator token in
 * an httpOnly cookie and calls this API from its own server. That is why no
 * browser origin is added to CORS here: a token this strong should never be
 * readable by a script in a tab.
 */

declare module 'fastify' {
  interface FastifyRequest {
    admin?: AdminContext;
  }
}

function bearer(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

const adminRoutes: FastifyPluginAsync = async (app) => {
  app.decorateRequest('admin', undefined);

  const requireAdmin = async (request: FastifyRequest) => {
    const token = bearer(request);
    if (!token) throw ApiError.unauthorized('missing_token', 'Operator token required');
    const context = await resolveAdminSession(token);
    if (!context) throw ApiError.unauthorized('invalid_token', 'Session is invalid or expired');
    request.admin = context;
  };

  /** Narrows `request.admin` and checks one capability. */
  function actor(request: FastifyRequest, capability: Capability = 'read'): AdminContext {
    const context = request.admin;
    if (!context) throw ApiError.unauthorized();
    if (!can(context.role, capability)) {
      throw ApiError.forbidden(
        'insufficient_role',
        `Role '${context.role}' may not perform this action`,
      );
    }
    return context;
  }

  /** Logging an audit failure rather than failing the request it describes. */
  const auditFailed = (err: unknown) => app.log.error({ err }, 'admin audit write failed');

  const guard = { preHandler: requireAdmin };

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /**
   * Sign in.
   *
   * Rate limited hard and per address: this is the one door into everything
   * above, and it is the only place on the server where guessing an operator
   * password would pay off. Five attempts per ten minutes is generous for a
   * person typing and useless to anything else.
   */
  app.post(
    '/v1/admin/sessions',
    { config: { rateLimit: { max: 5 * rateLimitFactor, timeWindow: '10 minutes' } } },
    async (request, reply) => {
      const body = parse(
        z.object({
          username: z.string().trim().min(1).max(64),
          password: z.string().min(1).max(1024),
          totpCode: z.string().regex(/^\d{6}$/).optional(),
        }),
        request.body,
      );

      const result = await login(body.username, body.password, body.totpCode, {
        ip: request.ip,
        userAgent: request.headers['user-agent'],
      });

      if (!result.ok) {
        // A missing second factor is not a failed attempt — the password was
        // right. Answered as 401 with its own code so the panel knows to ask
        // for the code rather than to clear the form, and deliberately not
        // written to the audit log, which would otherwise fill with the normal
        // first half of every correct login.
        if (result.reason === 'totp_required') {
          return reply.code(401).send({ error: 'totp_required', message: 'Two-factor code required' });
        }
        await auditFailedLogin(body.username, request.ip, auditFailed);
        if (result.reason === 'invalid_totp') {
          return reply.code(401).send({ error: 'invalid_totp', message: 'Two-factor code is incorrect' });
        }
        return reply
          .code(401)
          .send({ error: 'invalid_credentials', message: 'Username or password is wrong' });
      }

      await audit(result.admin, { action: 'admin.login', ip: request.ip }, auditFailed);
      reply.code(201);
      return {
        token: result.token,
        expiresAt: result.expiresAt.toISOString(),
        operator: {
          id: result.admin.adminId,
          username: result.admin.username,
          role: result.admin.role,
        },
      };
    },
  );

  app.delete('/v1/admin/sessions/current', guard, async (request) => {
    const me = actor(request);
    await revokeAdminSession(me.sessionId);
    await audit(me, { action: 'admin.logout', ip: request.ip }, auditFailed);
    return { ended: true };
  });

  /**
   * Who the caller is and what the panel may show them.
   *
   * Capabilities are sent as booleans rather than left for the panel to derive
   * from the role name. The server decides what a role may do; a client that
   * re-implements that mapping will drift from it, and the drift shows up as a
   * button that is visible and then refused.
   */
  app.get('/v1/admin/me', guard, async (request) => {
    const me = actor(request);
    const row = await adminById(me.adminId);
    return {
      id: me.adminId,
      username: me.username,
      role: me.role,
      displayName: row?.display_name ?? null,
      twoFactorEnabled: row?.totp_enabled_at !== null && row?.totp_enabled_at !== undefined,
      can: {
        read: can(me.role, 'read'),
        licenses: can(me.role, 'licenses'),
        moderate: can(me.role, 'moderate'),
        operators: can(me.role, 'operators'),
      },
    };
  });

  /** Changing your own password. Requires the current one, and ends every other session. */
  app.post('/v1/admin/me/password', guard, async (request) => {
    const me = actor(request);
    const body = parse(
      z.object({
        currentPassword: z.string().min(1).max(1024),
        newPassword: z.string().min(12).max(1024),
      }),
      request.body,
    );
    const row = await adminById(me.adminId);
    if (!row || !(await verifySecret(row.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is wrong');
    }
    await pool.query('UPDATE admin_users SET password_hash = $2 WHERE id = $1', [
      me.adminId,
      await hashSecret(body.newPassword),
    ]);
    // Every session except this one: a password change is what somebody does
    // when they think a session is not theirs.
    await pool.query(
      `UPDATE admin_sessions SET revoked_at = now()
       WHERE admin_user_id = $1 AND id <> $2 AND revoked_at IS NULL`,
      [me.adminId, me.sessionId],
    );
    return { changed: true };
  });

  /** Step 1 of enrolling a second factor: a secret, shown once. */
  app.post('/v1/admin/me/totp/setup', guard, async (request) => {
    const me = actor(request);
    const row = await adminById(me.adminId);
    if (row?.totp_enabled_at) {
      throw ApiError.conflict('totp_already_enabled', 'Two-factor auth is already enabled');
    }
    if (!canStoreSecrets()) {
      throw ApiError.unavailable(
        'totp_unavailable',
        'TOTP_SECRET_KEY is not configured, so a secret cannot be stored safely',
      );
    }
    const secret = authenticator.generateSecret();
    await pool.query(
      'UPDATE admin_users SET totp_secret = $2, totp_enabled_at = NULL WHERE id = $1',
      [me.adminId, sealSecret(secret)],
    );
    return { secret, otpauthUrl: authenticator.keyuri(me.username, 'Privio Admin', secret) };
  });

  /** Step 2: prove the authenticator works before the factor becomes mandatory. */
  app.post('/v1/admin/me/totp', guard, async (request) => {
    const me = actor(request);
    const body = parse(z.object({ code: z.string().regex(/^\d{6}$/) }), request.body);
    const row = await adminById(me.adminId);
    if (!row?.totp_secret) throw ApiError.badRequest('totp_not_set_up', 'Start with /totp/setup');
    const secret = openSecret(row.totp_secret);
    if (secret === null || !authenticator.check(body.code, secret)) {
      throw ApiError.badRequest('invalid_totp', 'Code is incorrect');
    }
    await pool.query('UPDATE admin_users SET totp_enabled_at = now() WHERE id = $1', [me.adminId]);
    return { enabled: true };
  });

  // ---------------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/overview', guard, async (request) => {
    actor(request);
    const query = parse(
      z.object({ days: z.coerce.number().int().min(7).max(90).default(30) }),
      request.query,
    );
    const [totals, signups] = await Promise.all([
      admin.overview(),
      admin.signupSeries(query.days),
    ]);
    return { ...totals, signups };
  });

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/accounts', guard, async (request) => {
    actor(request);
    const query = parse(
      z.object({
        q: z.string().trim().max(32).optional(),
        limit: z.coerce.number().int().min(1).max(100).default(25),
        offset: z.coerce.number().int().min(0).default(0),
        includeDeleted: booleanQuery(false),
      }),
      request.query,
    );
    return admin.findAccounts(query);
  });

  app.get('/v1/admin/accounts/:id', guard, async (request) => {
    actor(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const detail = await admin.accountDetail(params.id);
    if (!detail) throw ApiError.notFound('account_not_found', 'No such account');
    return detail;
  });

  // ---------------------------------------------------------------------------
  // Licenses
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/licenses', guard, async (request) => {
    actor(request);
    const query = parse(
      z.object({
        status: z.enum(['active', 'revoked']).optional(),
        redeemed: z
          .enum(['true', 'false'])
          .optional()
          .transform((value) => (value === undefined ? undefined : value === 'true')),
        q: z.string().trim().max(255).optional(),
        limit: z.coerce.number().int().min(1).max(100).default(25),
        offset: z.coerce.number().int().min(0).default(0),
      }),
      request.query,
    );
    return admin.findLicenses(query);
  });

  /**
   * Issue a licence by hand — a replacement for a lost key, a comped one, a
   * support resolution.
   *
   * The key comes back exactly once, as it does from the payment path, and the
   * operator has to hand it on there and then. `paymentProvider` is forced to
   * `manual` rather than taken from the caller: an operator-issued licence must
   * be distinguishable from a paid one afterwards, and it would not be if the
   * panel could label it `stripe`. The audit entry records the reference, never
   * the key.
   */
  app.post('/v1/admin/licenses', guard, async (request, reply) => {
    const me = actor(request, 'licenses');
    const body = parse(
      z.object({
        reference: z.string().trim().min(1).max(255),
        maxDevices: z.number().int().min(1).max(50).optional(),
        note: z.enum(['replacement', 'support', 'comp', 'testing']).optional(),
      }),
      request.body,
    );

    const result = await licenses.issueLicense({
      paymentProvider: 'manual',
      paymentReference: body.reference,
      maxDevices: body.maxDevices,
    });

    if (result.status === 'already_issued') {
      return reply.code(409).send({
        error: 'license_already_issued',
        message: 'That reference already has a license; its key cannot be shown again',
        licenseId: result.licenseId,
      });
    }

    await audit(
      me,
      {
        action: 'license.issue',
        targetType: 'license',
        targetId: result.licenseId,
        detail: { reference: body.reference, maxDevices: body.maxDevices, note: body.note },
        ip: request.ip,
      },
      auditFailed,
    );

    reply.code(201);
    return { licenseId: result.licenseId, licenseKey: result.licenseKey };
  });

  app.post('/v1/admin/licenses/:id/revoke', guard, async (request) => {
    const me = actor(request, 'licenses');
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({ reason: z.enum(['chargeback', 'refund', 'abuse', 'mistake']) }),
      request.body ?? {},
    );
    const revoked = await licenses.revokeById(params.id);
    if (!revoked) throw ApiError.notFound('license_not_found', 'No active license with that id');
    await audit(
      me,
      {
        action: 'license.revoke',
        targetType: 'license',
        targetId: params.id,
        detail: { reason: body.reason },
        ip: request.ip,
      },
      auditFailed,
    );
    return { revoked: true };
  });

  // ---------------------------------------------------------------------------
  // Moderation
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/reports', guard, async (request) => {
    actor(request);
    const query = parse(
      z.object({
        open: booleanQuery(true),
        limit: z.coerce.number().int().min(1).max(100).default(25),
        offset: z.coerce.number().int().min(0).default(0),
      }),
      request.query,
    );
    return admin.reportedChannels(query);
  });

  /**
   * Suspend a public channel: it stops being listed, stops resolving by handle
   * and stops being reachable by invite code.
   *
   * Members keep the channel and its key, because there is no mechanism by
   * which they would not — the key is on their devices and was never here. The
   * response says so explicitly so a panel cannot present this as more than it
   * is.
   */
  app.post('/v1/admin/channels/:id/suspend', guard, async (request) => {
    const me = actor(request, 'moderate');
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({
        reason: z.enum(['spam', 'abuse', 'illegal', 'impersonation', 'other']),
        reviewReports: z.boolean().default(true),
      }),
      request.body ?? {},
    );

    const channel = await admin.channelForModeration(params.id);
    if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');
    if (channel.visibility !== 'public') {
      throw ApiError.badRequest(
        'channel_not_public',
        'Only a public channel can be suspended: a private one is not discoverable, so suspending it would remove nothing',
      );
    }

    const suspended = await admin.suspendChannel(params.id, body.reason);
    if (!suspended) throw ApiError.conflict('already_suspended', 'That channel is already suspended');
    const reviewed = body.reviewReports ? await admin.reviewReports(params.id, me.adminId) : 0;

    await audit(
      me,
      {
        action: 'channel.suspend',
        targetType: 'channel',
        targetId: params.id,
        detail: { reason: body.reason, reportsClosed: reviewed },
        ip: request.ip,
      },
      auditFailed,
    );

    return {
      suspended: true,
      reportsClosed: reviewed,
      membersAffected: false,
      note: 'Removed from discovery, handle lookup and invite links. Existing members keep the channel and its key; no post was touched.',
    };
  });

  app.post('/v1/admin/channels/:id/reinstate', guard, async (request) => {
    const me = actor(request, 'moderate');
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const reinstated = await admin.reinstateChannel(params.id);
    if (!reinstated) throw ApiError.notFound('not_suspended', 'That channel is not suspended');
    await audit(
      me,
      { action: 'channel.reinstate', targetType: 'channel', targetId: params.id, ip: request.ip },
      auditFailed,
    );
    return { reinstated: true };
  });

  /** Judged and found fine: close the reports, leave the channel alone. */
  app.post('/v1/admin/channels/:id/review', guard, async (request) => {
    const me = actor(request, 'moderate');
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const channel = await admin.channelForModeration(params.id);
    if (!channel) throw ApiError.notFound('channel_not_found', 'No such channel');
    const closed = await admin.reviewReports(params.id, me.adminId);
    await audit(
      me,
      {
        action: 'report.review',
        targetType: 'channel',
        targetId: params.id,
        detail: { reportsClosed: closed },
        ip: request.ip,
      },
      auditFailed,
    );
    return { reportsClosed: closed };
  });

  // ---------------------------------------------------------------------------
  // Operators
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/operators', guard, async (request) => {
    actor(request, 'operators');
    return { operators: await admin.listOperators() };
  });

  app.post('/v1/admin/operators', guard, async (request, reply) => {
    const me = actor(request, 'operators');
    const body = parse(
      z.object({
        username: z
          .string()
          .trim()
          .toLowerCase()
          .regex(/^[a-z0-9_.-]{3,32}$/, 'must be 3-32 characters of a-z, 0-9, dot, dash or underscore'),
        password: z.string().min(12).max(1024),
        role: z.enum(ADMIN_ROLES),
        displayName: z.string().trim().max(64).optional(),
      }),
      request.body,
    );

    let created;
    try {
      created = await createAdminUser({ ...body, createdBy: me.adminId });
    } catch (err) {
      if ((err as { code?: string }).code === '23505') {
        throw ApiError.conflict('username_taken', 'An operator with that username already exists');
      }
      throw err;
    }

    await audit(
      me,
      {
        action: 'operator.create',
        targetType: 'operator',
        targetId: created.id,
        detail: { username: created.username, role: created.role },
        ip: request.ip,
      },
      auditFailed,
    );
    reply.code(201);
    return { id: created.id, username: created.username, role: created.role };
  });

  /**
   * Disable, re-enable, or change a role.
   *
   * Every one of those ends the target's live sessions. A role carried inside an
   * already-issued session would otherwise outlive the change by up to the
   * session TTL — which is exactly the window somebody being demoted would use.
   */
  app.patch('/v1/admin/operators/:id', guard, async (request) => {
    const me = actor(request, 'operators');
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({ role: z.enum(ADMIN_ROLES).optional(), disabled: z.boolean().optional() }),
      request.body,
    );
    if (body.role === undefined && body.disabled === undefined) {
      throw ApiError.badRequest('nothing_to_change', 'Pass role, disabled, or both');
    }

    const target = await adminById(params.id);
    if (!target) throw ApiError.notFound('operator_not_found', 'No such operator');

    // An owner locking themselves out, or demoting themselves to the last
    // non-owner, leaves a server nobody can administer and no way back in short
    // of the bootstrap CLI and a shell. Refused rather than warned about.
    if (target.id === me.adminId && (body.disabled === true || (body.role && body.role !== 'owner'))) {
      throw ApiError.badRequest(
        'cannot_demote_self',
        'Use another owner account to change or disable this one',
      );
    }
    if (target.role === 'owner' && body.role && body.role !== 'owner') {
      await assertAnotherOwnerRemains(target.id);
    }
    if (target.role === 'owner' && body.disabled === true) {
      await assertAnotherOwnerRemains(target.id);
    }

    const { rows } = await pool.query(
      `UPDATE admin_users
       SET role        = COALESCE($2, role),
           disabled_at = CASE WHEN $3::boolean IS NULL THEN disabled_at
                              WHEN $3 THEN COALESCE(disabled_at, now())
                              ELSE NULL END
       WHERE id = $1
       RETURNING role, disabled_at`,
      [params.id, body.role ?? null, body.disabled ?? null],
    );
    const ended = await revokeAllAdminSessions(params.id);

    if (body.role !== undefined && body.role !== target.role) {
      await audit(
        me,
        {
          action: 'operator.role_change',
          targetType: 'operator',
          targetId: params.id,
          detail: { from: target.role, to: body.role, sessionsEnded: ended },
          ip: request.ip,
        },
        auditFailed,
      );
    }
    if (body.disabled !== undefined) {
      await audit(
        me,
        {
          action: body.disabled ? 'operator.disable' : 'operator.enable',
          targetType: 'operator',
          targetId: params.id,
          detail: { username: target.username, sessionsEnded: ended },
          ip: request.ip,
        },
        auditFailed,
      );
    }

    return {
      id: params.id,
      role: rows[0]!.role as AdminRole,
      disabledAt: rows[0]!.disabled_at?.toISOString() ?? null,
      sessionsEnded: ended,
    };
  });

  async function assertAnotherOwnerRemains(excludingId: string): Promise<void> {
    const { rows } = await pool.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM admin_users
       WHERE role = 'owner' AND disabled_at IS NULL AND id <> $1`,
      [excludingId],
    );
    if (rows[0]!.n === 0) {
      throw ApiError.badRequest('last_owner', 'That is the last owner; promote another one first');
    }
  }

  // ---------------------------------------------------------------------------
  // Audit log
  // ---------------------------------------------------------------------------

  app.get('/v1/admin/audit', guard, async (request) => {
    actor(request);
    const query = parse(
      z.object({
        limit: z.coerce.number().int().min(1).max(200).default(50),
        before: z.coerce.number().int().positive().optional(),
        action: z.string().trim().max(64).optional(),
        targetId: z.string().trim().max(255).optional(),
      }),
      request.query,
    );
    const entries = await readAuditLog(query);
    return {
      entries,
      // The cursor is the caller's own business to keep; handing it back saves
      // the panel from re-deriving it from the last row.
      nextBefore: entries.length === query.limit ? entries[entries.length - 1]!.id : null,
    };
  });
};

export default adminRoutes;
