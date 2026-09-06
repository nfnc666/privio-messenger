import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import {
  countOneTimePreKeys,
  deviceRegistrationSchema,
  fetchPreKeyBundles,
  storeOneTimePreKeys,
  storeSignedPreKey,
} from '../services/devices.js';
import { findByUsername } from '../services/accounts.js';
import { ApiError } from '../util/errors.js';
import { parsePushEndpoint } from '../util/outbound.js';
import { parse, usernameSchema, uuidSchema } from '../util/validate.js';
import { config } from '../config.js';

/** Hosts an endpoint may live on. Empty list means "any public host". */
function allowedPushHosts(): string[] {
  return config.UNIFIEDPUSH_ALLOWED_HOSTS.split(',')
    .map((host) => host.trim().toLowerCase())
    .filter((host) => host.length > 0);
}

const deviceRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  /** Connected-device management: what is logged in, and from where. */
  app.get('/v1/devices', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const { rows } = await pool.query(
      `SELECT d.id, d.name, d.platform, d.created_at, d.last_seen_at,
              (d.push_token IS NOT NULL) AS push_enabled,
              count(s.id) FILTER (WHERE s.revoked_at IS NULL AND s.expires_at > now()) AS active_sessions
       FROM devices d
       LEFT JOIN sessions s ON s.device_id = d.id
       WHERE d.account_id = $1 AND d.revoked_at IS NULL
       GROUP BY d.id
       ORDER BY d.created_at ASC`,
      [accountId],
    );
    return {
      devices: rows.map((r) => ({
        id: r.id,
        name: r.name,
        platform: r.platform,
        current: r.id === deviceId,
        pushEnabled: r.push_enabled,
        activeSessions: Number(r.active_sessions),
        createdAt: (r.created_at as Date).toISOString(),
        lastSeenAt: (r.last_seen_at as Date).toISOString(),
      })),
    };
  });

  /** Remote logout of one device. Its queued envelopes and prekeys go with it. */
  app.delete('/v1/devices/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const { rowCount } = await pool.query(
      'UPDATE devices SET revoked_at = now() WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL',
      [params.id, accountId],
    );
    if (!rowCount) throw ApiError.notFound('device_not_found', 'No such active device');
    await pool.query('UPDATE sessions SET revoked_at = now() WHERE device_id = $1 AND revoked_at IS NULL', [
      params.id,
    ]);
    await pool.query('DELETE FROM envelopes WHERE recipient_device_id = $1', [params.id]);
    return { revoked: true };
  });

  app.put('/v1/devices/current/push', requireAuth, async (request) => {
    const { deviceId } = auth(request);
    const body = parse(
      z.object({
        provider: z.enum(['apns', 'fcm', 'unifiedpush']).nullable(),
        token: z.string().min(1).max(512).nullable(),
        /**
         * iOS only, and optional: the PushKit token a call arrives on. Sent
         * alongside the ordinary one because they are issued separately and
         * either can be reissued without the other.
         */
        voipToken: z.string().min(1).max(512).nullable().optional(),
      }),
      request.body,
    );
    if ((body.provider === null) !== (body.token === null)) {
      throw ApiError.badRequest('invalid_push_config', 'provider and token must be set or cleared together');
    }
    // A VoIP token only means anything on APNs. Accepting one for FCM or a
    // distributor would be storing a string nothing will ever read.
    if (body.voipToken != null && body.provider !== 'apns') {
      throw ApiError.badRequest('invalid_push_config', 'a VoIP token belongs to apns only');
    }
    // A UnifiedPush token is not a handle a vendor resolves — it is an address
    // this server will POST to. Checked here so a bad one is rejected while
    // someone is looking at it, and again before every send.
    if (body.provider === 'unifiedpush' && body.token !== null) {
      parsePushEndpoint(body.token, { allowedHosts: allowedPushHosts() });
    }
    // Clearing the provider clears the VoIP token with it: a device that has
    // stopped being pushed to has stopped ringing too, and leaving one behind
    // would have the relay calling a phone that signed out.
    await pool.query(
      'UPDATE devices SET push_provider = $2, push_token = $3, voip_token = $4 WHERE id = $1',
      [deviceId, body.provider, body.token, body.provider === null ? null : body.voipToken ?? null],
    );
    return { pushEnabled: body.token !== null, callsRing: body.voipToken != null };
  });

  /** Rotate this device's signed prekey (clients do this on a schedule). */
  app.put('/v1/keys/signed-prekey', requireAuth, async (request) => {
    const { deviceId } = auth(request);
    const body = parse(deviceRegistrationSchema.shape.signedPreKey, request.body);
    await storeSignedPreKey(pool, deviceId, body);
    return { updated: true };
  });

  /** Top up the one-time prekey pool. */
  app.post('/v1/keys/one-time', requireAuth, async (request) => {
    const { deviceId } = auth(request);
    const body = parse(z.object({ keys: deviceRegistrationSchema.shape.oneTimePreKeys }), request.body);
    await storeOneTimePreKeys(pool, deviceId, body.keys);
    return { remaining: await countOneTimePreKeys(deviceId) };
  });

  app.get('/v1/keys/count', requireAuth, async (request) => {
    const { deviceId } = auth(request);
    return { remaining: await countOneTimePreKeys(deviceId) };
  });

  /**
   * Prekey bundles for every active device of a user, so the caller can open a
   * Signal session per device. Consuming a one-time prekey is a side effect.
   */
  app.get('/v1/keys/:username', requireAuth, async (request) => {
    const { accountId, deviceId } = auth(request);
    const params = parse(z.object({ username: usernameSchema }), request.params);
    const target = await findByUsername(params.username);
    if (!target) throw ApiError.notFound('user_not_found', 'No such user');
    // Asking for your own account means "my other devices" — the copy of a
    // message that keeps a second device's view of a conversation from drifting
    // away from the first. A device never needs a session with itself.
    const bundles = await fetchPreKeyBundles(
      target.id,
      target.id === accountId ? deviceId : undefined,
    );
    if (bundles.length === 0) throw ApiError.notFound('no_devices', 'User has no active devices');
    return { accountId: target.id, username: target.username, devices: bundles };
  });
};

export default deviceRoutes;
