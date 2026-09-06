import { pool } from '../db/pool.js';
import type { DeliveryBus } from './bus.js';

/**
 * "This device of mine still needs the key."
 *
 * A join link cannot carry a key — it is meant to be posted in public — so a
 * new member arrives without one. They record a request here; any member who
 * already holds the key seals it to that device over the Signal session the two
 * accounts have, and clears the request. The server moves both halves without
 * being able to read either.
 *
 * Requests are per device, not per account: a key is sealed to one device at a
 * time, so a second device of the same account asks for itself.
 */
export type KeyScope = 'channel' | 'group';

export async function recordKeyRequest(
  scope: KeyScope,
  scopeId: string,
  accountId: string,
  deviceId: string,
): Promise<void> {
  await pool.query(
    `INSERT INTO key_requests (scope, scope_id, account_id, device_id)
     VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
    [scope, scopeId, accountId, deviceId],
  );
}

/**
 * Tells the devices that could answer a request that there is one.
 *
 * Without it a request sits until whoever holds the key next polls, which is
 * two minutes on the client's own timer — long enough that a second device
 * signing in looks at a group it cannot name for the whole of it.
 *
 * The wake carries a device id and a reason and nothing else. The key never
 * touches the server, and this does not change that: it only says that
 * somebody is waiting.
 *
 * Every member's device except the asking one. A key is sealed per device, and
 * the account's own other devices are both allowed to answer and the likeliest
 * to be online holding it.
 */
export async function wakeKeyHolders(
  bus: DeliveryBus,
  scope: KeyScope,
  scopeId: string,
  exceptDeviceId: string,
): Promise<number> {
  const membership = scope === 'group' ? 'group_members' : 'channel_members';
  const column = scope === 'group' ? 'group_id' : 'channel_id';
  const { rows } = await pool.query<{ id: string }>(
    `SELECT d.id
     FROM ${membership} m
     JOIN devices d ON d.account_id = m.account_id AND d.revoked_at IS NULL
     WHERE m.${column} = $1 AND d.id <> $2
     LIMIT 500`,
    [scopeId, exceptDeviceId],
  );
  await Promise.all(
    rows.map((row) => bus.publish({ deviceId: row.id, kind: 'key-request' })),
  );
  return rows.length;
}

export interface PendingKeyRequest {
  accountId: string;
  username: string;
  deviceId: string;
  deviceIndex: number;
  registrationId: number;
  requestedAt: string;
}

/**
 * Who is waiting, excluding [exceptDeviceId] — the caller's own device, which
 * cannot answer its own request.
 *
 * Joined against membership, which is belt and braces on purpose. Removal
 * already deletes the leaver's requests, but that is a delete racing an insert:
 * a device that recorded a request in the same second as its account was
 * removed would otherwise leave a row behind, and every member's app would
 * dutifully seal the new key to somebody who was just thrown out. The join
 * makes the answer depend on membership *now* rather than on which write
 * landed first.
 */
export async function pendingKeyRequests(
  scope: KeyScope,
  scopeId: string,
  exceptDeviceId: string,
): Promise<PendingKeyRequest[]> {
  const membership = scope === 'group' ? 'group_members' : 'channel_members';
  const column = scope === 'group' ? 'group_id' : 'channel_id';
  const { rows } = await pool.query(
    `SELECT r.account_id, a.username, r.device_id, d.device_index, d.registration_id,
            r.requested_at
     FROM key_requests r
     JOIN devices d ON d.id = r.device_id AND d.revoked_at IS NULL
     JOIN accounts a ON a.id = r.account_id AND a.deleted_at IS NULL
     JOIN ${membership} m ON m.${column} = r.scope_id AND m.account_id = r.account_id
     WHERE r.scope = $1 AND r.scope_id = $2 AND r.device_id <> $3
     ORDER BY r.requested_at ASC
     LIMIT 200`,
    [scope, scopeId, exceptDeviceId],
  );
  return rows.map((r) => ({
    accountId: r.account_id,
    username: r.username,
    deviceId: r.device_id,
    deviceIndex: r.device_index,
    registrationId: r.registration_id,
    requestedAt: (r.requested_at as Date).toISOString(),
  }));
}

export async function clearKeyRequest(
  scope: KeyScope,
  scopeId: string,
  deviceId: string,
): Promise<void> {
  await pool.query(
    'DELETE FROM key_requests WHERE scope = $1 AND scope_id = $2 AND device_id = $3',
    [scope, scopeId, deviceId],
  );
}

/** Called when someone leaves: a request from a non-member must not linger. */
export async function clearKeyRequestsFor(
  scope: KeyScope,
  scopeId: string,
  accountId: string,
): Promise<void> {
  await pool.query(
    'DELETE FROM key_requests WHERE scope = $1 AND scope_id = $2 AND account_id = $3',
    [scope, scopeId, accountId],
  );
}
