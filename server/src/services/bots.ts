import { createHash, timingSafeEqual } from 'node:crypto';
import { pool } from '../db/pool.js';
import { generateToken } from '../util/crypto.js';

/**
 * Bots: accounts somebody else operates over HTTP.
 *
 * The boundary this module keeps, and the reason it is worth stating twice:
 * **nothing here touches `envelopes`.** A bot conversation is plaintext in
 * `bot_messages`, readable by the operator and by this server, because a
 * program reached over HTTP cannot hold Signal keys without this server holding
 * them for it — which is the one thing the design exists to prevent. Keeping
 * the two in separate tables is what stops bot chats becoming a quietly weaker
 * case of ordinary ones. See `docs/bots.md`.
 */

export interface BotRow {
  account_id: string;
  owner_account_id: string;
  description: string | null;
  commands: BotCommand[];
  disabled_at: Date | null;
  created_at: Date;
}

export interface BotCommand {
  command: string;
  description: string;
}

/** How many bots one account may own, and how fast a bot may send. */
export const BOT_LIMITS = {
  perOwner: 20,
  /** Messages per minute, per bot, across every conversation. */
  sendsPerMinute: 30,
  /** The longest a `getUpdates` call will wait before answering empty. */
  maxPollSeconds: 30,
} as const;

/**
 * Long-poll clients may open more than one request by mistake (or on purpose).
 * Without a shared gate each request used to execute one database query every
 * second, so N concurrent polls meant N queries/second for one bot. Keep the
 * database work bounded per bot regardless of how many HTTP requests are open.
 *
 * This is deliberately process-local: it protects the database from connection
 * fan-out on each server instance without adding durable tracking of a bot's
 * polling behaviour. Horizontal deployments therefore get at most one query
 * per interval per instance, still a strict bound instead of per connection.
 */
const POLL_DB_MIN_INTERVAL_MS = 900;
const nextPollAt = new Map<string, number>();

function reservePoll(botId: string): boolean {
  const now = Date.now();
  const next = nextPollAt.get(botId) ?? 0;
  if (now < next) return false;

  const releaseAt = now + POLL_DB_MIN_INTERVAL_MS;
  nextPollAt.set(botId, releaseAt);
  const timer = setTimeout(() => {
    if (nextPollAt.get(botId) === releaseAt) nextPollAt.delete(botId);
  }, POLL_DB_MIN_INTERVAL_MS + 100);
  timer.unref?.();
  return true;
}

/**
 * The stored form of a token: a SHA-256 digest as bytes.
 *
 * Bytes rather than base64 because that is what every other credential digest
 * in this schema is, and `test/schema.test.ts` asserts the type. A digest held
 * as text is one a reader has to be *told* is not readable.
 */
export function tokenDigest(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

/** A bot as its owner sees it. Never includes a token: those are shown once. */
export function botJson(bot: BotRow, username: string, displayName: string | null) {
  return {
    id: bot.account_id,
    username,
    displayName,
    description: bot.description,
    commands: bot.commands,
    disabled: bot.disabled_at !== null,
    createdAt: bot.created_at.toISOString(),
  };
}

export async function findOwned(botId: string, ownerId: string): Promise<BotRow | null> {
  const { rows } = await pool.query<BotRow>(
    `SELECT b.* FROM bots b
       JOIN accounts a ON a.id = b.account_id
      WHERE b.account_id = $1 AND b.owner_account_id = $2 AND a.deleted_at IS NULL`,
    [botId, ownerId],
  );
  return rows[0] ?? null;
}

/**
 * The bot a token belongs to, or null.
 *
 * Constant-time against the stored digest, and a revoked row is not a match —
 * revoking is the whole point of the column, so it is checked in the query
 * rather than afterwards where somebody could forget it.
 */
export async function botForToken(token: string): Promise<BotRow | null> {
  const digest = tokenDigest(token);
  const { rows } = await pool.query<BotRow & { token_hash: Buffer; token_id: string }>(
    `SELECT b.*, t.token_hash, t.id AS token_id
       FROM bot_tokens t
       JOIN bots b ON b.account_id = t.bot_id
       JOIN accounts a ON a.id = b.account_id
      WHERE t.revoked_at IS NULL AND a.deleted_at IS NULL AND t.token_hash = $1`,
    [digest],
  );
  const row = rows[0];
  if (!row) return null;

  // Belt and braces: the lookup above already matched on the digest, so this
  // compares equal by construction. It is here so that a future change to the
  // query — a LIKE, a prefix index — cannot turn an exact match into a partial
  // one without this failing first.
  const stored = row.token_hash;
  if (digest.length !== stored.length || !timingSafeEqual(digest, stored)) return null;

  await pool.query('UPDATE bot_tokens SET last_used_at = now() WHERE id = $1', [row.token_id]);
  return row;
}

/** Issues a token. The plaintext is returned once and never stored. */
export async function issueToken(botId: string): Promise<string> {
  const token = generateToken();
  await pool.query('INSERT INTO bot_tokens (bot_id, token_hash) VALUES ($1, $2)', [
    botId,
    tokenDigest(token),
  ]);
  return token;
}

/** Revokes every live token for a bot. Returns how many were revoked. */
export async function revokeTokens(botId: string): Promise<number> {
  const { rowCount } = await pool.query(
    'UPDATE bot_tokens SET revoked_at = now() WHERE bot_id = $1 AND revoked_at IS NULL',
    [botId],
  );
  return rowCount ?? 0;
}

/**
 * Whether a bot may write to this account.
 *
 * The rule the brief asks for, and it is enforced in one place so it cannot be
 * true on one route and false on another: **a bot may not open a conversation.**
 * The row in `bot_contacts` is the record of the human having written first,
 * and blocking removes the licence again.
 */
export async function mayWriteTo(botId: string, accountId: string): Promise<boolean> {
  const { rows } = await pool.query<{ blocked_at: Date | null }>(
    'SELECT blocked_at FROM bot_contacts WHERE bot_id = $1 AND account_id = $2',
    [botId, accountId],
  );
  const row = rows[0];
  return row !== undefined && row.blocked_at === null;
}

/** Records that a human has written to a bot, which opens the return path. */
export async function noteContact(botId: string, accountId: string): Promise<void> {
  await pool.query(
    `INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)
     ON CONFLICT (bot_id, account_id) DO UPDATE SET blocked_at = NULL`,
    [botId, accountId],
  );
}

/** Whether this bot has sent too much in the last minute. */
export async function isRateLimited(botId: string): Promise<boolean> {
  const { rows } = await pool.query<{ n: string }>(
    `SELECT count(*) AS n FROM bot_messages
      WHERE bot_id = $1 AND author = 'bot' AND created_at > now() - interval '1 minute'`,
    [botId],
  );
  return Number(rows[0]!.n) >= BOT_LIMITS.sendsPerMinute;
}

/**
 * Takes the updates waiting for a bot, marking them delivered.
 *
 * One statement, so two pollers cannot both take the same row: the `UPDATE …
 * RETURNING` over a subselect with `FOR UPDATE SKIP LOCKED` is what makes a
 * duplicated delivery impossible rather than unlikely.
 *
 * The shared poll reservation above additionally means concurrent long polls do
 * not multiply database traffic. Calls inside the sub-second gate answer empty;
 * the long-poll loop will try again on its next tick.
 */
export async function takeUpdates(botId: string, limit: number) {
  if (!reservePoll(botId)) return [];

  const { rows } = await pool.query<{
    id: string;
    account_id: string;
    scope: string;
    scope_id: string | null;
    body: string;
    created_at: Date;
    username: string;
  }>(
    `UPDATE bot_messages m
        SET delivered_at = now()
      WHERE m.id IN (
        SELECT id FROM bot_messages
         WHERE bot_id = $1 AND author = 'user' AND delivered_at IS NULL
         ORDER BY id
         LIMIT $2
         FOR UPDATE SKIP LOCKED
      )
      RETURNING m.id, m.account_id, m.scope, m.scope_id, m.body, m.created_at,
                (SELECT username FROM accounts WHERE id = m.account_id) AS username`,
    [botId, limit],
  );
  return rows
    .sort((a, b) => Number(a.id) - Number(b.id))
    .map((row) => ({
      updateId: Number(row.id),
      chat: { accountId: row.account_id, username: row.username },
      scope: row.scope,
      scopeId: row.scope_id,
      text: row.body,
      at: row.created_at.toISOString(),
    }));
}
