import { pool } from '../db/pool.js';
import type { AdminContext } from './admin_auth.js';

/**
 * The only writer to `admin_audit_log`.
 *
 * One writer so there is one place to check the rule that makes the table safe
 * to keep: **nothing written here may come from user content.** Not a message,
 * not a post, not a backup, not a private channel's metadata, not a display
 * name typed by somebody who is about to be moderated. A log full of what the
 * server promised not to read would undo the promise more thoroughly than any
 * route, because it would do it permanently and in a table built never to be
 * deleted from.
 *
 * What may go in `detail`: identifiers the server already holds, enum values
 * from a fixed set, counts, and field names. `sanitiseDetail` is the backstop
 * rather than the policy — the policy is what callers pass.
 */

/** Actions, spelled once so a typo is a compile error rather than a gap in the log. */
export type AuditAction =
  | 'admin.login'
  | 'admin.login_failed'
  | 'admin.logout'
  | 'operator.create'
  | 'operator.disable'
  | 'operator.enable'
  | 'operator.role_change'
  | 'license.issue'
  | 'license.revoke'
  | 'report.review'
  | 'channel.suspend'
  | 'channel.reinstate'
  // Which channel carries the verification badge. Audited because it is the one
  // setting in the product that makes a claim *about* a channel to everybody
  // who sees it, and "who moved the badge, and when" has to be answerable.
  | 'official_channel.designate'
  | 'official_channel.clear';

export interface AuditEntry {
  action: AuditAction;
  targetType?: 'account' | 'channel' | 'license' | 'operator' | 'order';
  targetId?: string;
  detail?: Record<string, unknown>;
  ip?: string;
}

/**
 * Values small and simple enough to be certain they are not content.
 *
 * Strings are capped at 128 characters and objects are not walked: a nested
 * object is where a whole request body ends up when somebody passes `body`
 * instead of `{ reason: body.reason }`, and the cap is what stops a long free
 * text field from being logged in full if one is ever added upstream.
 */
function sanitiseDetail(detail: Record<string, unknown>): Record<string, unknown> {
  const safe: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(detail)) {
    if (value === null || value === undefined) continue;
    if (typeof value === 'string') safe[key] = value.slice(0, 128);
    else if (typeof value === 'number' || typeof value === 'boolean') safe[key] = value;
    else if (Array.isArray(value)) safe[key] = value.length;
    // Anything else — objects, dates, buffers — is dropped rather than
    // stringified. A dropped field is a gap somebody notices; a stringified one
    // is a leak nobody does.
  }
  return safe;
}

/**
 * Records an operator action.
 *
 * Never throws: an action that succeeded must not be reported as failed because
 * the log write lost a race with a connection drop. The failure is logged to
 * the process log instead, which is where an operator watching the server would
 * see that the audit trail has a hole. It is deliberately *not* wrapped into
 * the action's transaction — a moderation decision that is rolled back because
 * the log insert failed is the worse outcome, and the panel's writes are
 * individually idempotent enough to retry.
 */
export async function audit(
  actor: Pick<AdminContext, 'adminId' | 'username'>,
  entry: AuditEntry,
  onError?: (err: unknown) => void,
): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO admin_audit_log
         (admin_user_id, actor_username, action, target_type, target_id, detail, ip)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        actor.adminId,
        actor.username,
        entry.action,
        entry.targetType ?? null,
        entry.targetId ?? null,
        JSON.stringify(sanitiseDetail(entry.detail ?? {})),
        entry.ip ?? null,
      ],
    );
  } catch (err) {
    onError?.(err);
  }
}

/**
 * A failed sign-in, which has no actor row to attribute to.
 *
 * Logged with the username as it was typed, capped, and nothing else. Not the
 * password, not a hash of it, not a "was the username real" flag — that last
 * one would turn the audit log into the account-enumeration oracle the login
 * itself was carefully built not to be.
 */
export async function auditFailedLogin(
  username: string,
  ip: string | undefined,
  onError?: (err: unknown) => void,
): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO admin_audit_log (admin_user_id, actor_username, action, detail, ip)
       VALUES (NULL, $1, 'admin.login_failed', '{}'::jsonb, $2)`,
      [username.slice(0, 64), ip ?? null],
    );
  } catch (err) {
    onError?.(err);
  }
}

export interface AuditRow {
  id: number;
  actorUsername: string;
  adminUserId: string | null;
  action: string;
  targetType: string | null;
  targetId: string | null;
  detail: Record<string, unknown>;
  ip: string | null;
  at: string;
}

/** The log, newest first, optionally narrowed to one action or one target. */
export async function readAuditLog(query: {
  limit: number;
  before?: number;
  action?: string;
  targetId?: string;
}): Promise<AuditRow[]> {
  const { rows } = await pool.query(
    `SELECT id, admin_user_id, actor_username, action, target_type, target_id, detail, ip::text AS ip, at
     FROM admin_audit_log
     WHERE ($1::bigint IS NULL OR id < $1)
       AND ($2::text IS NULL OR action = $2)
       AND ($3::text IS NULL OR target_id = $3)
     ORDER BY id DESC
     LIMIT $4`,
    [query.before ?? null, query.action ?? null, query.targetId ?? null, query.limit],
  );
  return rows.map((row) => ({
    id: row.id,
    adminUserId: row.admin_user_id,
    actorUsername: row.actor_username,
    action: row.action,
    targetType: row.target_type,
    targetId: row.target_id,
    detail: row.detail,
    ip: row.ip,
    at: row.at.toISOString(),
  }));
}
