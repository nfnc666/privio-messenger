import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { authenticator } from 'otplib';
import { canStoreSecrets, openSecret, sealSecret } from '../services/totp.js';
import { pool, withTransaction } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import * as accounts from '../services/accounts.js';
import type { BlobStorage } from '../services/storage.js';
import { deviceRegistrationSchema, registerDevice } from '../services/devices.js';
import {
  createSession,
  liveSessionsFor,
  revokeAllSessions,
  revokeSession,
} from '../services/sessions.js';
import { announceRevocation } from '../services/revocation.js';
import type { DeliveryBus } from '../services/bus.js';
import { hashSecret, verifySecret } from '../util/crypto.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, passwordSchema, usernameSchema, uuidSchema } from '../util/validate.js';
import { config, rateLimitFactor } from '../config.js';

/**
 * The budget for routes that check a credential: a password, a wipe code, a
 * six-digit code. Ten attempts per address per five minutes, which is generous
 * for a person and useless for a guesser.
 *
 * It is declared per route rather than around the plugin, because reading your
 * own account is not an attempt at anything and must not spend the same
 * allowance a login does.
 */
const guessable = {
  config: {
    rateLimit: {
      max: 10 * rateLimitFactor,
      timeWindow: '5 minutes',
      keyGenerator: (request: { ip: string }) => request.ip,
    },
  },
};

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

const accountRoutes = (storage: BlobStorage, bus: DeliveryBus): FastifyPluginAsync => async (app) => {
  /** Create an account and its first device. No phone number, no email. */
  app.post('/v1/accounts', guessable, async (request, reply) => {
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
  app.post('/v1/sessions', guessable, async (request) => {
    const body = parse(loginSchema, request.body);
    const account = await accounts.findByUsername(body.username);

    if (!account) {
      await verifySecret(await DUMMY_HASH_PROMISE, body.password);
      throw ApiError.unauthorized('invalid_credentials', 'Username or password is incorrect');
    }

    const passwordOk = await verifySecret(account.password_hash, body.password);
    if (!passwordOk) {
      // A duress code looks exactly like a wrong password from outside.
      if (await accounts.matchesDuressCode(account, body.password)) {
        // Read the sessions before the wipe removes them, then close every
        // socket. A duress wipe that left a signed-in device receiving is not
        // a wipe.
        const open = await liveSessionsFor(account.id);
        await accounts.wipeAccount(account.id, storage);
        await announceRevocation(bus, open, request.log);
      }
      throw ApiError.unauthorized('invalid_credentials', 'Username or password is incorrect');
    }

    if (account.totp_enabled_at && account.totp_secret) {
      if (!body.totpCode) throw ApiError.unauthorized('totp_required', 'Two-factor code required');
      const secret = openSecret(account.totp_secret);
      // A secret that will not open — a rotated or lost key — must refuse the
      // login rather than wave it through. Getting past a second factor whose
      // secret the server can no longer read is the same as not having one.
      if (secret === null || !authenticator.check(body.totpCode, secret)) {
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
    // Told to close, not left to notice. Before this the socket kept running
    // on a session that no longer existed: it went on receiving envelopes and
    // its acknowledgements went on deleting them from the queue.
    await announceRevocation(bus, await revokeSession(sessionId, accountId), request.log);
    return { revoked: true };
  });

  /** Remote logout of every other device. */
  app.post('/v1/sessions/revoke-all', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { sessionId, accountId } = auth(request);
    const ended = await revokeAllSessions(accountId, sessionId);
    await announceRevocation(bus, ended, request.log);
    return { revoked: ended.length };
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
      duressCodeSet: account.duress_code_hash !== null,
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
  app.post(
    '/v1/accounts/me/password',
    { ...guessable, preHandler: (r) => app.requireAuth(r) },
    async (request) => {
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
    // Changing a password is what somebody does when they think another device
    // is not theirs any more. Leaving that device's socket open would make the
    // change cosmetic until it happened to reconnect.
    const ended = await revokeAllSessions(accountId, sessionId);
    await announceRevocation(bus, ended, request.log);
    return { updated: true, otherSessionsRevoked: ended.length };
  });

  /** Set or clear the duress code. */
  app.put(
    '/v1/accounts/me/duress-code',
    { ...guessable, preHandler: (r) => app.requireAuth(r) },
    async (request) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({
        currentPassword: z.string().min(1),
        duressCode: z.string().min(4).max(128).nullable(),
      }),
      request.body,
    );
    const account = await accounts.findById(accountId);
    if (!account || !(await verifySecret(account.password_hash, body.currentPassword))) {
      throw ApiError.unauthorized('invalid_credentials', 'Current password is incorrect');
    }
    if (body.duressCode && (await verifySecret(account.password_hash, body.duressCode))) {
      throw ApiError.badRequest(
        'duress_code_matches_password',
        'Duress code must differ from the password',
      );
    }
    await accounts.setDuressCode(accountId, body.duressCode);
    return { duressCodeSet: body.duressCode !== null };
  });

  /**
   * The duress wipe, from a device that is already signed in.
   *
   * The login path wipes when the code is typed instead of the password. This
   * is the other place a person under duress is standing: at the lock screen of
   * a phone that is already signed in, where there is no password to substitute
   * for. The device recognises the code offline and then tells the server, so
   * the queued envelopes and the backup go too.
   *
   * It takes the duress code rather than the password on purpose — under duress
   * the password is the one thing the person is not going to be typing.
   */
  app.post(
    '/v1/accounts/me/wipe',
    { ...guessable, preHandler: (r) => app.requireAuth(r) },
    async (request) => {
      const { accountId } = auth(request);
      const body = parse(z.object({ duressCode: z.string().min(1) }), request.body);
      const account = await accounts.findById(accountId);
      if (!account || !(await accounts.matchesDuressCode(account, body.duressCode))) {
        // Same answer a wrong password gets anywhere else. A caller must not be
        // able to use this to find out whether a duress code exists.
        throw ApiError.unauthorized('invalid_credentials', 'That code is not right');
      }
      const open = await liveSessionsFor(accountId);
      await accounts.wipeAccount(accountId, storage);
      await announceRevocation(bus, open, request.log);
      return { wiped: true };
    },
  );

  /** Step 1 of enabling 2FA: hand the client a secret to show as a QR code. */
  app.post('/v1/accounts/me/totp/setup', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId, username } = auth(request);
    const account = await accounts.findById(accountId);
    if (account?.totp_enabled_at) {
      throw ApiError.conflict('totp_already_enabled', 'Two-factor auth is already enabled');
    }
    if (!canStoreSecrets()) {
      // Refused rather than stored in the clear. A TOTP secret does not expire,
      // so one written unsealed is a permanent hole in this account's second
      // factor, and nobody would ever be told.
      //
      // The person reading the error can do nothing about the configuration,
      // so they get a sentence they can act on and the operator gets the
      // variable name in the log.
      request.log.error(
        'Refusing TOTP setup: TOTP_SECRET_KEY is not configured, so the secret ' +
          'could only be stored in the clear. Set it to base64 of 32 random bytes.',
      );
      throw ApiError.unavailable(
        'totp_unavailable',
        'This server has not been set up for two-factor authentication. Ask whoever runs it.',
      );
    }
    const secret = authenticator.generateSecret();
    await pool.query('UPDATE accounts SET totp_secret = $2, totp_enabled_at = NULL WHERE id = $1', [
      accountId,
      sealSecret(secret),
    ]);
    return { secret, otpauthUrl: authenticator.keyuri(username, 'Privio', secret) };
  });

  /** Step 2: prove the authenticator app works before the factor becomes mandatory. */
  app.post(
    '/v1/accounts/me/totp/enable',
    { ...guessable, preHandler: (r) => app.requireAuth(r) },
    async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ code: z.string().regex(/^\d{6}$/) }), request.body);
    const account = await accounts.findById(accountId);
    if (!account?.totp_secret) throw ApiError.badRequest('totp_not_set_up', 'Start with /totp/setup');
    const secret = openSecret(account.totp_secret);
    if (secret === null || !authenticator.check(body.code, secret)) {
      throw ApiError.badRequest('invalid_totp', 'Code is incorrect');
    }
    await pool.query('UPDATE accounts SET totp_enabled_at = now() WHERE id = $1', [accountId]);
    return { twoFactorEnabled: true };
  });

  app.delete(
    '/v1/accounts/me/totp',
    { ...guessable, preHandler: (r) => app.requireAuth(r) },
    async (request) => {
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
    // `RETURNING avatar_media_id` would hand back the value this statement has
    // just set — NULL — so the picture being removed was never named and was
    // left to sit in storage under the hundred-year expiry that making it an
    // avatar gave it. Reading the row first is what learns the old id.
    const { rows } = await pool.query<{ previous: string | null }>(
      `WITH prev AS (SELECT id, avatar_media_id FROM accounts WHERE id = $1 FOR UPDATE)
       UPDATE accounts SET avatar_media_id = NULL, avatar_updated_at = now()
         FROM prev WHERE accounts.id = prev.id
       RETURNING prev.avatar_media_id AS previous`,
      [accountId],
    );
    const removed = rows[0]?.previous ?? null;
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
    // Same order and the same reason: the rows that name the sockets are about
    // to be gone, so they are read first and the sockets closed afterwards.
    const open = await liveSessionsFor(accountId);
    await accounts.deleteAccount(accountId, storage);
    await announceRevocation(bus, open, request.log);
    return { deleted: true };
  });
};

export default accountRoutes;
