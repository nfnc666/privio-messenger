import { pool } from '../db/pool.js';

/**
 * What the panel reads.
 *
 * Every query in this file is bounded by the same rule as the schema: it may
 * return what the server already had to know in order to route bytes, plus the
 * plaintext a *public* channel publishes on purpose so it can be found. There
 * is deliberately no function here that reads `envelopes.content`,
 * `backups`, `media_objects`, `channel_posts.content`, `groups.encrypted_metadata`
 * or a private channel's `encrypted_metadata` — not because they are encrypted
 * and would be useless, though they are and it would be, but so that the
 * absence is visible when reading the file rather than argued about later.
 *
 * Counts are the exception that proves it: `queuedEnvelopes` is how many rows
 * are waiting, which is an operational number. It says nothing about any of
 * them.
 */

export interface Overview {
  /**
   * People.
   *
   * Bots are rows in `accounts` too — that is how a bot gets a username, a
   * picture and a chat — but an operator asking "how many accounts" is asking
   * how many *people*, and counting @botcreator among them would inflate every
   * figure on the dashboard by one on a server with no users at all. So the
   * counts below exclude them and [bots] says how many there are, which is the
   * number an operator would actually want next to it.
   */
  accounts: { total: number; active30d: number; new7d: number; deleted: number; bots: number };
  devices: { total: number; ios: number; android: number; desktop: number; web: number };
  channels: { total: number; publicChannels: number; suspended: number };
  licenses: { active: number; revoked: number; unredeemed: number };
  /** Undelivered envelopes and sessions in flight — load, not content. */
  queue: { envelopes: number; liveSessions: number };
  /** Channels carrying at least one report nobody has reviewed. */
  openReports: number;
}

/**
 * The dashboard's top strip, as one round trip.
 *
 * One statement rather than nine because the panel's landing page would
 * otherwise open nine connections every time an operator hits refresh, and
 * because the numbers should be consistent with each other: nine separate
 * queries can show more suspended channels than channels.
 */
export async function overview(): Promise<Overview> {
  const { rows } = await pool.query(`
    SELECT
      (SELECT count(*) FROM accounts WHERE deleted_at IS NULL AND NOT is_bot)          AS accounts_total,
      (SELECT count(*) FROM accounts WHERE deleted_at IS NULL AND NOT is_bot
         AND last_seen_at > now() - interval '30 days')                                AS accounts_active,
      (SELECT count(*) FROM accounts WHERE deleted_at IS NULL AND NOT is_bot
         AND created_at > now() - interval '7 days')                                   AS accounts_new,
      (SELECT count(*) FROM accounts WHERE deleted_at IS NOT NULL AND NOT is_bot)      AS accounts_deleted,
      (SELECT count(*) FROM accounts WHERE deleted_at IS NULL AND is_bot)              AS accounts_bots,
      (SELECT count(*) FROM devices WHERE revoked_at IS NULL)                          AS devices_total,
      (SELECT count(*) FROM devices WHERE revoked_at IS NULL AND platform = 'ios')     AS devices_ios,
      (SELECT count(*) FROM devices WHERE revoked_at IS NULL AND platform = 'android') AS devices_android,
      (SELECT count(*) FROM devices WHERE revoked_at IS NULL AND platform = 'desktop') AS devices_desktop,
      (SELECT count(*) FROM devices WHERE revoked_at IS NULL AND platform = 'web')     AS devices_web,
      (SELECT count(*) FROM channels WHERE deleted_at IS NULL)                         AS channels_total,
      (SELECT count(*) FROM channels WHERE deleted_at IS NULL AND visibility = 'public'
         AND suspended_at IS NULL)                                                     AS channels_public,
      (SELECT count(*) FROM channels WHERE deleted_at IS NULL
         AND suspended_at IS NOT NULL)                                                 AS channels_suspended,
      (SELECT count(*) FROM licenses WHERE status = 'active' AND redeemed_by IS NOT NULL) AS licenses_active,
      (SELECT count(*) FROM licenses WHERE status = 'revoked')                         AS licenses_revoked,
      (SELECT count(*) FROM licenses WHERE status = 'active' AND redeemed_by IS NULL)  AS licenses_unredeemed,
      (SELECT count(*) FROM envelopes)                                                 AS queue_envelopes,
      (SELECT count(*) FROM sessions WHERE revoked_at IS NULL AND expires_at > now())  AS live_sessions,
      (SELECT count(DISTINCT channel_id) FROM channel_reports WHERE reviewed_at IS NULL) AS open_reports
  `);
  const r = rows[0]!;
  const n = (value: unknown) => Number(value ?? 0);
  return {
    accounts: {
      total: n(r.accounts_total),
      active30d: n(r.accounts_active),
      new7d: n(r.accounts_new),
      deleted: n(r.accounts_deleted),
      bots: n(r.accounts_bots),
    },
    devices: {
      total: n(r.devices_total),
      ios: n(r.devices_ios),
      android: n(r.devices_android),
      desktop: n(r.devices_desktop),
      web: n(r.devices_web),
    },
    channels: {
      total: n(r.channels_total),
      publicChannels: n(r.channels_public),
      suspended: n(r.channels_suspended),
    },
    licenses: {
      active: n(r.licenses_active),
      revoked: n(r.licenses_revoked),
      unredeemed: n(r.licenses_unredeemed),
    },
    queue: { envelopes: n(r.queue_envelopes), liveSessions: n(r.live_sessions) },
    openReports: n(r.open_reports),
  };
}

/**
 * Sign-ups per day, for the one chart the panel draws.
 *
 * `generate_series` rather than grouping what exists, so a day with no sign-ups
 * is a zero rather than a missing point — a line chart that silently closes
 * gaps draws a smooth curve over an outage.
 */
export async function signupSeries(days: number): Promise<{ day: string; accounts: number }[]> {
  const { rows } = await pool.query(
    `SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
            count(a.id)::int             AS accounts
     FROM generate_series(
            date_trunc('day', now()) - make_interval(days => $1 - 1),
            date_trunc('day', now()),
            interval '1 day') AS d(day)
     LEFT JOIN accounts a
       ON date_trunc('day', a.created_at) = d.day AND NOT a.is_bot
     GROUP BY d.day
     ORDER BY d.day`,
    [days],
  );
  return rows.map((row) => ({ day: row.day, accounts: row.accounts }));
}

export interface AccountSummary {
  id: string;
  username: string;
  displayName: string | null;
  createdAt: string;
  lastSeenAt: string;
  deletedAt: string | null;
  devices: number;
  licensed: boolean;
  twoFactor: boolean;
}

/**
 * Account lookup.
 *
 * Prefix search on the username only. Not a substring search, and not over
 * display names: a display name is chosen by the person and a `%foo%` over it
 * turns the panel into a directory of everyone whose chosen name contains a
 * word — which is a different product from "find the account this support
 * ticket is about".
 */
export async function findAccounts(query: {
  q?: string;
  limit: number;
  offset: number;
  includeDeleted: boolean;
}): Promise<{ accounts: AccountSummary[]; total: number }> {
  const params = [query.q?.trim().toLowerCase() || null, query.includeDeleted];
  // `NOT is_bot` for the same reason as the counts: this list is people. A bot
  // is reached through its owner, whose account is in this list, and a system
  // account like @botcreator has no owner to reach it through at all.
  const where = `($1::text IS NULL OR a.username LIKE $1 || '%')
                 AND ($2::boolean OR a.deleted_at IS NULL)
                 AND NOT a.is_bot`;

  const [page, count] = await Promise.all([
    pool.query(
      `SELECT a.id, a.username, a.display_name, a.created_at, a.last_seen_at, a.deleted_at,
              a.totp_enabled_at,
              (SELECT count(*) FROM devices d
                WHERE d.account_id = a.id AND d.revoked_at IS NULL)::int AS devices,
              EXISTS (SELECT 1 FROM licenses l
                       WHERE l.redeemed_by = a.id AND l.status = 'active')  AS licensed
       FROM accounts a
       WHERE ${where}
       ORDER BY a.created_at DESC
       LIMIT $3 OFFSET $4`,
      [...params, query.limit, query.offset],
    ),
    pool.query(`SELECT count(*)::int AS total FROM accounts a WHERE ${where}`, params),
  ]);

  return {
    accounts: page.rows.map(toAccountSummary),
    total: count.rows[0]!.total,
  };
}

function toAccountSummary(row: {
  id: string;
  username: string;
  display_name: string | null;
  created_at: Date;
  last_seen_at: Date;
  deleted_at: Date | null;
  totp_enabled_at: Date | null;
  devices: number;
  licensed: boolean;
}): AccountSummary {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    createdAt: row.created_at.toISOString(),
    lastSeenAt: row.last_seen_at.toISOString(),
    deletedAt: row.deleted_at?.toISOString() ?? null,
    devices: row.devices,
    licensed: row.licensed,
    twoFactor: row.totp_enabled_at !== null,
  };
}

export interface AccountDetail extends AccountSummary {
  devicesDetail: {
    id: string;
    name: string;
    platform: string;
    createdAt: string;
    lastSeenAt: string;
    revokedAt: string | null;
    /** Whether a push route is registered. Never the token itself. */
    pushConfigured: boolean;
  }[];
  license: { id: string; source: string; maxDevices: number; redeemedAt: string | null } | null;
  /**
   * Counts only. How many channels somebody owns is a support question; which
   * private ones they are in is not, and is not returned.
   */
  ownedPublicChannels: { id: string; handle: string | null; title: string | null; members: number; suspendedAt: string | null }[];
}

export async function accountDetail(id: string): Promise<AccountDetail | null> {
  const { rows } = await pool.query(
    `SELECT a.id, a.username, a.display_name, a.created_at, a.last_seen_at, a.deleted_at,
            a.totp_enabled_at,
            (SELECT count(*) FROM devices d
              WHERE d.account_id = a.id AND d.revoked_at IS NULL)::int AS devices,
            EXISTS (SELECT 1 FROM licenses l
                     WHERE l.redeemed_by = a.id AND l.status = 'active') AS licensed
     FROM accounts a WHERE a.id = $1`,
    [id],
  );
  if (!rows[0]) return null;

  const [devices, license, channels] = await Promise.all([
    pool.query(
      `SELECT id, name, platform, created_at, last_seen_at, revoked_at,
              (push_token IS NOT NULL) AS push_configured
       FROM devices WHERE account_id = $1 ORDER BY created_at DESC`,
      [id],
    ),
    pool.query(
      `SELECT id, source, max_devices, redeemed_at FROM licenses
       WHERE redeemed_by = $1 AND status = 'active'`,
      [id],
    ),
    // Public channels only. A private channel this account owns is not named
    // here: its title is sealed, and listing the id alone would tell an
    // operator a private channel exists and who owns it, which is the metadata
    // the private visibility exists to withhold.
    pool.query(
      `SELECT id, handle, title, member_count, suspended_at FROM channels
       WHERE owner_account_id = $1 AND visibility = 'public' AND deleted_at IS NULL
       ORDER BY member_count DESC`,
      [id],
    ),
  ]);

  return {
    ...toAccountSummary(rows[0]),
    devicesDetail: devices.rows.map((d) => ({
      id: d.id,
      name: d.name,
      platform: d.platform,
      createdAt: d.created_at.toISOString(),
      lastSeenAt: d.last_seen_at.toISOString(),
      revokedAt: d.revoked_at?.toISOString() ?? null,
      pushConfigured: d.push_configured,
    })),
    license: license.rows[0]
      ? {
          id: license.rows[0].id,
          source: license.rows[0].source,
          maxDevices: license.rows[0].max_devices,
          redeemedAt: license.rows[0].redeemed_at?.toISOString() ?? null,
        }
      : null,
    ownedPublicChannels: channels.rows.map((c) => ({
      id: c.id,
      handle: c.handle,
      title: c.title,
      members: c.member_count,
      suspendedAt: c.suspended_at?.toISOString() ?? null,
    })),
  };
}

export interface LicenseSummary {
  id: string;
  status: string;
  source: string;
  maxDevices: number;
  paymentProvider: string | null;
  paymentReference: string | null;
  redeemedBy: { id: string; username: string } | null;
  redeemedAt: string | null;
  createdAt: string;
}

/**
 * Licences, without keys.
 *
 * `key_hash` is not selected and there is no route that returns it. The key was
 * shown once, at issue, to the website that paid for it; the panel can tell you
 * a licence exists, who holds it and whether it is live, and it cannot tell you
 * what to type into an app. That is the difference between an operator tool and
 * a key generator.
 */
export async function findLicenses(query: {
  status?: 'active' | 'revoked';
  redeemed?: boolean;
  q?: string;
  limit: number;
  offset: number;
}): Promise<{ licenses: LicenseSummary[]; total: number }> {
  const params = [
    query.status ?? null,
    query.redeemed === undefined ? null : query.redeemed,
    query.q?.trim() || null,
  ];
  const where = `($1::text IS NULL OR l.status = $1)
                 AND ($2::boolean IS NULL OR (l.redeemed_by IS NOT NULL) = $2)
                 AND ($3::text IS NULL OR l.payment_reference = $3 OR a.username = lower($3))`;

  const [page, count] = await Promise.all([
    pool.query(
      `SELECT l.id, l.status, l.source, l.max_devices, l.payment_provider, l.payment_reference,
              l.redeemed_at, l.created_at, a.id AS account_id, a.username
       FROM licenses l LEFT JOIN accounts a ON a.id = l.redeemed_by
       WHERE ${where}
       ORDER BY l.created_at DESC
       LIMIT $4 OFFSET $5`,
      [...params, query.limit, query.offset],
    ),
    pool.query(
      `SELECT count(*)::int AS total FROM licenses l LEFT JOIN accounts a ON a.id = l.redeemed_by
       WHERE ${where}`,
      params,
    ),
  ]);

  return {
    licenses: page.rows.map((row) => ({
      id: row.id,
      status: row.status,
      source: row.source,
      maxDevices: row.max_devices,
      paymentProvider: row.payment_provider,
      paymentReference: row.payment_reference,
      redeemedBy: row.account_id ? { id: row.account_id, username: row.username } : null,
      redeemedAt: row.redeemed_at?.toISOString() ?? null,
      createdAt: row.created_at.toISOString(),
    })),
    total: count.rows[0]!.total,
  };
}

export interface ReportedChannel {
  channelId: string;
  /** Public channels only; null for a private one, which is the whole point. */
  handle: string | null;
  title: string | null;
  description: string | null;
  category: string | null;
  visibility: 'public' | 'private';
  members: number;
  createdAt: string;
  suspendedAt: string | null;
  suspendedReason: string | null;
  owner: { id: string; username: string } | null;
  reports: { total: number; open: number; reasons: Record<string, number>; firstAt: string; lastAt: string };
}

/**
 * The moderation queue.
 *
 * Grouped by channel rather than listed per report, because the decision is
 * about the channel: ten reports are one thing to look at, not ten. The reasons
 * come back as counts per reason, which is the most a fixed enum can tell you
 * and exactly as much as the report table was designed to hold.
 *
 * What an operator sees for a *private* channel is: an id, a member count, and
 * how many people reported it, with what reasons. Not the title, because it is
 * sealed. That screen is meant to feel thin — it is honest about a report being
 * a signal rather than evidence, and `022_channel_ownership_and_reports.sql`
 * says why promising more would mean not encrypting the posts.
 */
export async function reportedChannels(query: {
  open: boolean;
  limit: number;
  offset: number;
}): Promise<{ channels: ReportedChannel[]; total: number }> {
  const having = query.open ? 'HAVING count(*) FILTER (WHERE r.reviewed_at IS NULL) > 0' : '';

  const [page, count] = await Promise.all([
    pool.query(
      `SELECT c.id, c.handle, c.title, c.description, c.category, c.visibility,
              c.member_count, c.created_at, c.suspended_at, c.suspended_reason,
              a.id AS owner_id, a.username AS owner_username,
              count(*)::int                                            AS reports_total,
              count(*) FILTER (WHERE r.reviewed_at IS NULL)::int        AS reports_open,
              min(r.reported_at)                                        AS first_at,
              max(r.reported_at)                                        AS last_at,
              (SELECT jsonb_object_agg(reason, n) FROM (
                 SELECT reason, count(*)::int AS n FROM channel_reports
                 WHERE channel_id = c.id GROUP BY reason) AS byreason)  AS reasons
       FROM channel_reports r
       JOIN channels c ON c.id = r.channel_id AND c.deleted_at IS NULL
       LEFT JOIN accounts a ON a.id = c.owner_account_id AND a.deleted_at IS NULL
       GROUP BY c.id, a.id, a.username
       ${having}
       ORDER BY count(*) FILTER (WHERE r.reviewed_at IS NULL) DESC, max(r.reported_at) DESC
       LIMIT $1 OFFSET $2`,
      [query.limit, query.offset],
    ),
    pool.query(
      `SELECT count(*)::int AS total FROM (
         SELECT c.id FROM channel_reports r
         JOIN channels c ON c.id = r.channel_id AND c.deleted_at IS NULL
         GROUP BY c.id ${having}) AS q`,
    ),
  ]);

  return {
    channels: page.rows.map((row) => ({
      channelId: row.id,
      // Belt and braces: a private channel has no handle or title by schema, but
      // the mapping states it rather than relying on that staying true.
      handle: row.visibility === 'public' ? row.handle : null,
      title: row.visibility === 'public' ? row.title : null,
      description: row.visibility === 'public' ? row.description : null,
      category: row.visibility === 'public' ? row.category : null,
      visibility: row.visibility,
      members: row.member_count,
      createdAt: row.created_at.toISOString(),
      suspendedAt: row.suspended_at?.toISOString() ?? null,
      suspendedReason: row.suspended_reason,
      owner: row.owner_id ? { id: row.owner_id, username: row.owner_username } : null,
      reports: {
        total: row.reports_total,
        open: row.reports_open,
        reasons: row.reasons ?? {},
        firstAt: row.first_at.toISOString(),
        lastAt: row.last_at.toISOString(),
      },
    })),
    total: count.rows[0]!.total,
  };
}

export interface ReportedAccount {
  accountId: string;
  username: string;
  displayName: string | null;
  createdAt: string;
  reports: { total: number; open: number; reasons: Record<string, number>; firstAt: string; lastAt: string };
}

/**
 * The moderation queue for people, beside the one for channels.
 *
 * Thinner than `reportedChannels`, and unavoidably so: a channel has a public
 * title and description a reviewer can read, and an account has a username and
 * nothing else the server may look at. There is no message history here to
 * quote, because the server never held one in the clear — see
 * `033_account_reports.sql`. What this answers is how many people reported
 * somebody and on what grounds, which is a signal, not evidence, and is worth
 * showing only as long as nobody mistakes it for the second thing.
 *
 * Deliberately no suspend action to go with it. Suspending a channel removes
 * something the server controls — a listing, a handle, an invite code.
 * Suspending a *person* in an end-to-end encrypted messenger would need a
 * decision about what happens to conversations it cannot read, and that is a
 * design question, not a query.
 */
export async function reportedAccounts(query: {
  open: boolean;
  limit: number;
  offset: number;
}): Promise<{ accounts: ReportedAccount[]; total: number }> {
  const having = query.open ? 'HAVING count(*) FILTER (WHERE r.reviewed_at IS NULL) > 0' : '';

  const [page, count] = await Promise.all([
    pool.query(
      `SELECT a.id, a.username, a.display_name, a.created_at,
              count(*)::int                                      AS reports_total,
              count(*) FILTER (WHERE r.reviewed_at IS NULL)::int  AS reports_open,
              min(r.reported_at)                                  AS first_at,
              max(r.reported_at)                                  AS last_at,
              (SELECT jsonb_object_agg(reason, n) FROM (
                 SELECT reason, count(*)::int AS n FROM account_reports
                 WHERE account_id = a.id GROUP BY reason) AS byreason) AS reasons
       FROM account_reports r
       JOIN accounts a ON a.id = r.account_id AND a.deleted_at IS NULL
       GROUP BY a.id
       ${having}
       ORDER BY count(*) FILTER (WHERE r.reviewed_at IS NULL) DESC, max(r.reported_at) DESC
       LIMIT $1 OFFSET $2`,
      [query.limit, query.offset],
    ),
    pool.query(
      `SELECT count(*)::int AS total FROM (
         SELECT a.id FROM account_reports r
         JOIN accounts a ON a.id = r.account_id AND a.deleted_at IS NULL
         GROUP BY a.id ${having}) AS q`,
    ),
  ]);

  return {
    accounts: page.rows.map((row) => ({
      accountId: row.id,
      username: row.username,
      displayName: row.display_name,
      createdAt: row.created_at.toISOString(),
      reports: {
        total: row.reports_total,
        open: row.reports_open,
        reasons: row.reasons ?? {},
        firstAt: row.first_at.toISOString(),
        lastAt: row.last_at.toISOString(),
      },
    })),
    total: count.rows[0]!.total,
  };
}

export interface ChannelRow {
  id: string;
  visibility: 'public' | 'private';
  handle: string | null;
  title: string | null;
  suspendedAt: Date | null;
}

export async function channelForModeration(id: string): Promise<ChannelRow | null> {
  const { rows } = await pool.query(
    `SELECT id, visibility, handle, title, suspended_at FROM channels
     WHERE id = $1 AND deleted_at IS NULL`,
    [id],
  );
  const row = rows[0];
  return row
    ? {
        id: row.id,
        visibility: row.visibility,
        handle: row.handle,
        title: row.title,
        suspendedAt: row.suspended_at,
      }
    : null;
}

/** Takes a public channel out of discovery. Returns false when it was already out. */
export async function suspendChannel(id: string, reason: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE channels SET suspended_at = now(), suspended_reason = $2
     WHERE id = $1 AND deleted_at IS NULL AND suspended_at IS NULL`,
    [id, reason],
  );
  return (rowCount ?? 0) > 0;
}

export async function reinstateChannel(id: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE channels SET suspended_at = NULL, suspended_reason = NULL
     WHERE id = $1 AND deleted_at IS NULL AND suspended_at IS NOT NULL`,
    [id],
  );
  return (rowCount ?? 0) > 0;
}

/** Closes every standing report on a channel. Returns how many were open. */
export async function reviewReports(channelId: string, adminId: string): Promise<number> {
  const { rowCount } = await pool.query(
    `UPDATE channel_reports SET reviewed_at = now(), reviewed_by = $2
     WHERE channel_id = $1 AND reviewed_at IS NULL`,
    [channelId, adminId],
  );
  return rowCount ?? 0;
}

export interface OperatorSummary {
  id: string;
  username: string;
  displayName: string | null;
  role: string;
  twoFactor: boolean;
  createdAt: string;
  lastLoginAt: string | null;
  disabledAt: string | null;
}

export async function listOperators(): Promise<OperatorSummary[]> {
  const { rows } = await pool.query(
    `SELECT id, username, display_name, role, totp_enabled_at, created_at, last_login_at, disabled_at
     FROM admin_users ORDER BY disabled_at NULLS FIRST, username`,
  );
  return rows.map((row) => ({
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    role: row.role,
    twoFactor: row.totp_enabled_at !== null,
    createdAt: row.created_at.toISOString(),
    lastLoginAt: row.last_login_at?.toISOString() ?? null,
    disabledAt: row.disabled_at?.toISOString() ?? null,
  }));
}
