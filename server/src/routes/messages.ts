import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import { findByUsername } from '../services/accounts.js';
import type { DeliveryService, OutgoingEnvelope } from '../services/delivery.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse, usernameSchema, uuidSchema } from '../util/validate.js';

const perDeviceSchema = z.object({
  deviceId: uuidSchema,
  registrationId: z.number().int().min(1).max(16383),
  type: z.enum(['prekey', 'ciphertext', 'receipt', 'typing', 'key_change', 'group_update', 'call_signal']),
  content: base64Bytes(1, config.MAX_ENVELOPE_BYTES),
});

const sendSchema = z
  .object({
    username: usernameSchema.optional(),
    accountId: uuidSchema.optional(),
    messages: z.array(perDeviceSchema).min(1).max(256),
  })
  .refine((v) => Boolean(v.username) !== Boolean(v.accountId), {
    message: 'provide exactly one of username or accountId',
  });

/**
 * A message must be sealed once per recipient device. If the client's idea of
 * the device list is stale the whole send is rejected with the difference, so
 * nobody ends up with a conversation that silently skips one of their phones.
 */
function reconcile(expected: string[], provided: string[]) {
  const providedSet = new Set(provided);
  const expectedSet = new Set(expected);
  return {
    missingDevices: expected.filter((id) => !providedSet.has(id)),
    extraDevices: provided.filter((id) => !expectedSet.has(id)),
  };
}

async function activeDeviceIds(accountId: string): Promise<string[]> {
  const { rows } = await pool.query<{ id: string }>(
    'SELECT id FROM devices WHERE account_id = $1 AND revoked_at IS NULL ORDER BY id',
    [accountId],
  );
  return rows.map((r) => r.id);
}

async function isBlockedBy(ownerId: string, candidateId: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    'SELECT 1 FROM blocks WHERE account_id = $1 AND blocked_account_id = $2',
    [ownerId, candidateId],
  );
  return Boolean(rowCount);
}

export function messageRoutes(delivery: DeliveryService): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

    /** Send pre-sealed ciphertext to every device of one account. */
    app.post('/v1/messages', requireAuth, async (request, reply) => {
      const { accountId, deviceId } = auth(request);
      const body = parse(sendSchema, request.body);

      const target = body.username
        ? await findByUsername(body.username)
        : (await pool.query('SELECT * FROM accounts WHERE id = $1 AND deleted_at IS NULL', [body.accountId]))
            .rows[0];
      if (!target) throw ApiError.notFound('user_not_found', 'No such user');

      // A sender is never told they are blocked; the send simply goes nowhere.
      if (target.id !== accountId && (await isBlockedBy(target.id, accountId))) {
        reply.code(202);
        return { accepted: true, deliveredTo: 0 };
      }

      const expected = (await activeDeviceIds(target.id))
        // Sending to yourself (multi-device sync) must not echo to this device.
        .filter((id) => !(target.id === accountId && id === deviceId));
      if (expected.length === 0) throw ApiError.notFound('no_devices', 'Recipient has no active devices');

      const { missingDevices, extraDevices } = reconcile(expected, body.messages.map((m) => m.deviceId));
      if (missingDevices.length || extraDevices.length) {
        throw Object.assign(
          new ApiError(409, 'device_mismatch', 'Recipient device list is stale; re-fetch prekey bundles'),
          { missingDevices, extraDevices },
        );
      }

      const envelopes: OutgoingEnvelope[] = body.messages.map((m) => ({
        recipientDeviceId: m.deviceId,
        senderAccountId: accountId,
        senderDeviceId: deviceId,
        type: m.type,
        content: m.content,
      }));
      await delivery.enqueue(envelopes);
      reply.code(202);
      return { accepted: true, deliveredTo: envelopes.length };
    });

    /** Fan out to every member device of a group. */
    app.post('/v1/messages/group/:groupId', requireAuth, async (request, reply) => {
      const { accountId, deviceId } = auth(request);
      const params = parse(z.object({ groupId: uuidSchema }), request.params);
      const body = parse(z.object({ messages: z.array(perDeviceSchema).min(1).max(2048) }), request.body);

      const { rowCount: isMember } = await pool.query(
        `SELECT 1 FROM group_members m JOIN groups g ON g.id = m.group_id
         WHERE m.group_id = $1 AND m.account_id = $2 AND g.deleted_at IS NULL`,
        [params.groupId, accountId],
      );
      if (!isMember) throw ApiError.forbidden('not_a_member', 'You are not a member of this group');

      // Members who blocked the sender are dropped from the fan-out silently.
      const { rows } = await pool.query<{ id: string }>(
        `SELECT d.id FROM group_members m
         JOIN devices d ON d.account_id = m.account_id AND d.revoked_at IS NULL
         WHERE m.group_id = $1
           AND d.id <> $2
           AND NOT EXISTS (
             SELECT 1 FROM blocks b WHERE b.account_id = m.account_id AND b.blocked_account_id = $3
           )
         ORDER BY d.id`,
        [params.groupId, deviceId, accountId],
      );
      const expected = rows.map((r) => r.id);
      const provided = body.messages.map((m) => m.deviceId);
      const { missingDevices } = reconcile(expected, provided);
      if (missingDevices.length) {
        throw Object.assign(
          new ApiError(409, 'device_mismatch', 'Group device list is stale; re-fetch prekey bundles'),
          { missingDevices, extraDevices: [] },
        );
      }

      const allowed = new Set(expected);
      const envelopes: OutgoingEnvelope[] = body.messages
        .filter((m) => allowed.has(m.deviceId))
        .map((m) => ({
          recipientDeviceId: m.deviceId,
          senderAccountId: accountId,
          senderDeviceId: deviceId,
          groupId: params.groupId,
          type: m.type,
          content: m.content,
        }));
      await delivery.enqueue(envelopes);
      reply.code(202);
      return { accepted: true, deliveredTo: envelopes.length };
    });

    /** Drain this device's queue. Envelopes stay until acknowledged. */
    app.get('/v1/messages', requireAuth, async (request) => {
      const { deviceId } = auth(request);
      const query = parse(
        z.object({ limit: z.coerce.number().int().min(1).max(500).default(100) }),
        request.query,
      );
      const envelopes = await delivery.fetch(deviceId, query.limit);
      return { envelopes, more: envelopes.length === query.limit };
    });

    app.delete('/v1/messages', requireAuth, async (request) => {
      const { deviceId } = auth(request);
      const query = parse(z.object({ upTo: z.coerce.number().int().min(1) }), request.query);
      return { acknowledged: await delivery.acknowledge(deviceId, query.upTo) };
    });
  };
}

export default messageRoutes;
