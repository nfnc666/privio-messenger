import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { config, rateLimitFactor } from '../config.js';
import { auth } from '../plugins/auth.js';
import type { DeliveryService, OutgoingEnvelope } from '../services/delivery.js';
import {
  ACCESS_KEY_BYTES,
  accessKeyMatches,
  issueSenderCertificate,
  type SealedSenderKeys,
} from '../services/sealed_sender.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, disappearSecondsSchema, parse, uuidSchema } from '../util/validate.js';

/**
 * Sealed sender: delivering a message without learning who sent it.
 *
 * Four routes, and the split between them is the design:
 *
 * * the **certificate** and the **access key** routes are authenticated — they
 *   are where this server knows who is asking, and they hand out or store
 *   nothing that says who anybody is talking to;
 * * the **send** route is not, and refuses to be: it never reads a session, it
 *   is not logged, and the envelope it stores names no sender.
 *
 * See docs/sealed-sender.md, which this file implements the server half of.
 */

const UNAVAILABLE = () =>
  new ApiError(503, 'sealed_sender_unavailable', 'Sealed sender is not configured on this server');

/**
 * One answer for every way an unidentified send is not let in: no such
 * account, an account that accepts no sealed messages, a wrong key. Three
 * answers would make this route a way to ask whether an account exists.
 */
const DENIED = () =>
  new ApiError(401, 'unidentified_access_denied', 'Not permitted to send sealed messages to this account');

const sealedSendSchema = z.object({
  accountId: uuidSchema,
  /** Same bound as an ordinary send. Only how long the server keeps it. */
  expiresInSeconds: disappearSecondsSchema.optional(),
  messages: z
    .array(
      z.object({
        deviceId: uuidSchema,
        registrationId: z.number().int().min(1).max(16383),
        content: base64Bytes(1, config.MAX_ENVELOPE_BYTES),
      }),
    )
    .min(1)
    .max(256)
    .refine((messages) => new Set(messages.map((m) => m.deviceId)).size === messages.length, {
      message: 'each recipient device may appear only once',
    }),
});

function readAccessKey(header: string | string[] | undefined): Buffer | null {
  if (typeof header !== 'string') return null;
  const bytes = Buffer.from(header, 'base64');
  return bytes.length === ACCESS_KEY_BYTES ? bytes : null;
}

export function sealedSenderRoutes(
  delivery: DeliveryService,
  keys: SealedSenderKeys | null,
): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = {
      preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
    };
    // A certificate is what sending sealed costs, so it is what the license
    // pays for. The send itself cannot check a license: a send this server
    // cannot attribute is a send it cannot attribute to a license either. A
    // device that loses its license keeps a certificate for a day at most.
    const requireLicensedAuth = {
      preHandler: [
        (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
        (r: Parameters<typeof app.requireLicense>[0]) => app.requireLicense(r),
      ],
    };

    /**
     * The key every certificate chains to. Public by definition, and the app
     * pins it on first use rather than re-reading it on every launch.
     */
    app.get('/v1/certificate/trust-root', async () => {
      if (!keys) throw UNAVAILABLE();
      return { trustRoot: Buffer.from(keys.trustRoot.serialize()).toString('base64') };
    });

    /**
     * A certificate for this device: this account, this device's index, and
     * the identity key this server holds for it — read from the database, not
     * taken from the request.
     */
    app.get('/v1/certificate/delivery', requireLicensedAuth, async (request) => {
      if (!keys) throw UNAVAILABLE();
      const { accountId, deviceId } = auth(request);
      const { rows } = await pool.query<{ device_index: number; identity_key: Buffer }>(
        `SELECT device_index, identity_key FROM devices
          WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL`,
        [deviceId, accountId],
      );
      const device = rows[0];
      if (!device) throw ApiError.unauthorized('device_revoked', 'This device is no longer signed in');
      let issued: ReturnType<typeof issueSenderCertificate>;
      try {
        issued = issueSenderCertificate(keys, {
          accountId,
          deviceIndex: device.device_index,
          identityKey: device.identity_key,
        });
      } catch {
        // Registration takes 32 to 64 bytes; the app sends a 33-byte Curve25519
        // key. Anything else cannot be certified, and saying so beats a 500.
        throw ApiError.conflict(
          'identity_key_unusable',
          'This device registered an identity key that cannot be certified',
        );
      }
      return {
        certificate: issued.certificate.toString('base64'),
        expiresAt: issued.expiresAt.toISOString(),
      };
    });

    /**
     * Stores the key that lets people this account has talked to send it
     * sealed messages. Derived on the device from the profile key; the server
     * keeps it to compare and never hands it back.
     */
    app.put('/v1/accounts/me/unidentified-access', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const body = parse(
        z.object({ accessKey: base64Bytes(ACCESS_KEY_BYTES, ACCESS_KEY_BYTES) }),
        request.body,
      );
      await pool.query('UPDATE accounts SET unidentified_access_key = $1 WHERE id = $2', [
        body.accessKey,
        accountId,
      ]);
      return { enabled: true };
    });

    /** Stops accepting sealed messages. Ordinary ones still arrive. */
    app.delete('/v1/accounts/me/unidentified-access', requireAuth, async (request) => {
      const { accountId } = auth(request);
      await pool.query('UPDATE accounts SET unidentified_access_key = NULL WHERE id = $1', [
        accountId,
      ]);
      return { enabled: false };
    });

    /**
     * Delivers sealed envelopes to every device of one account, without a
     * session and without a record of who sent them.
     *
     * `logLevel: 'silent'` keeps the request — its address and URL — out of
     * the log, which is where an otherwise anonymous send would be tied back
     * to the address that also signs in. Rate-limited per address in memory,
     * like every route that has no account to count against.
     */
    app.post(
      '/v1/messages/sealed',
      {
        logLevel: 'silent',
        config: { rateLimit: { max: 120 * rateLimitFactor, timeWindow: '1 minute' } },
      },
      async (request, reply) => {
        // A sealed send that also says who sent it is a bug that would undo the
        // point without anybody noticing. Refused loudly instead.
        if (request.headers.authorization) {
          throw ApiError.badRequest(
            'do_not_identify',
            'A sealed send must not carry a session. Send it without Authorization.',
          );
        }
        if (!keys) throw UNAVAILABLE();

        const presented = readAccessKey(request.headers['unidentified-access-key']);
        const body = parse(sealedSendSchema, request.body);

        const { rows } = await pool.query<{ unidentified_access_key: Buffer | null }>(
          'SELECT unidentified_access_key FROM accounts WHERE id = $1 AND deleted_at IS NULL',
          [body.accountId],
        );
        if (!accessKeyMatches(rows[0]?.unidentified_access_key ?? null, presented)) {
          throw DENIED();
        }

        // The same reconciliation as an ordinary send: sealed once per device,
        // and a stale list is refused with the difference rather than skipping
        // one of somebody's phones.
        const { rows: devices } = await pool.query<{ id: string }>(
          'SELECT id FROM devices WHERE account_id = $1 AND revoked_at IS NULL ORDER BY id',
          [body.accountId],
        );
        const expected = devices.map((d) => d.id);
        const provided = new Set(body.messages.map((m) => m.deviceId));
        const missingDevices = expected.filter((id) => !provided.has(id));
        const extraDevices = [...provided].filter((id) => !expected.includes(id));
        if (missingDevices.length || extraDevices.length) {
          throw Object.assign(
            new ApiError(409, 'device_mismatch', 'Recipient device list is stale; re-fetch prekey bundles'),
            { missingDevices, extraDevices },
          );
        }

        const expiresAt = body.expiresInSeconds
          ? new Date(Date.now() + body.expiresInSeconds * 1000)
          : null;
        const envelopes: OutgoingEnvelope[] = body.messages.map((m) => ({
          recipientDeviceId: m.deviceId,
          senderAccountId: null,
          senderDeviceId: null,
          type: 'sealed',
          content: m.content,
          expiresAt,
        }));
        await delivery.enqueue(envelopes);
        reply.code(202);
        return { accepted: true, deliveredTo: envelopes.length };
      },
    );
  };
}

export default sealedSenderRoutes;
