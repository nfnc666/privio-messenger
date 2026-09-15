import { pool, type Pool, type PoolClient } from '../db/pool.js';

/**
 * The official Privio channel.
 *
 * **The badge is a uuid, never a name.** That is the whole point of this file
 * and it is worth being blunt about: handles can be imitated. `privio_official`
 * and `privio_officia1` are one character apart, and a verification mark that
 * followed a *name* would decorate the second one for anybody who registered it
 * first. So the designated channel is stored as its immutable id, every check
 * below compares ids, and the handle is kept only as evidence of what was
 * designated — nothing reads it to decide anything.
 *
 * The id is also not configuration. An environment variable would put the
 * decision somewhere a deployment could get wrong silently, and somewhere a
 * restart could change; the row records who set it and when, and setting it
 * goes through an operator route that has to *find* the channel and confirm its
 * owner first.
 */

export interface OfficialChannel {
  channelId: string;
  designatedHandle: string;
  designatedOwner: string;
  setAt: Date;
  setBy: string | null;
}

/**
 * The designated channel, cached.
 *
 * Read on nearly every channel response — a list of forty channels asks forty
 * times — and it changes approximately never, so it is held in memory and
 * refreshed when it is written. A deployment running several processes sees a
 * change after each has been through [refresh], which for a value that is set
 * once in the product's life is the right trade; `docs/official-channel.md`
 * says so rather than leaving it to be discovered.
 *
 * `undefined` means "not looked up yet", `null` means "looked up, none set".
 * The difference matters: treating an unloaded cache as "none" would answer
 * `verified: false` for the official channel itself during start-up.
 */
let cached: OfficialChannel | null | undefined;

/** Reads the row and updates the cache. Called at boot and after any change. */
export async function refresh(db: Pool | PoolClient = pool): Promise<OfficialChannel | null> {
  const { rows } = await db.query<{
    channel_id: string;
    designated_handle: string;
    designated_owner: string;
    set_at: Date;
    set_by: string | null;
  }>('SELECT * FROM official_channel WHERE singleton');
  const row = rows[0];
  cached = row
    ? {
        channelId: row.channel_id,
        designatedHandle: row.designated_handle,
        designatedOwner: row.designated_owner,
        setAt: row.set_at,
        setBy: row.set_by,
      }
    : null;
  return cached;
}

/** The designated channel, or null. Loads on first use. */
export async function current(): Promise<OfficialChannel | null> {
  return cached === undefined ? refresh() : cached;
}

/**
 * Whether this id is the official channel — synchronously.
 *
 * Synchronous because it is asked inside a response serialiser, which cannot
 * await. Answers `false` before the cache is loaded, which is why [refresh] is
 * awaited at start-up rather than left to the first request.
 */
export function isOfficial(channelId: unknown): boolean {
  return cached != null && typeof channelId === 'string' && channelId === cached.channelId;
}

/** Forgets the cache. For tests, which truncate the table between cases. */
export function forgetCache(): void {
  cached = undefined;
}

/**
 * Designates a channel, by id.
 *
 * Takes the id and the two things the operator confirmed about it, and stores
 * all three. The confirmation happens at the route, where the channel is looked
 * up and its owner shown; this function is the write.
 */
export async function designate(
  channelId: string,
  handle: string,
  ownerAccountId: string,
  setBy: string | null,
): Promise<OfficialChannel | null> {
  await pool.query(
    `INSERT INTO official_channel (singleton, channel_id, designated_handle, designated_owner, set_by)
     VALUES (true, $1, $2, $3, $4)
     ON CONFLICT (singleton) DO UPDATE
       SET channel_id = EXCLUDED.channel_id,
           designated_handle = EXCLUDED.designated_handle,
           designated_owner = EXCLUDED.designated_owner,
           set_at = now(),
           set_by = EXCLUDED.set_by`,
    [channelId, handle, ownerAccountId, setBy],
  );
  return refresh();
}

/** Removes the designation. The channel itself is untouched. */
export async function clear(): Promise<void> {
  await pool.query('DELETE FROM official_channel WHERE singleton');
  await refresh();
}

/**
 * Subscribes an account to the official channel, once in its life.
 *
 * Four things this deliberately does **not** do:
 *
 * - **It does not run twice.** The offer row is the record, and it is written
 *   whether or not a membership was created. Somebody who leaves is not
 *   re-added on their next sign-in, which is the difference between a channel
 *   you can remove and one that keeps coming back.
 * - **It does not touch an existing membership.** `ON CONFLICT DO NOTHING`, so
 *   the channel's owner and its admins keep the role and the permissions they
 *   have. An auto-subscribe that overwrote a row would demote the operator of
 *   the channel to a subscriber of it.
 * - **It does not grant anything.** The role is `subscriber` and the
 *   permission columns are left at their defaults, which are all false.
 * - **It does not rotate the key epoch.** Joining a channel never has; this is
 *   a join.
 *
 * Returns whether a membership was actually created, which is what the tests
 * assert against.
 */
export async function ensureSubscribed(accountId: string): Promise<boolean> {
  const official = await current();
  if (!official) return false;

  // The offer row is the guard, and it is claimed first: two sign-ins racing on
  // the same account both reach here, and only the one that inserts the row
  // goes on to subscribe.
  const { rowCount: claimed } = await pool.query(
    `INSERT INTO official_channel_offers (account_id, channel_id)
     VALUES ($1, $2) ON CONFLICT (account_id, channel_id) DO NOTHING`,
    [accountId, official.channelId],
  );
  if (claimed !== 1) return false;

  const { rowCount: joined } = await pool.query(
    `INSERT INTO channel_members (channel_id, account_id, role)
     SELECT $2, $1, 'subscriber'
       FROM channels c
      WHERE c.id = $2 AND c.deleted_at IS NULL
     ON CONFLICT (channel_id, account_id) DO NOTHING`,
    [accountId, official.channelId],
  );

  if (joined === 1) {
    await pool.query('UPDATE channels SET member_count = member_count + 1 WHERE id = $1', [
      official.channelId,
    ]);
  }
  return joined === 1;
}

/**
 * Records that somebody left the official channel on purpose.
 *
 * Called from the ordinary leave route. It does not stop the re-add — the offer
 * row already does that — but "left deliberately" and "was offered and stayed"
 * are different facts, and a support question about a missing channel is
 * answered by which one it is.
 */
export async function noteLeft(accountId: string, channelId: string): Promise<void> {
  if (!isOfficial(channelId)) return;
  await pool.query(
    `UPDATE official_channel_offers SET opted_out_at = now()
      WHERE account_id = $1 AND channel_id = $2 AND opted_out_at IS NULL`,
    [accountId, channelId],
  );
}

/** Records a voluntary return, so the stored fact matches what is true. */
export async function noteRejoined(accountId: string, channelId: string): Promise<void> {
  if (!isOfficial(channelId)) return;
  await pool.query(
    `INSERT INTO official_channel_offers (account_id, channel_id, opted_out_at)
     VALUES ($1, $2, NULL)
     ON CONFLICT (account_id, channel_id) DO UPDATE SET opted_out_at = NULL`,
    [accountId, channelId],
  );
}
