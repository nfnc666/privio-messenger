import { z } from 'zod';
import type { PoolClient } from '../db/pool.js';
import { pool } from '../db/pool.js';
import { base64Bytes } from '../util/validate.js';
import { ApiError } from '../util/errors.js';

/** X3DH registration material. Public keys only — private halves stay on the device. */
export const deviceRegistrationSchema = z.object({
  name: z.string().trim().min(1).max(64),
  platform: z.enum(['ios', 'android', 'desktop', 'web']),
  registrationId: z.number().int().min(1).max(16383),
  identityKey: base64Bytes(32, 64),
  signedPreKey: z.object({
    keyId: z.number().int().min(0).max(0xffffff),
    publicKey: base64Bytes(32, 64),
    signature: base64Bytes(32, 128),
  }),
  oneTimePreKeys: z
    .array(
      z.object({
        keyId: z.number().int().min(0).max(0xffffff),
        publicKey: base64Bytes(32, 64),
      }),
    )
    .max(200)
    .default([]),
});

export type DeviceRegistration = z.infer<typeof deviceRegistrationSchema>;

/**
 * The cap for an account with no license behind it — a self-hosted deployment,
 * or an account on the hosted service that has not activated a key yet.
 *
 * A licensed account uses its license's own limit instead, which is what
 * [deviceLimitFor] resolves. The two are the same number today; they are
 * separate so that selling a larger licence never means redeploying.
 */
export const DEFAULT_DEVICE_LIMIT = 5;

/**
 * How many active devices this account may have.
 *
 * Read inside the caller's transaction, which already holds the account row
 * lock — so the limit that is checked is the limit at the moment the device is
 * inserted, and a license revoked mid-registration cannot be raced past.
 */
export async function deviceLimitFor(client: PoolClient, accountId: string): Promise<number> {
  const { rows } = await client.query<{ max_devices: number }>(
    `SELECT max_devices FROM licenses
      WHERE redeemed_by = $1 AND status = 'active'`,
    [accountId],
  );
  return rows[0]?.max_devices ?? DEFAULT_DEVICE_LIMIT;
}

export interface RegisteredDevice {
  deviceId: string;
  deviceIndex: number;
}

export async function registerDevice(
  client: PoolClient,
  accountId: string,
  input: DeviceRegistration,
): Promise<RegisteredDevice> {
  // Serialise concurrent registrations for this account so two devices cannot
  // race onto the same index.
  await client.query('SELECT id FROM accounts WHERE id = $1 FOR UPDATE', [accountId]);

  const { rows: existing } = await client.query<{ count: string }>(
    'SELECT count(*) FROM devices WHERE account_id = $1 AND revoked_at IS NULL',
    [accountId],
  );
  const limit = await deviceLimitFor(client, accountId);
  if (Number(existing[0]!.count) >= limit) {
    throw ApiError.conflict(
      'too_many_devices',
      `This license covers ${limit} active device${limit === 1 ? '' : 's'}. ` +
        'Remove one in Settings → Devices to add another.',
    );
  }

  const deviceIndex = await nextDeviceIndex(client, accountId);
  const { rows } = await client.query<{ id: string }>(
    `INSERT INTO devices (account_id, name, platform, registration_id, identity_key, device_index)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [accountId, input.name, input.platform, input.registrationId, input.identityKey, deviceIndex],
  );
  const deviceId = rows[0]!.id;
  await storeSignedPreKey(client, deviceId, input.signedPreKey);
  await storeOneTimePreKeys(client, deviceId, input.oneTimePreKeys);
  return { deviceId, deviceIndex };
}

/**
 * The lowest index not already taken on this account, counting revoked devices:
 * reusing a retired index would let an old Signal session address a new device.
 */
async function nextDeviceIndex(client: PoolClient, accountId: string): Promise<number> {
  const { rows } = await client.query<{ next_index: number }>(
    `SELECT COALESCE(max(device_index), 0) + 1 AS next_index
     FROM devices WHERE account_id = $1`,
    [accountId],
  );
  return rows[0]!.next_index;
}

export async function storeSignedPreKey(
  client: PoolClient | typeof pool,
  deviceId: string,
  key: DeviceRegistration['signedPreKey'],
): Promise<void> {
  await client.query(
    `INSERT INTO signed_prekeys (device_id, key_id, public_key, signature)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (device_id) DO UPDATE
       SET key_id = EXCLUDED.key_id,
           public_key = EXCLUDED.public_key,
           signature = EXCLUDED.signature,
           created_at = now()`,
    [deviceId, key.keyId, key.publicKey, key.signature],
  );
}

export async function storeOneTimePreKeys(
  client: PoolClient | typeof pool,
  deviceId: string,
  keys: { keyId: number; publicKey: Buffer }[],
): Promise<void> {
  if (keys.length === 0) return;
  const values: unknown[] = [];
  const tuples = keys.map((k, i) => {
    values.push(deviceId, k.keyId, k.publicKey);
    return `($${i * 3 + 1}, $${i * 3 + 2}, $${i * 3 + 3})`;
  });
  await client.query(
    `INSERT INTO one_time_prekeys (device_id, key_id, public_key)
     VALUES ${tuples.join(', ')}
     ON CONFLICT (device_id, key_id) DO NOTHING`,
    values,
  );
}

export interface PreKeyBundle {
  deviceId: string;
  /** Stable per-account index used to build the Signal address. */
  deviceIndex: number;
  registrationId: number;
  identityKey: string;
  signedPreKey: { keyId: number; publicKey: string; signature: string };
  oneTimePreKey: { keyId: number; publicKey: string } | null;
}

/**
 * Hands out one bundle per active device of the target account, consuming a
 * one-time prekey where any remain. A device with an exhausted pool still gets
 * a usable bundle from its signed prekey (weaker forward secrecy until the
 * client tops up — clients refill well before the pool empties).
 */
export async function fetchPreKeyBundles(accountId: string): Promise<PreKeyBundle[]> {
  const { rows: devices } = await pool.query(
    `SELECT d.id, d.device_index, d.registration_id, d.identity_key,
            s.key_id AS spk_id, s.public_key AS spk_pub, s.signature AS spk_sig
     FROM devices d
     JOIN signed_prekeys s ON s.device_id = d.id
     WHERE d.account_id = $1 AND d.revoked_at IS NULL`,
    [accountId],
  );

  const bundles: PreKeyBundle[] = [];
  for (const device of devices) {
    // DELETE ... RETURNING makes consumption atomic against concurrent fetches.
    const { rows: otp } = await pool.query(
      `DELETE FROM one_time_prekeys
       WHERE (device_id, key_id) IN (
         SELECT device_id, key_id FROM one_time_prekeys
         WHERE device_id = $1 ORDER BY key_id LIMIT 1 FOR UPDATE SKIP LOCKED
       )
       RETURNING key_id, public_key`,
      [device.id],
    );
    bundles.push({
      deviceId: device.id,
      deviceIndex: device.device_index,
      registrationId: device.registration_id,
      identityKey: (device.identity_key as Buffer).toString('base64'),
      signedPreKey: {
        keyId: device.spk_id,
        publicKey: (device.spk_pub as Buffer).toString('base64'),
        signature: (device.spk_sig as Buffer).toString('base64'),
      },
      oneTimePreKey: otp[0]
        ? { keyId: otp[0].key_id, publicKey: (otp[0].public_key as Buffer).toString('base64') }
        : null,
    });
  }
  return bundles;
}

export async function countOneTimePreKeys(deviceId: string): Promise<number> {
  const { rows } = await pool.query<{ count: string }>(
    'SELECT count(*) FROM one_time_prekeys WHERE device_id = $1',
    [deviceId],
  );
  return Number(rows[0]!.count);
}
