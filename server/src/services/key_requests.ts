import { pool } from '../db/pool.js';

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
 */
export async function pendingKeyRequests(
  scope: KeyScope,
  scopeId: string,
  exceptDeviceId: string,
): Promise<PendingKeyRequest[]> {
  const { rows } = await pool.query(
    `SELECT r.account_id, a.username, r.device_id, d.device_index, d.registration_id,
            r.requested_at
     FROM key_requests r
     JOIN devices d ON d.id = r.device_id AND d.revoked_at IS NULL
     JOIN accounts a ON a.id = r.account_id AND a.deleted_at IS NULL
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
