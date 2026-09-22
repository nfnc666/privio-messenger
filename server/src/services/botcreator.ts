import { pool, withTransaction } from '../db/pool.js';
import { DISPLAY_NAME_LIMIT, cleanDisplayName, isTooLong } from './display_name.js';
import * as bots from './bots.js';

/**
 * @botcreator: the assistant that makes bots.
 *
 * A state machine rather than a chat model. Every reply below is produced from
 * the last thing the person typed and a small amount of state held in
 * `botcreator_state`, so the whole conversation is deterministic and testable,
 * and nothing about it depends on a service being up.
 *
 * **A token never travels through here.** `/token` and `/newbot` finish by
 * telling the app to open a protected sheet, and the token is fetched over the
 * ordinary authenticated API by the owner's own client. It is not put in a chat
 * message, because a chat message is exactly the thing that gets scrolled back
 * to, screenshotted, and — in a bot conversation, which is not end-to-end
 * encrypted — stored in the clear on this server.
 */

export interface AssistantReply {
  /** What the assistant says. Plain text; the app renders it. */
  text: string;
  /**
   * An instruction to the app, not to the person.
   *
   * `showToken` is how a token reaches a screen without reaching a message:
   * the app opens its protected sheet and asks the API for one.
   */
  action?: { kind: 'showToken'; botId: string } | { kind: 'openBots' };
}

type Step =
  | { at: 'idle' }
  | { at: 'newbot.name' }
  | { at: 'newbot.username'; name: string }
  | { at: 'setname'; botId: string }
  | { at: 'setdescription'; botId: string }
  | { at: 'setcommands'; botId: string }
  | { at: 'deletebot.confirm'; botId: string; username: string };

const HELP = [
  'I can make bots for you and look after the ones you have.',
  '',
  '/newbot — create a bot',
  '/mybots — list your bots',
  '/setname — change a bot’s display name',
  '/setdescription — change what a bot says about itself',
  '/setuserpic — change a bot’s picture',
  '/setcommands — set the commands a bot offers',
  '/token — generate a new API token',
  '/revoke — revoke the current tokens',
  '/deletebot — delete a bot',
].join('\n');

/** The username the assistant answers to. Reserved in migration 029. */
export const BOTCREATOR_USERNAME = 'botcreator';

/**
 * Makes sure the assistant's account exists.
 *
 * Migration 029 inserts it, but a one-time insert is a fragile home for an
 * account the product depends on: anything that truncates or restores the
 * accounts table loses it, and nothing brings it back. This runs at start-up
 * and is idempotent, so the account is *ensured* rather than assumed — which
 * is how a test harness that truncates between runs still has an assistant to
 * talk to, and how a restored backup does too.
 *
 * The password hash is `!`, which is not a valid Argon2 encoding: `verifySecret`
 * catches the parse failure and answers false for every input, so there is no
 * password that signs this account in.
 */
export async function ensureAssistant(): Promise<string> {
  const { rows } = await pool.query<{ id: string }>(
    `INSERT INTO accounts (username, display_name, password_hash, is_bot)
     VALUES ($1, 'Bot Creator', '!', true)
     ON CONFLICT (username) DO UPDATE SET is_bot = true
     RETURNING id`,
    [BOTCREATOR_USERNAME],
  );
  return rows[0]!.id;
}

/** Where a conversation with the assistant has got to. */
async function readStep(accountId: string): Promise<Step> {
  const { rows } = await pool.query<{ step: Step }>(
    'SELECT step FROM botcreator_state WHERE account_id = $1',
    [accountId],
  );
  return rows[0]?.step ?? { at: 'idle' };
}

async function writeStep(accountId: string, step: Step): Promise<void> {
  await pool.query(
    `INSERT INTO botcreator_state (account_id, step) VALUES ($1, $2)
     ON CONFLICT (account_id) DO UPDATE SET step = $2, updated_at = now()`,
    [accountId, JSON.stringify(step)],
  );
}

async function ownedBots(ownerId: string) {
  const { rows } = await pool.query<{ account_id: string; username: string; display_name: string | null }>(
    `SELECT b.account_id, a.username, a.display_name
       FROM bots b JOIN accounts a ON a.id = b.account_id
      WHERE b.owner_account_id = $1 AND a.deleted_at IS NULL
      ORDER BY b.created_at`,
    [ownerId],
  );
  return rows;
}

interface OwnedBot {
  account_id: string;
  username: string;
  display_name: string | null;
}

/** Resolves "which bot" for a command that names one, or asks. */
async function pickBot(
  ownerId: string,
  argument: string,
): Promise<{ bot: OwnedBot; error?: undefined } | { error: string; bot?: undefined }> {
  const list = await ownedBots(ownerId);
  if (list.length === 0) return { error: 'You have no bots yet. Send /newbot to make one.' };
  const wanted = argument.trim().replace(/^@/, '').toLowerCase();
  if (wanted) {
    const found = list.find((bot) => bot.username === wanted);
    return found ? { bot: found } : { error: `You have no bot called @${wanted}.` };
  }
  if (list.length === 1) return { bot: list[0]! };
  return {
    error: [
      'Which bot? Add its username, like this:',
      ...list.map((bot) => `  /${'…'} @${bot.username}`),
    ].join('\n'),
  };
}

const USERNAME = /^[a-z0-9_.]{3,32}$/;

/**
 * Answers one message to @botcreator.
 *
 * Pure apart from the database: given the same state and the same text it
 * produces the same reply, which is what makes the whole flow testable without
 * a chat screen.
 */
export async function respond(ownerId: string, text: string): Promise<AssistantReply> {
  const trimmed = text.trim();
  const [word = '', ...rest] = trimmed.split(/\s+/);
  const command = word.toLowerCase();
  const argument = rest.join(' ');
  const step = await readStep(ownerId);

  // A command always wins over whatever step we were in, so somebody who
  // started /newbot and changed their mind is never stuck inside it.
  if (command.startsWith('/')) {
    await writeStep(ownerId, { at: 'idle' });

    switch (command) {
      case '/start':
      case '/help':
        return { text: `Hello. ${HELP}` };

      case '/newbot':
        await writeStep(ownerId, { at: 'newbot.name' });
        return { text: 'Alright. What should the bot be called? This is the name people see.' };

      case '/mybots': {
        const list = await ownedBots(ownerId);
        if (list.length === 0) return { text: 'You have no bots yet. Send /newbot to make one.' };
        return {
          text: ['Your bots:', ...list.map((bot) => `  ${bot.display_name ?? bot.username} — @${bot.username}`)].join('\n'),
          action: { kind: 'openBots' },
        };
      }

      case '/setname':
      case '/setdescription':
      case '/setcommands': {
        const picked = await pickBot(ownerId, argument);
        if (picked.error !== undefined) return { text: picked.error };
        const at = command === '/setname' ? 'setname' : command === '/setdescription' ? 'setdescription' : 'setcommands';
        await writeStep(ownerId, { at, botId: picked.bot.account_id } as Step);
        return {
          text:
            at === 'setname'
              ? `New display name for @${picked.bot.username}?`
              : at === 'setdescription'
                ? `What should @${picked.bot.username} say about itself?`
                : [
                    `Send the commands for @${picked.bot.username}, one per line:`,
                    '',
                    'start - what this does',
                    'help - show help',
                    '',
                    'Send "none" to clear them.',
                  ].join('\n'),
        };
      }

      case '/setuserpic': {
        const picked = await pickBot(ownerId, argument);
        if (picked.error !== undefined) return { text: picked.error };
        // The picture is an upload, which is a thing the app does and a chat
        // message cannot. So this hands over rather than pretending.
        return {
          text: `Pick a picture for @${picked.bot.username} on its page — I have opened it for you.`,
          action: { kind: 'openBots' },
        };
      }

      case '/token': {
        const picked = await pickBot(ownerId, argument);
        if (picked.error !== undefined) return { text: picked.error };
        return {
          text: `Here is a new token for @${picked.bot.username}. It is shown once and it is not in this chat.`,
          action: { kind: 'showToken', botId: picked.bot.account_id },
        };
      }

      case '/revoke': {
        const picked = await pickBot(ownerId, argument);
        if (picked.error !== undefined) return { text: picked.error };
        const revoked = await bots.revokeTokens(picked.bot.account_id);
        return {
          text:
            revoked === 0
              ? `@${picked.bot.username} had no live tokens.`
              : `Revoked ${revoked} token${revoked === 1 ? '' : 's'} for @${picked.bot.username}. Anything using one stops working now.`,
        };
      }

      case '/deletebot': {
        const picked = await pickBot(ownerId, argument);
        if (picked.error !== undefined) return { text: picked.error };
        await writeStep(ownerId, {
          at: 'deletebot.confirm',
          botId: picked.bot.account_id,
          username: picked.bot.username,
        });
        return {
          text: `Delete @${picked.bot.username}? This cannot be undone. Type the username to confirm, or /cancel.`,
        };
      }

      case '/cancel':
        return { text: 'Cancelled.' };

      default:
        return { text: `I do not know ${command}.\n\n${HELP}` };
    }
  }

  // Not a command: it is an answer to whatever was asked.
  switch (step.at) {
    case 'newbot.name': {
      if (trimmed.length === 0 || trimmed.length > 64) {
        return { text: 'That name will not do. One to sixty-four characters, please.' };
      }
      await writeStep(ownerId, { at: 'newbot.username', name: trimmed });
      return {
        text: `Good. Now a username for it — 3 to 32 characters, letters, digits, dot or underscore. People will write to it by that name.`,
      };
    }

    case 'newbot.username': {
      const username = trimmed.replace(/^@/, '').toLowerCase();
      if (!USERNAME.test(username)) {
        return { text: 'That username will not do. 3 to 32 characters: a–z, 0–9, dot or underscore.' };
      }
      const created = await createBot(ownerId, step.name, username);
      if (created.error !== undefined) return { text: created.error };
      await writeStep(ownerId, { at: 'idle' });
      return {
        text: [
          `Done. @${username} is yours.`,
          '',
          'Its token is next — I will show it once, in a screen that keeps it out of this conversation.',
          '',
          'One thing worth knowing: a chat with a bot is not end-to-end encrypted. Whoever runs the bot reads what is sent to it, and so does the server. Ordinary chats are unchanged.',
        ].join('\n'),
        action: { kind: 'showToken', botId: created.botId },
      };
    }

    case 'setname': {
      // The same cleaning a person's own name gets, and for the same reason:
      // a bot's name is drawn in other people's chat lists.
      const name = cleanDisplayName(trimmed);
      if (name === null) return { text: 'A name, please — that was nothing but spaces.' };
      if (isTooLong(name)) return { text: `At most ${DISPLAY_NAME_LIMIT} characters, please.` };
      await pool.query('UPDATE accounts SET display_name = $2 WHERE id = $1', [step.botId, name]);
      await writeStep(ownerId, { at: 'idle' });
      return { text: `Renamed to ${name}.` };
    }

    case 'setdescription': {
      if (trimmed.length > 512) return { text: 'That is too long — 512 characters at most.' };
      await pool.query('UPDATE bots SET description = $2 WHERE account_id = $1', [step.botId, trimmed]);
      await writeStep(ownerId, { at: 'idle' });
      return { text: 'Description set.' };
    }

    case 'setcommands': {
      if (trimmed.toLowerCase() === 'none') {
        await pool.query(`UPDATE bots SET commands = '[]'::jsonb WHERE account_id = $1`, [step.botId]);
        await writeStep(ownerId, { at: 'idle' });
        return { text: 'Commands cleared.' };
      }
      const parsed = parseCommands(trimmed);
      if (parsed.error !== undefined) return { text: parsed.error };
      await pool.query('UPDATE bots SET commands = $2::jsonb WHERE account_id = $1', [
        step.botId,
        JSON.stringify(parsed.commands),
      ]);
      await writeStep(ownerId, { at: 'idle' });
      return { text: `Set ${parsed.commands.length} command${parsed.commands.length === 1 ? '' : 's'}.` };
    }

    case 'deletebot.confirm': {
      if (trimmed.replace(/^@/, '').toLowerCase() !== step.username) {
        await writeStep(ownerId, { at: 'idle' });
        return { text: 'That is not the username. Nothing was deleted.' };
      }
      await deleteBot(step.botId);
      await writeStep(ownerId, { at: 'idle' });
      return { text: `@${step.username} is gone.` };
    }

    case 'idle':
      return { text: HELP };
  }
}

/** Reads the `command - description` block the assistant asks for. */
function parseCommands(
  text: string,
): { commands: bots.BotCommand[]; error?: undefined } | { error: string; commands?: undefined } {
  const commands: bots.BotCommand[] = [];
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const match = /^\/?([a-z0-9_]{1,32})\s*-\s*(.{1,256})$/i.exec(trimmed);
    if (!match) return { error: `I could not read this line:\n  ${trimmed}\n\nUse: command - what it does` };
    commands.push({ command: match[1]!.toLowerCase(), description: match[2]!.trim() });
  }
  if (commands.length === 0) return { error: 'No commands found. Send "none" to clear them.' };
  if (commands.length > 100) return { error: 'That is more than a hundred commands.' };
  return { commands };
}

/**
 * Creates a bot and its account.
 *
 * The password hash is `!`, which is not a valid Argon2 encoding: `verifySecret`
 * catches the parse failure and returns false, so there is no password that
 * signs a bot account in. A bot is reached by token, never by login.
 */
export async function createBot(
  ownerId: string,
  name: string,
  username: string,
): Promise<{ botId: string; error?: undefined } | { error: string; botId?: undefined }> {
  const { rowCount: reserved } = await pool.query(
    'SELECT 1 FROM reserved_usernames WHERE username = $1',
    [username],
  );
  if (reserved === 1) return { error: `@${username} is not available.` };

  const { rows: mine } = await pool.query<{ n: string }>(
    `SELECT count(*) AS n FROM bots b JOIN accounts a ON a.id = b.account_id
      WHERE b.owner_account_id = $1 AND a.deleted_at IS NULL`,
    [ownerId],
  );
  if (Number(mine[0]!.n) >= bots.BOT_LIMITS.perOwner) {
    return { error: 'You have as many bots as one account may own.' };
  }

  try {
    return await withTransaction(async (client) => {
      const { rows } = await client.query<{ id: string }>(
        `INSERT INTO accounts (username, display_name, password_hash, is_bot)
         VALUES ($1, $2, $3, true) RETURNING id`,
        [username, name, '!'],
      );
      const botId = rows[0]!.id;
      await client.query('INSERT INTO bots (account_id, owner_account_id) VALUES ($1, $2)', [
        botId,
        ownerId,
      ]);
      return { botId };
    });
  } catch (error) {
    if ((error as { code?: string }).code === '23505') {
      return { error: `@${username} is taken. Try another.` };
    }
    throw error;
  }
}

/** Deletes a bot: tokens die, the account is tombstoned, the username frees. */
export async function deleteBot(botId: string): Promise<void> {
  await withTransaction(async (client) => {
    await client.query('UPDATE bot_tokens SET revoked_at = now() WHERE bot_id = $1', [botId]);
    await client.query('DELETE FROM bot_messages WHERE bot_id = $1', [botId]);
    await client.query(
      `UPDATE accounts
          SET deleted_at = now(),
              username = left('deleted.' || replace(id::text, '-', ''), 32),
              display_name = NULL
        WHERE id = $1`,
      [botId],
    );
  });
}
