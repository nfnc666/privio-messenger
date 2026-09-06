import type { FastifyBaseLogger } from 'fastify';
import type { PoolClient } from '../db/pool.js';
import { pool } from '../db/pool.js';
import type { DeliveryBus } from './bus.js';
import type { PushProvider, PushSender, PushTarget } from './push.js';

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

/**
 * The one envelope type a phone has to be woken *now* for.
 *
 * Everything else can wait for whatever batching window the operating system
 * decides on — the envelope is stored, and it will still be there. A call will
 * not: nobody holds a ringing phone to their ear for four minutes, so a call
 * signal that arrives late is a call that was never offered at all.
 *
 * This is the only thing about an envelope the push layer is told, and it is
 * not content: it says a call is happening, not who is calling or whether it
 * was answered.
 */
const RINGS: ReadonlySet<EnvelopeType> = new Set(['call_signal']);

/**
 * How long a send waits for wake-ups before going on without them.
 *
 * The envelope is already stored and the live socket already published by the
 * time this runs, so a push is best effort by definition. It stopped being
 * free when a provider became something that makes a network call: a recipient
 * can now register an endpoint that black-holes, and without a deadline every
 * message to them would cost the *sender* the full request timeout.
 */
const WAKE_DEADLINE_MS = 1000;

export class DeliveryService {
  constructor(
    private readonly bus: DeliveryBus,
    private readonly push: PushSender,
    private readonly log?: FastifyBaseLogger,
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
    await Promise.all(
      deviceIds.map((id) => this.bus.publish({ deviceId: id, kind: 'envelopes' })),
    );
    const wakeable = deviceIds.filter((id) => durable.some((e) => e.recipientDeviceId === id));
    const ringing = new Set(
      durable.filter((e) => RINGS.has(e.type)).map((e) => e.recipientDeviceId),
    );
    await this.wake(wakeable, ringing);
  }

  /** Sends a contentless push to devices that have registered a token. */
  private async wake(deviceIds: string[], ringing: ReadonlySet<string> = new Set()): Promise<void> {
    if (deviceIds.length === 0) return;
    const { rows } = await pool.query<{
      id: string;
      push_provider: PushProvider;
      push_token: string;
      voip_token: string | null;
    }>(
      `SELECT id, push_provider, push_token, voip_token FROM devices
       WHERE id = ANY($1::uuid[]) AND revoked_at IS NULL
         AND push_provider IS NOT NULL AND push_token IS NOT NULL`,
      [deviceIds],
    );
    const pending = rows.map((row) =>
      this.notifyQuietly({
        deviceId: row.id,
        provider: row.push_provider,
        token: row.push_token,
        urgency: ringing.has(row.id) ? 'call' : 'normal',
        voipToken: row.voip_token,
      }),
    );

    // Stragglers are left to finish on their own — they can no longer reject,
    // so nothing is waiting on them and nothing crashes if they fail late.
    await Promise.race([Promise.all(pending), deadline(WAKE_DEADLINE_MS)]);
  }

  /**
   * A wake-up that cannot fail the send it belongs to.
   *
   * Every failure here is somebody else's endpoint being wrong: a distributor
   * that has gone away, a URL that stopped resolving publicly, a vendor
   * refusing a stale token. None of that means the message did not arrive —
   * it is already stored — so none of it may turn a successful send into an
   * error the sender sees and retries.
   */
  private async notifyQuietly(target: PushTarget): Promise<void> {
    try {
      if ((await this.push.notify(target)) === 'gone') await this.forget(target);
    } catch (err) {
      this.log?.debug(
        { err, deviceId: target.deviceId, provider: target.provider },
        'wake-up failed',
      );
    }
  }

  /**
   * Drops a token the vendor has told us is dead.
   *
   * Kept narrow on purpose: the update names the token it was told about, so a
   * device that registered a new one while this wake-up was in flight keeps
   * the new one. Without that condition a late "gone" for yesterday's token
   * would silently unregister a device that is working perfectly.
   */
  private async forget(target: PushTarget): Promise<void> {
    try {
      await pool.query(
        `UPDATE devices SET push_provider = NULL, push_token = NULL, voip_token = NULL
         WHERE id = $1 AND push_token = $2`,
        [target.deviceId, target.token],
      );
      this.log?.debug({ deviceId: target.deviceId }, 'push token dropped: the vendor says it is gone');
    } catch (err) {
      // Same rule as everything else here: a wake-up cannot fail a send.
      this.log?.debug({ err, deviceId: target.deviceId }, 'could not drop a dead push token');
    }
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

/** A timer that resolves after [ms] and never holds the process open. */
function deadline(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
  });
}
