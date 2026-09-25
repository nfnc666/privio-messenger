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
/**
 * A bot by its account id, whoever owns it.
 *
 * Distinct from [findOwned], which is the owner's view and is what every
 * management route uses. This one answers "is this account a bot, and is it
 * still enabled" for callers that are not the owner — a group admin adding it,
 * for one.
 */
export async function byAccountId(accountId: string): Promise<BotRow | null> {
  const { rows } = await pool.query<BotRow>(
    `SELECT b.* FROM bots b
       JOIN accounts a ON a.id = b.account_id AND a.deleted_at IS NULL
      WHERE b.account_id = $1`,
    [accountId],
  );
  return rows[0] ?? null;
}

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

/** What a bot is allowed to do in one group. */
export interface BotGroupRights {
  maySend: boolean;
  mayModerate: boolean;
  mayRestrictMembers: boolean;
  mayManageInvites: boolean;
  readsAllMessages: boolean;
}

/** None of them. What adding a bot grants before an admin decides anything. */
export const NO_BOT_RIGHTS: BotGroupRights = {
  maySend: false,
  mayModerate: false,
  mayRestrictMembers: false,
  mayManageInvites: false,
  readsAllMessages: false,
};

/**
 * What a bot may do in a group, or null when it is not in that group at all.
 *
 * The single place the question is answered, for the same reason [mayWriteTo]
 * is: a right that is checked in two places is a right that will eventually be
 * true in one of them and false in the other. Every route that acts on a bot's
 * behalf inside a group asks this, on every call, rather than trusting
 * something the caller said.
 *
 * Null and "no rights" are deliberately different answers. A bot that was
 * removed is not a bot with nothing to do; it is a bot that is not there, and
 * the routes answer the two differently.
 */
export async function groupRightsOf(
  botId: string,
  groupId: string,
): Promise<BotGroupRights | null> {
  const { rows } = await pool.query<{
    may_send: boolean;
    may_moderate: boolean;
    may_restrict_members: boolean;
    may_manage_invites: boolean;
    reads_all_messages: boolean;
  }>(
    `SELECT may_send, may_moderate, may_restrict_members, may_manage_invites,
            reads_all_messages
       FROM bot_group_members m
       JOIN groups g ON g.id = m.group_id AND g.deleted_at IS NULL
      WHERE m.bot_id = $1 AND m.group_id = $2`,
    [botId, groupId],
  );
  const row = rows[0];
  if (!row) return null;
  return {
    maySend: row.may_send,
    mayModerate: row.may_moderate,
    mayRestrictMembers: row.may_restrict_members,
    mayManageInvites: row.may_manage_invites,
    readsAllMessages: row.reads_all_messages,
  };
}

/**
 * The bots in a group, with their rights, for the members' devices.
 *
 * Every member reads this, not only admins: a device has to know which bots
 * are present in order to decide what to forward, and somebody writing in a
 * group is entitled to know who receives it. The list carries no token and no
 * owner contact detail — it is who is in the room, which the member list
 * already tells them.
 */
export async function botsInGroup(groupId: string): Promise<
  Array<{ botId: string; username: string; displayName: string | null } & BotGroupRights>
> {
  const { rows } = await pool.query(
    `SELECT m.bot_id, a.username, a.display_name,
            m.may_send, m.may_moderate, m.may_restrict_members,
            m.may_manage_invites, m.reads_all_messages
       FROM bot_group_members m
       JOIN accounts a ON a.id = m.bot_id AND a.deleted_at IS NULL
       JOIN bots b ON b.account_id = m.bot_id AND b.disabled_at IS NULL
      WHERE m.group_id = $1
      ORDER BY a.username`,
    [groupId],
  );
  return rows.map((r) => ({
    botId: r.bot_id as string,
    username: r.username as string,
    displayName: r.display_name as string | null,
    maySend: r.may_send as boolean,
    mayModerate: r.may_moderate as boolean,
    mayRestrictMembers: r.may_restrict_members as boolean,
    mayManageInvites: r.may_manage_invites as boolean,
    readsAllMessages: r.reads_all_messages as boolean,
  }));
}

/** Records that a human has written to a bot, which opens the return path. */
export async function noteContact(botId: string, accountId: string): Promise<void> {
  await pool.query(
    `INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)
     ON CONFLICT (bot_id, account_id) DO UPDATE SET blocked_at = NULL`,
    [botId, accountId],
  );
}

/**
 * Stops a bot: it may no longer write, and nothing further reaches it.
 *
 * The same row `noteContact` writes, with the date set. Two effects, and both
 * are wanted:
 *
 * * `mayWriteTo` goes false, so the bot's next send is refused;
 * * [takeUpdates] stops handing over anything from this person, including
 *   messages that were waiting undelivered when they stopped it.
 *
 * Writing to the bot again clears it — that is `noteContact`, and it is the
 * right way round: somebody who types a message to a bot has decided to talk to
 * it again. Blocking is the stronger thing and goes through the account block
 * list, which no message of theirs can undo.
 */
export async function stopBot(botId: string, accountId: string): Promise<void> {
  await pool.query(
    `INSERT INTO bot_contacts (bot_id, account_id, blocked_at)
     VALUES ($1, $2, now())
     ON CONFLICT (bot_id, account_id) DO UPDATE SET blocked_at = now()`,
    [botId, accountId],
  );
}

/** Whether this person has ever started this bot, and whether they stopped it. */
export async function contactState(
  botId: string,
  accountId: string,
): Promise<{ started: boolean; stopped: boolean }> {
  const { rows } = await pool.query<{ blocked_at: Date | null }>(
    'SELECT blocked_at FROM bot_contacts WHERE bot_id = $1 AND account_id = $2',
    [botId, accountId],
  );
  const row = rows[0];
  if (row === undefined) return { started: false, stopped: false };
  return { started: row.blocked_at === null, stopped: row.blocked_at !== null };
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
    kind: string;
    pressed_message_id: string | null;
    created_at: Date;
    username: string;
  }>(
    `UPDATE bot_messages m
        SET delivered_at = now()
      WHERE m.id IN (
        SELECT id FROM bot_messages
         WHERE bot_id = $1 AND author = 'user' AND delivered_at IS NULL
           -- Nothing from somebody who has stopped this bot, including what was
           -- already waiting when they stopped it. "Stop" that let the queue
           -- drain afterwards would be a stop the operator still hears through.
           AND EXISTS (
             SELECT 1 FROM bot_contacts c
              WHERE c.bot_id = bot_messages.bot_id
                AND c.account_id = bot_messages.account_id
                AND c.blocked_at IS NULL
           )
         ORDER BY id
         LIMIT $2
         FOR UPDATE SKIP LOCKED
      )
      RETURNING m.id, m.account_id, m.scope, m.scope_id, m.body, m.kind,
                m.pressed_message_id, m.created_at,
                (SELECT username FROM accounts WHERE id = m.account_id) AS username`,
    [botId, limit],
  );
  return rows
    .sort((a, b) => Number(a.id) - Number(b.id))
    .map((row) => {
      // A button press travels the same way a typed message does — same table,
      // same take-once delivery, same order — and is told apart here rather
      // than in a second stream a bot could read out of sequence.
      const press = row.kind === 'button' && row.pressed_message_id !== null;
      return {
        updateId: Number(row.id),
        chat: { accountId: row.account_id, username: row.username },
        scope: row.scope,
        scopeId: row.scope_id,
        // A press has no text. Empty rather than the button id, so a bot that
        // only looks at `text` cannot mistake an id for something somebody
        // typed.
        text: press ? '' : row.body,
        // Parsed here rather than in every bot. `/help@name` and `/help` differ
        // in a group with several bots, and a parser per bot is a parser that
        // disagrees with the one the app used to decide whether to forward it.
        command: press ? null : parseCommand(row.body),
        button: press
          ? { id: row.body, messageId: Number(row.pressed_message_id) }
          : null,
        at: row.created_at.toISOString(),
      };
    });
}

export interface ParsedCommand {
  /** Without the slash and lower-cased: `help`. */
  name: string;
  /** The bot it named, if it named one: `/help@weather` -> `weather`. */
  addressedTo: string | null;
  /** Everything after the first word, untouched. */
  args: string;
}

/**
 * The command in a message, or null when there is not one.
 *
 * Only a leading slash counts. A slash mid-sentence is a slash, and a message
 * that merely contains `/help` somewhere is not a command — treating it as one
 * is how a bot answers a sentence about commands.
 */
export function parseCommand(text: string): ParsedCommand | null {
  const trimmed = text.trimStart();
  if (!trimmed.startsWith('/')) return null;

  const firstSpace = trimmed.search(/\s/);
  const head = firstSpace < 0 ? trimmed : trimmed.slice(0, firstSpace);
  const args = firstSpace < 0 ? '' : trimmed.slice(firstSpace + 1).trim();

  const at = head.indexOf('@');
  const name = (at < 0 ? head.slice(1) : head.slice(1, at)).toLowerCase();
  if (name.length === 0) return null;

  return {
    name,
    addressedTo: at < 0 ? null : head.slice(at + 1).toLowerCase() || null,
    args,
  };
}
