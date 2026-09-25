import { pool } from '../db/pool.js';
import { ApiError } from '../util/errors.js';

/**
 * Who is in a group, and whether they may act as an admin.
 *
 * Lifted out of `routes/groups.ts` when a second file needed it — the bot
 * routes, which manage a group's bots and must refuse a member exactly as the
 * group routes refuse one. Two copies of a membership check is how a rule ends
 * up enforced on one route and forgotten on the next.
 *
 * It throws rather than returning a boolean, deliberately: a caller that
 * forgets to look at a returned `false` has written a route with no permission
 * check at all, and nothing about the code would show it.
 */
export async function requireGroupMembership(
  groupId: string,
  accountId: string,
  mustBeAdmin = false,
): Promise<string> {
  const { rows } = await pool.query<{ role: string }>(
    `SELECT m.role FROM group_members m JOIN groups g ON g.id = m.group_id
     WHERE m.group_id = $1 AND m.account_id = $2 AND g.deleted_at IS NULL`,
    [groupId, accountId],
  );
  const role = rows[0]?.role;
  if (!role) throw ApiError.forbidden('not_a_member', 'You are not a member of this group');
  if (mustBeAdmin && role !== 'admin') {
    throw ApiError.forbidden('not_an_admin', 'Admin role required');
  }
  return role;
}
