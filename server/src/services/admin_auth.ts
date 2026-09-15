import { authenticator } from 'otplib';
import { config } from '../config.js';
import { pool } from '../db/pool.js';
import { generateToken, hashSecret, tokenHash, verifySecret } from '../util/crypto.js';
import { openSecret } from './totp.js';

/**
 * Operator authentication.
 *
 * Separate from `services/sessions.ts` on purpose, and not a role flag on an
 * account: an operator login is the one credential that sees across accounts,
 * so it is stored apart, expires in hours rather than a year, and is revoked
 * without touching whatever Privio account the same person happens to use. See
 * migration 027 for the rest of that argument.
 */

export const ADMIN_ROLES = ['owner', 'admin', 'support', 'viewer'] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];

export interface AdminContext {
  sessionId: string;
  adminId: string;
  username: string;
  role: AdminRole;
}

export interface AdminUserRow {
  id: string;
  username: string;
  display_name: string | null;
  password_hash: string;
  totp_secret: string | null;
  totp_enabled_at: Date | null;
  role: AdminRole;
  created_at: Date;
  last_login_at: Date | null;
  disabled_at: Date | null;
}

/**
 * Why a sign-in did not work, for the caller to turn into a response.
 *
 * `bad_credentials` covers a wrong username, a wrong password and a disabled
 * operator alike — the three are indistinguishable from outside, which is the
 * point: an attacker with a list of names must not learn which of them are
 * real. `totp_required` is separate because it is not a failure, it is the
 * second half of a login that is going fine.
 */
export type AdminLoginFailure = 'bad_credentials' | 'totp_required' | 'invalid_totp';

export type AdminLoginResult =
  | { ok: true; token: string; expiresAt: Date; admin: AdminContext }
  | { ok: false; reason: AdminLoginFailure };

/**
 * A dummy Argon2 hash, verified against when no operator matched.
 *
 * Without it, an unknown username returns in microseconds while a known one
 * takes the ~50ms Argon2 costs, and the difference enumerates the operator
 * table over a coffee break. Generated once at module load rather than written
 * as a constant so that it is a real hash of a real random string, with the
 * same parameters the live rows use — a stale hardcoded digest would drift from
 * the parameters and start costing a different amount of time.
 */
const decoyHash = hashSecret(generateToken());

export async function findAdminByUsername(username: string): Promise<AdminUserRow | null> {
  const { rows } = await pool.query<AdminUserRow>(
    'SELECT * FROM admin_users WHERE username = $1',
    [username.trim().toLowerCase()],
  );
  return rows[0] ?? null;
}

export async function adminById(id: string): Promise<AdminUserRow | null> {
  const { rows } = await pool.query<AdminUserRow>('SELECT * FROM admin_users WHERE id = $1', [id]);
  return rows[0] ?? null;
}

/**
 * Username, password, and a TOTP code when the operator has enrolled.
 *
 * Two-factor is not optional in practice — `create-admin` enrols it and the
 * panel nags until it is on — but it is enforced per row rather than globally
 * so that the very first operator can be created and then immediately enrol,
 * which is impossible if the login refuses everyone without a factor they have
 * no way to set up yet.
 */
export async function login(
  username: string,
  password: string,
  totpCode: string | undefined,
  context: { ip?: string; userAgent?: string } = {},
): Promise<AdminLoginResult> {
  const admin = await findAdminByUsername(username);

  if (!admin || admin.disabled_at !== null) {
    // Spend the same time as a real verification before failing. `void` on the
    // result: what matters is that the work happened, not what it said.
    await verifySecret(await decoyHash, password);
    return { ok: false, reason: 'bad_credentials' };
  }

  if (!(await verifySecret(admin.password_hash, password))) {
    return { ok: false, reason: 'bad_credentials' };
  }

  if (admin.totp_enabled_at && admin.totp_secret) {
    if (!totpCode) return { ok: false, reason: 'totp_required' };
    const secret = openSecret(admin.totp_secret);
    // A secret that will not open is a wrong or rotated TOTP_SECRET_KEY, not a
    // wrong code. Refusing is still right — the factor cannot be checked, so it
    // has not been met.
    if (secret === null || !authenticator.check(totpCode, secret)) {
      return { ok: false, reason: 'invalid_totp' };
    }
  }

  const token = generateToken();
  const expiresAt = new Date(Date.now() + config.ADMIN_SESSION_TTL_MINUTES * 60_000);
  const { rows } = await pool.query<{ id: string }>(
    `INSERT INTO admin_sessions (admin_user_id, token_hash, ip, user_agent, expires_at)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [admin.id, tokenHash(token), context.ip ?? null, context.userAgent ?? null, expiresAt],
  );
  await pool.query('UPDATE admin_users SET last_login_at = now() WHERE id = $1', [admin.id]);

  return {
    ok: true,
    token,
    expiresAt,
    admin: {
      sessionId: rows[0]!.id,
      adminId: admin.id,
      username: admin.username,
      role: admin.role,
    },
  };
}

/** Resolves an operator bearer token, or null when it is invalid, expired, revoked or disabled. */
export async function resolveAdminSession(token: string): Promise<AdminContext | null> {
  const { rows } = await pool.query<{
    id: string;
    admin_user_id: string;
    username: string;
    role: AdminRole;
  }>(
    `SELECT s.id, s.admin_user_id, u.username, u.role
     FROM admin_sessions s
     JOIN admin_users u ON u.id = s.admin_user_id
     WHERE s.token_hash = $1
       AND s.revoked_at IS NULL AND s.expires_at > now()
       AND u.disabled_at IS NULL`,
    [tokenHash(token)],
  );
  const row = rows[0];
  if (!row) return null;

  // Best-effort, and one statement holding one row lock — same reasoning as the
  // account session path, which deadlocked when it took three at once.
  void pool
    .query('UPDATE admin_sessions SET last_used_at = now() WHERE id = $1', [row.id])
    .catch(() => {});

  return {
    sessionId: row.id,
    adminId: row.admin_user_id,
    username: row.username,
    role: row.role,
  };
}

export async function revokeAdminSession(sessionId: string): Promise<void> {
  await pool.query(
    'UPDATE admin_sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL',
    [sessionId],
  );
}

/**
 * Ends every session an operator holds.
 *
 * Called when they are disabled or their role changes. A role carried in a live
 * session would otherwise outlive the demotion by up to the session TTL, which
 * is exactly the window somebody being removed would use.
 */
export async function revokeAllAdminSessions(adminId: string): Promise<number> {
  const { rowCount } = await pool.query(
    'UPDATE admin_sessions SET revoked_at = now() WHERE admin_user_id = $1 AND revoked_at IS NULL',
    [adminId],
  );
  return rowCount ?? 0;
}

/**
 * What each role may do.
 *
 * Capabilities rather than a rank, because the roles are not a straight line:
 * support issues licences but must not suspend a channel, while an admin
 * moderates but must not create operators. A ranked check would have to decide
 * which of those two is "higher" and would be wrong for one of them.
 */
export const CAPABILITIES = {
  /** Read anything the panel shows. */
  read: ['owner', 'admin', 'support', 'viewer'],
  /** Issue and revoke licences. */
  licenses: ['owner', 'admin', 'support'],
  /** Suspend and reinstate public channels, review reports. */
  moderate: ['owner', 'admin'],
  /** Create, disable and re-role operators. */
  operators: ['owner'],
} as const satisfies Record<string, readonly AdminRole[]>;

export type Capability = keyof typeof CAPABILITIES;

export function can(role: AdminRole, capability: Capability): boolean {
  return (CAPABILITIES[capability] as readonly AdminRole[]).includes(role);
}

/** Creates an operator. Used by the bootstrap CLI and by `POST /v1/admin/operators`. */
export async function createAdminUser(input: {
  username: string;
  password: string;
  role: AdminRole;
  displayName?: string;
  createdBy?: string;
}): Promise<AdminUserRow> {
  const { rows } = await pool.query<AdminUserRow>(
    `INSERT INTO admin_users (username, display_name, password_hash, role, created_by)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [
      input.username.trim().toLowerCase(),
      input.displayName?.trim() || null,
      await hashSecret(input.password),
      input.role,
      input.createdBy ?? null,
    ],
  );
  return rows[0]!;
}

/** True when nobody can sign in yet, which is what the bootstrap CLI is for. */
export async function hasAnyAdmin(): Promise<boolean> {
  const { rows } = await pool.query<{ exists: boolean }>(
    'SELECT EXISTS (SELECT 1 FROM admin_users WHERE disabled_at IS NULL) AS exists',
  );
  return rows[0]!.exists;
}
