import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { authenticator } from 'otplib';
import { pool, withTransaction } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import * as accounts from '../services/accounts.js';
import { deviceRegistrationSchema, registerDevice } from '../services/devices.js';
import { createSession, revokeAllSessions, revokeSession } from '../services/sessions.js';
import { hashSecret, verifySecret } from '../util/crypto.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, passwordSchema, usernameSchema, uuidSchema } from '../util/validate.js';
import { config } from '../config.js';

// Verifying a throwaway hash on unknown usernames keeps login timing flat, so a
// failed attempt does not reveal whether the account exists.
const DUMMY_HASH_PROMISE = hashSecret('privio-timing-equaliser');

const privacySchema = z.object({
  lastSeen: z.enum(['everyone', 'contacts', 'nobody']).optional(),
  readReceipts: z.boolean().optional(),
  typingIndicators: z.boolean().optional(),
  whoCanAddMeToGroups: z.enum(['everyone', 'contacts']).optional(),
});

const registerSchema = z.object({
  username: usernameSchema,
  password: passwordSchema,
  displayName: z.string().trim().min(1).max(64).optional(),
  device: deviceRegistrationSchema,
});

const loginSchema = z.object({
  username: usernameSchema,
  password: z.string().min(1).max(1024),
  totpCode: z.string().regex(/^\d{6}$/).optional(),
  device: deviceRegistrationSchema,
});

const accountRoutes: FastifyPluginAsync = async (app) => {
  /** Create an account and its first device. No phone number, no email. */
  app.post('/v1/accounts', async (request, reply) => {
    const body = parse(registerSchema, request.body);

    const existing = await accounts.findByUsername(body.username);
    if (existing) throw ApiError.conflict('username_taken', 'That username is already in use');

    const passwordHash = await hashSecret(body.password);
    const result = await withTransaction(async (client) => {
      const { rows } = await client
        .query<{ id: string }>(
          `INSERT INTO accounts (username, display_name, password_hash)
           VALUES ($1, $2, $3) RETURNING id`,
          [body.username, body.displayName ?? null, passwordHash],
        )
        .catch((err: { code?: string }) => {
          if (err.code === '23505') throw ApiError.conflict('username_taken', 'That username is already in use');
          throw err;
        });
      const accountId = rows[0]!.id;
      const device = await registerDevice(client, accountId, body.device);
      return { accountId, ...device };
    });

    const session = await createSession(result.accountId, result.deviceId, request.headers['user-agent']);
    reply.code(201);
    return {
      accountId: result.accountId,
      deviceId: result.deviceId,
      deviceIndex: result.deviceIndex,
      username: body.username,
      token: session.token,
      expiresAt: session.expiresAt.toISOString(),
    };
  });

  /** Log in and register the calling device in one step. */
  app.post('/v1/sessions', async (request) => {
    const body = parse(loginSchema, request.body);
    const account = await accounts.findByUsername(body.username);

    if (!account) {
      await verifySecret(await DUMMY_HASH_PROMISE, body.password);
      throw ApiError.unauthorized('invalid_credentials', 'Username or password is incorrect');
    }

    const passwordOk = await verifySecret(account.password_hash, body.password);
    if (!passwordOk) {
      // A duress wipe code looks exactly like a wrong password from outside.
      if (await accounts.matchesWipeCode(account, body.password)) {
        await accounts.wipeAccount(account.id);
      }
      throw ApiError.unauthorized('invalid_credentials', 'Username or password is incorrect');
    }

    if (account.totp_enabled_at && account.totp_secret) {
      if (!body.totpCode) throw ApiError.unauthorized('totp_required', 'Two-factor code required');
      if (!authenticator.check(body.totpCode, account.totp_secret)) {
        throw ApiError.unauthorized('invalid_totp', 'Two-factor code is incorrect');
      }
    }

    const device = await withTransaction((client) => registerDevice(client, account.id, body.device));
    const session = await createSession(account.id, device.deviceId, request.headers['user-agent']);
    return {
      accountId: account.id,
      deviceId: device.deviceId,
      deviceIndex: device.deviceIndex,
      username: account.username,
      token: session.token,
      expiresAt: session.expiresAt.toISOString(),
    };
  });

  app.delete('/v1/sessions/current', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { sessionId, accountId } = auth(request);
    await revokeSession(sessionId, accountId);
    return { revoked: true };
  });

  /** Remote logout of every other device. */
  app.post('/v1/sessions/revoke-all', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { sessionId, accountId } = auth(request);
    const revoked = await revokeAllSessions(accountId, sessionId);
    return { revoked };
  });

  app.get('/v1/accounts/me', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId, deviceId } = auth(request);
    const account = await accounts.findById(accountId);
    if (!account) throw ApiError.notFound('account_not_found', 'Account no longer exists');
    return {
      ...accounts.publicProfile(account),
      deviceId,
      privacy: account.privacy,
      twoFactorEnabled: account.totp_enabled_at !== null,
      wipeCodeSet: account.wipe_code_hash !== null,
      createdAt: account.created_at.toISOString(),
    };
  });

  app.patch('/v1/accounts/me', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({
        displayName: z.string().trim().min(1).max(64).nullable().optional(),
        privacy: privacySchema.optional(),
      }),
      request.body,
    );
    const { rows } = await pool.query<accounts.AccountRow>(
      `UPDATE accounts
       SET display_name = COALESCE($2, display_name),
           privacy = privacy || COALESCE($3::jsonb, '{}'::jsonb)
       WHERE id = $1 RETURNING *`,
      [accountId, body.displayName ?? null, body.privacy ? JSON.stringify(body.privacy) : null],
    );
    const account = rows[0]!;
    return { ...accounts.publicProfile(account), privacy: account.privacy };
  });

  /** Change the account password. Every other session is revoked. */
  app.post('/v1/accounts/me/password', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId, sessionId } = auth(request);
    const body = parse(
      z.object({ currentPassword: z.string().min(1), newPassword: passwordSchema }),
      request.body,
    );
    const account = await accounts.findById(accountId);
    if (!account || !(await verifySecret(account.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is incorrect');
    }
    await accounts.setPassword(accountId, body.newPassword);
    const revoked = await revokeAllSessions(accountId, sessionId);
    return { updated: true, otherSessionsRevoked: revoked };
  });

  /** Set or clear the duress wipe code. */
  app.put('/v1/accounts/me/wipe-code', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({
        currentPassword: z.string().min(1),
        wipeCode: z.string().min(4).max(128).nullable(),
      }),
      request.body,
    );
    const account = await accounts.findById(accountId);
    if (!account || !(await verifySecret(account.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is incorrect');
    }
    if (body.wipeCode && (await verifySecret(account.password_hash, body.wipeCode))) {
      throw ApiError.badRequest('wipe_code_matches_password', 'Wipe code must differ from the password');
    }
    await accounts.setWipeCode(accountId, body.wipeCode);
    return { wipeCodeSet: body.wipeCode !== null };
  });

  /** Step 1 of enabling 2FA: hand the client a secret to show as a QR code. */
  app.post('/v1/accounts/me/totp/setup', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId, username } = auth(request);
    const account = await accounts.findById(accountId);
    if (account?.totp_enabled_at) {
      throw ApiError.conflict('totp_already_enabled', 'Two-factor auth is already enabled');
    }
    const secret = authenticator.generateSecret();
    await pool.query('UPDATE accounts SET totp_secret = $2, totp_enabled_at = NULL WHERE id = $1', [
      accountId,
      secret,
    ]);
    return { secret, otpauthUrl: authenticator.keyuri(username, 'Privio', secret) };
  });

  /** Step 2: prove the authenticator app works before the factor becomes mandatory. */
  app.post('/v1/accounts/me/totp/enable', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ code: z.string().regex(/^\d{6}$/) }), request.body);
    const account = await accounts.findById(accountId);
    if (!account?.totp_secret) throw ApiError.badRequest('totp_not_set_up', 'Start with /totp/setup');
    if (!authenticator.check(body.code, account.totp_secret)) {
      throw ApiError.badRequest('invalid_totp', 'Code is incorrect');
    }
    await pool.query('UPDATE accounts SET totp_enabled_at = now() WHERE id = $1', [accountId]);
    return { twoFactorEnabled: true };
  });

  app.delete('/v1/accounts/me/totp', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ currentPassword: z.string().min(1) }), request.body);
    const account = await accounts.findById(accountId);
    if (!account || !(await verifySecret(account.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is incorrect');
    }
    await pool.query(
      'UPDATE accounts SET totp_secret = NULL, totp_enabled_at = NULL WHERE id = $1',
      [accountId],
    );
    return { twoFactorEnabled: false };
  });

  /**
   * Account recovery blob: the client seals its identity keys with a recovery
   * key the user writes down. The server stores the ciphertext and nothing else.
   */
  app.put('/v1/accounts/me/recovery', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({ blob: base64Bytes(1, config.MAX_ENVELOPE_BYTES * 4) }),
      request.body,
    );
    await pool.query('UPDATE accounts SET recovery_blob = $2 WHERE id = $1', [accountId, body.blob]);
    return { stored: true, byteSize: body.blob.length };
  });

  app.get('/v1/accounts/me/recovery', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query<{ recovery_blob: Buffer | null }>(
      'SELECT recovery_blob FROM accounts WHERE id = $1',
      [accountId],
    );
    const blob = rows[0]?.recovery_blob ?? null;
    if (!blob) throw ApiError.notFound('no_recovery_blob', 'No recovery blob stored');
    return { blob: blob.toString('base64') };
  });

  /**
   * Point the account at an avatar.
   *
   * The bytes were uploaded to /v1/media already, sealed with the owner's
   * profile key — so this stores a reference to ciphertext, and the server can
   * no more see the picture than it can read a message. The upload must belong
   * to the caller: without that check anyone could adopt anyone else's object
   * id and confirm, by watching for an error, whether it exists.
   */
  app.put('/v1/accounts/me/avatar', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ mediaId: uuidSchema }), request.body);

    const { rows } = await pool.query<{ id: string }>(
      'SELECT id FROM media_objects WHERE id = $1 AND owner_account_id = $2',
      [body.mediaId, accountId],
    );
    if (!rows[0]) throw ApiError.notFound('media_not_found', 'No such upload of yours');

    const previous = await withTransaction(async (client) => {
      const { rows: old } = await client.query<{ avatar_media_id: string | null }>(
        'SELECT avatar_media_id FROM accounts WHERE id = $1 FOR UPDATE',
        [accountId],
      );
      await client.query(
        'UPDATE accounts SET avatar_media_id = $2, avatar_updated_at = now() WHERE id = $1',
        [accountId, body.mediaId],
      );
      // An avatar outlives the attachment retention window; the sweep also skips
      // referenced objects, and this keeps the expiry itself honest.
      await client.query(
        `UPDATE media_objects SET expires_at = now() + interval '100 years' WHERE id = $1`,
        [body.mediaId],
      );
      return old[0]?.avatar_media_id ?? null;
    });

    // The old picture is nobody's now: let it fall into the next sweep.
    if (previous && previous !== body.mediaId) {
      await pool.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [previous]);
    }
    return { avatarMediaId: body.mediaId };
  });

  app.delete('/v1/accounts/me/avatar', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query<{ avatar_media_id: string | null }>(
      'UPDATE accounts SET avatar_media_id = NULL, avatar_updated_at = now() WHERE id = $1 RETURNING avatar_media_id',
      [accountId],
    );
    const removed = rows[0]?.avatar_media_id ?? null;
    if (removed) {
      await pool.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [removed]);
    }
    return { avatarMediaId: null };
  });

  app.delete('/v1/accounts/me', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ currentPassword: z.string().min(1) }), request.body);
    const account = await accounts.findById(accountId);
    if (!account || !(await verifySecret(account.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is incorrect');
    }
    await accounts.deleteAccount(accountId);
    return { deleted: true };
  });
};

export default accountRoutes;
