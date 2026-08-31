import type { PoolClient } from '../db/pool.js';
import { pool } from '../db/pool.js';
import type { DeliveryBus } from './bus.js';
import type { PushProvider, PushSender } from './push.js';

export type EnvelopeType =
  | 'prekey'
  | 'ciphertext'
  | 'receipt'
  | 'typing'
  | 'key_change'
  | 'group_update'
  | 'call_signal';

export interface OutgoingEnvelope {
  recipientDeviceId: string;
  senderAccountId: string;
  senderDeviceId: string;
  groupId?: string | null;
  type: EnvelopeType;
  content: Buffer;
}

export interface StoredEnvelope {
  id: number;
  type: EnvelopeType;
  senderAccountId: string | null;
  senderDeviceId: string | null;
  /** The sender's per-account index, which is how the protocol names a session. */
  senderDeviceIndex: number | null;
  groupId: string | null;
  content: string; // base64
  createdAt: string;
}

/** Ephemeral envelope types are dropped rather than queued for an offline device. */
const EPHEMERAL: ReadonlySet<EnvelopeType> = new Set(['typing']);

export class DeliveryService {
  constructor(
    private readonly bus: DeliveryBus,
    private readonly push: PushSender,
  ) {}

  /** Persists envelopes, wakes any live socket, and pushes to devices that are offline. */
  async enqueue(envelopes: OutgoingEnvelope[], client?: PoolClient): Promise<void> {
    if (envelopes.length === 0) return;
    const db = client ?? pool;

    const durable = envelopes.filter((e) => !EPHEMERAL.has(e.type));
    if (durable.length > 0) {
      // One multi-row INSERT keeps group fan-out to a single round trip.
      const values: unknown[] = [];
      const tuples = durable.map((e, i) => {
        const o = i * 6;
        values.push(e.recipientDeviceId, e.senderAccountId, e.senderDeviceId, e.groupId ?? null, e.type, e.content);
        return `($${o + 1}, $${o + 2}, $${o + 3}, $${o + 4}, $${o + 5}, $${o + 6})`;
      });
      await db.query(
        `INSERT INTO envelopes (recipient_device_id, sender_account_id, sender_device_id, group_id, envelope_type, content)
         VALUES ${tuples.join(', ')}`,
        values,
      );
    }

    const deviceIds = [...new Set(envelopes.map((e) => e.recipientDeviceId))];
    await Promise.all(deviceIds.map((id) => this.bus.publish(id)));
    await this.wake(deviceIds.filter((id) => durable.some((e) => e.recipientDeviceId === id)));
  }

  /** Sends a contentless push to devices that have registered a token. */
  private async wake(deviceIds: string[]): Promise<void> {
    if (deviceIds.length === 0) return;
    const { rows } = await pool.query<{ id: string; push_provider: PushProvider; push_token: string }>(
      `SELECT id, push_provider, push_token FROM devices
       WHERE id = ANY($1::uuid[]) AND revoked_at IS NULL
         AND push_provider IS NOT NULL AND push_token IS NOT NULL`,
      [deviceIds],
    );
    await Promise.all(
      rows.map((row) =>
        this.push.notify({ deviceId: row.id, provider: row.push_provider, token: row.push_token }),
      ),
    );
  }

  /** Returns queued envelopes for a device, oldest first. */
  async fetch(deviceId: string, limit = 100): Promise<StoredEnvelope[]> {
    const { rows } = await pool.query(
      `SELECT e.id, e.envelope_type, e.sender_account_id, e.sender_device_id,
              s.device_index AS sender_device_index, e.group_id, e.content, e.created_at
       FROM envelopes e
       LEFT JOIN devices s ON s.id = e.sender_device_id
       WHERE e.recipient_device_id = $1 ORDER BY e.id ASC LIMIT $2`,
      [deviceId, limit],
    );
    return rows.map((r) => ({
      id: r.id as number,
      type: r.envelope_type as EnvelopeType,
      senderAccountId: r.sender_account_id,
      senderDeviceId: r.sender_device_id,
      senderDeviceIndex: r.sender_device_index,
      groupId: r.group_id,
      content: (r.content as Buffer).toString('base64'),
      createdAt: (r.created_at as Date).toISOString(),
    }));
  }

  /** Deletes acknowledged envelopes. Delivery is at-least-once until this lands. */
  async acknowledge(deviceId: string, upToId: number): Promise<number> {
    const { rowCount } = await pool.query(
      'DELETE FROM envelopes WHERE recipient_device_id = $1 AND id <= $2',
      [deviceId, upToId],
    );
    return rowCount ?? 0;
  }
}
