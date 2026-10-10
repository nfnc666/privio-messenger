import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { generateToken, tokenHash } from '../util/crypto.js';

export interface AuthContext {
  sessionId: string;
  accountId: string;
  deviceId: string;
  username: string;
}

export interface IssuedSession {
  token: string;
  expiresAt: Date;
  sessionId: string;
}

/**
 * Issues a session for a device.
 *
 * No user agent, no address: nothing about the client is kept beyond the
 * device it belongs to (migration 044). Times are to the hour — see
 * `resolveSession` for why — and the session ends after `SESSION_TTL_DAYS`
 * without use, not that long after it was issued.
 */
export async function createSession(accountId: string, deviceId: string): Promise<IssuedSession> {
  const token = generateToken();
  const { rows } = await pool.query<{ id: string; expires_at: Date }>(
    `INSERT INTO sessions (account_id, device_id, token_hash, last_used_at, expires_at)
     VALUES ($1, $2, $3, date_trunc('hour', now(), 'UTC'),
             date_trunc('hour', now(), 'UTC') + make_interval(days => $4))
     RETURNING id, expires_at`,
    [accountId, deviceId, tokenHash(token), config.SESSION_TTL_DAYS],
  );
  return { token, expiresAt: rows[0]!.expires_at, sessionId: rows[0]!.id };
}

/** Resolves a bearer token to an auth context, or null when it is invalid, expired or revoked. */
export async function resolveSession(token: string): Promise<AuthContext | null> {
  const { rows } = await pool.query(
    `SELECT s.id, s.account_id, s.device_id, a.username
     FROM sessions s
     JOIN accounts a ON a.id = s.account_id
     JOIN devices d ON d.id = s.device_id
     WHERE s.token_hash = $1
       AND s.revoked_at IS NULL AND s.expires_at > now()
       AND a.deleted_at IS NULL AND d.revoked_at IS NULL`,
    [tokenHash(token)],
  );
  const row = rows[0];
  if (!row) return null;

  // Presence bookkeeping is best-effort and must not block the request — and
  // must not deadlock with a real write either, which is what the single
  // statement this replaces did.
  //
  // It was one CTE touching sessions, devices and accounts, so it held three
  // row locks in one transaction. `wipeAccount` holds the same three in the
  // other order: it deletes the devices first and updates the account last.
  // Two transactions taking the same rows in opposite orders is the textbook
  // deadlock, and Postgres resolved it by killing one of them — sometimes the
  // wipe, which is how deleting an account came back as a 500 while one of that
  // account's own sockets happened to be checking in. Seen in CI on
  // 2026-09-07, in `ws_revocation.test.ts`.
  //
  // Three statements instead, each its own transaction, so this holds exactly
  // one row lock at a time and can never be one side of a cycle — whatever
  // order anything else takes. That is a stronger guarantee than agreeing on
  // an order, which would bind every future writer to a rule nothing enforces.
  // The cost is three round trips on a path that nothing waits for.
  //
  // To the hour, and written at most once an hour. Exact to the millisecond on
  // every request, these columns were a timeline of when somebody is awake
  // (`docs/metadata-privacy-review.md`, section 2); nothing Privio shows needs
  // more than the hour. The `<` makes the rest of the hour a no-op, which is
  // also most of the writes this path used to make.
  //
  // Each use moves the session's end out to `SESSION_TTL_DAYS` from now, so a
  // phone in daily use stays signed in, and a token left on a device nobody
  // opens any more stops working on its own. `expires_at` is to the hour as
  // well: to the millisecond, it would give away the very moment of last use
  // that `last_used_at` no longer does.
  const hour = "date_trunc('hour', now(), 'UTC')";
  void (async () => {
    await pool.query(
      `UPDATE sessions
          SET last_used_at = ${hour}, expires_at = ${hour} + make_interval(days => $2)
        WHERE id = $1 AND last_used_at < ${hour}`,
      [row.id, config.SESSION_TTL_DAYS],
    );
    await pool.query(
      `UPDATE devices SET last_seen_at = ${hour} WHERE id = $1 AND last_seen_at < ${hour}`,
      [row.device_id],
    );
    await pool.query(
      `UPDATE accounts SET last_seen_at = ${hour} WHERE id = $1 AND last_seen_at < ${hour}`,
      [row.account_id],
    );
  })().catch(() => {});

  return {
    sessionId: row.id,
    accountId: row.account_id,
    deviceId: row.device_id,
    username: row.username,
  };
}

/** One session that has just ended, and the device it belonged to. */
export interface EndedSession {
  sessionId: string;
  deviceId: string;
}

export async function revokeSession(
  sessionId: string,
  accountId: string,
): Promise<EndedSession | null> {
  // Returning the device rather than a boolean, because the caller has to tell
  // the open socket to close and the socket is identified by its device.
  const { rows } = await pool.query<{ id: string; device_id: string }>(
    `UPDATE sessions SET revoked_at = now()
     WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
     RETURNING id, device_id`,
    [sessionId, accountId],
  );
  const row = rows[0];
  return row ? { sessionId: row.id, deviceId: row.device_id } : null;
}

/** Remote logout: kills every session for the account, optionally sparing the caller's. */
export async function revokeAllSessions(
  accountId: string,
  exceptSessionId?: string,
): Promise<EndedSession[]> {
  const { rows } = await pool.query<{ id: string; device_id: string }>(
    `UPDATE sessions SET revoked_at = now()
     WHERE account_id = $1 AND revoked_at IS NULL AND ($2::uuid IS NULL OR id <> $2)
     RETURNING id, device_id`,
    [accountId, exceptSessionId ?? null],
  );
  return rows.map((row) => ({ sessionId: row.id, deviceId: row.device_id }));
}

/** Every session an account has open, for a revocation that is not per-session. */
export async function liveSessionsFor(accountId: string): Promise<EndedSession[]> {
  const { rows } = await pool.query<{ id: string; device_id: string }>(
    `SELECT id, device_id FROM sessions
     WHERE account_id = $1 AND revoked_at IS NULL AND expires_at > now()`,
    [accountId],
  );
  return rows.map((row) => ({ sessionId: row.id, deviceId: row.device_id }));
}
