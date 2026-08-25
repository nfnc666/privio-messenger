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

export async function createSession(
  accountId: string,
  deviceId: string,
  userAgent?: string,
): Promise<IssuedSession> {
  const token = generateToken();
  const expiresAt = new Date(Date.now() + config.SESSION_TTL_DAYS * 86_400_000);
  const { rows } = await pool.query<{ id: string }>(
    `INSERT INTO sessions (account_id, device_id, token_hash, user_agent, expires_at)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [accountId, deviceId, tokenHash(token), userAgent ?? null, expiresAt],
  );
  return { token, expiresAt, sessionId: rows[0]!.id };
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

  // Presence bookkeeping is best-effort and must not block the request.
  void pool
    .query(
      `WITH s AS (UPDATE sessions SET last_used_at = now() WHERE id = $1),
            d AS (UPDATE devices SET last_seen_at = now() WHERE id = $2)
       UPDATE accounts SET last_seen_at = now() WHERE id = $3`,
      [row.id, row.device_id, row.account_id],
    )
    .catch(() => {});

  return {
    sessionId: row.id,
    accountId: row.account_id,
    deviceId: row.device_id,
    username: row.username,
  };
}

export async function revokeSession(sessionId: string, accountId: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    'UPDATE sessions SET revoked_at = now() WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL',
    [sessionId, accountId],
  );
  return (rowCount ?? 0) > 0;
}

/** Remote logout: kills every session for the account, optionally sparing the caller's. */
export async function revokeAllSessions(accountId: string, exceptSessionId?: string): Promise<number> {
  const { rowCount } = await pool.query(
    `UPDATE sessions SET revoked_at = now()
     WHERE account_id = $1 AND revoked_at IS NULL AND ($2::uuid IS NULL OR id <> $2)`,
    [accountId, exceptSessionId ?? null],
  );
  return rowCount ?? 0;
}
