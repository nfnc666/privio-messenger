import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import type { BlobStorage } from '../services/storage.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import * as bots from '../services/bots.js';
import * as webhooks from '../services/bot_webhooks.js';
import * as assistant from '../services/botcreator.js';
import { cleanDisplayName, isTooLong } from '../services/display_name.js';
import { ApiError } from '../util/errors.js';
import { requireGroupMembership } from '../services/group_membership.js';
import { clearKeyRequestsFor } from '../services/key_requests.js';
import { assertResolvesPublicly, parsePushEndpoint } from '../util/outbound.js';
import { parse, usernameSchema, uuidSchema } from '../util/validate.js';
import { rateLimitFactor } from '../config.js';

/**
 * Bots: the owner's side, the assistant, and the API a bot itself speaks.
 *
 * Three audiences in one file because they are one feature, and separating them
 * would hide the thing worth seeing side by side: the owner routes take a
 * session, the bot API takes a token, and **neither can do the other's job**.
 * A token cannot rename a bot; a session cannot poll for updates.
 */

const commandsSchema = z
  .array(
    z.object({
      command: z.string().trim().regex(/^[a-z0-9_]{1,32}$/),
      description: z.string().trim().min(1).max(256),
    }),
  )
  .max(100);

/**
 * The buttons a bot may put under one message.
 *
 * Eight, because a column of buttons a person has to scroll is a column whose
 * last button nobody presses, and because every one of them is a thing the bot
 * has to handle. The id is what comes back on a press and is the bot's own
 * business; the label is what the person reads and decides on.
 */
const buttonsSchema = z
  .array(
    z.object({
      id: z.string().trim().min(1).max(64),
      label: z.string().trim().min(1).max(64),
    }),
  )
  .max(8)
  .refine(
    (buttons) => new Set(buttons.map((b) => b.id)).size === buttons.length,
    { message: 'Two buttons with the same id cannot be told apart on a press' },
  );

/**
 * A poll a bot puts to the people it sends it to.
 *
 * Ten answers at most, like a channel poll, and no two the same: an answer a
 * person cannot tell from its neighbour is an answer they cannot choose. The
 * question and the answers are plaintext, as everything on the bot path is —
 * migration 041 says so where the columns are defined.
 */
const pollSchema = z
  .object({
    question: z.string().trim().min(1).max(300),
    options: z
      .array(z.string().trim().min(1).max(100))
      .min(2)
      .max(bots.BOT_LIMITS.maxPollOptions)
      .refine((options) => new Set(options).size === options.length, {
        message: 'Two answers with the same words cannot be told apart',
      }),
    /** 1 for a single choice; more lets a person pick up to that many. */
    maxChoices: z.number().int().min(1).max(bots.BOT_LIMITS.maxPollOptions).default(1),
    /**
     * Whether the people answering may see the tally. Off by default: they do
     * not know who else was asked, and with few people a tally gives away how
     * somebody else answered.
     */
    showResults: z.boolean().default(false),
    closesAt: z.string().datetime({ offset: true }).optional(),
  })
  .refine((poll) => poll.maxChoices <= poll.options.length, {
    message: 'A poll cannot take more answers than it offers',
  });

/** Pulls the bearer token off a bot request. Never logged, anywhere. */
function botToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

export function botRoutes(storage: BlobStorage): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = {
      preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
    };

    /** A bot's own identity, resolved from its token. */
    async function requireBot(request: FastifyRequest) {
      const token = botToken(request);
      if (token === null) throw ApiError.unauthorized('no_token', 'Send a bot token as a bearer token');
      const bot = await bots.botForToken(token);
      if (!bot) throw ApiError.unauthorized('invalid_token', 'That token is not valid');
      if (bot.disabled_at !== null) {
        throw ApiError.forbidden('bot_disabled', 'This bot is switched off');
      }
      return bot;
    }

    // --- The owner's side -----------------------------------------------------

    app.get('/v1/bots', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const { rows } = await pool.query<bots.BotRow & { username: string; display_name: string | null }>(
        `SELECT b.*, a.username, a.display_name
           FROM bots b JOIN accounts a ON a.id = b.account_id
          WHERE b.owner_account_id = $1 AND a.deleted_at IS NULL
          ORDER BY b.created_at`,
        [accountId],
      );
      return { bots: rows.map((row) => bots.botJson(row, row.username, row.display_name)) };
    });

    app.post('/v1/bots', requireAuth, async (request, reply) => {
      const { accountId } = auth(request);
      const body = parse(
        z.object({ name: z.string().trim().min(1).max(64), username: usernameSchema }),
        request.body,
      );
      const created = await assistant.createBot(accountId, body.name, body.username);
      if (created.error !== undefined) throw ApiError.conflict('username_taken', created.error);

      const { rows } = await pool.query<bots.BotRow & { username: string; display_name: string | null }>(
        `SELECT b.*, a.username, a.display_name FROM bots b JOIN accounts a ON a.id = b.account_id
          WHERE b.account_id = $1`,
        [created.botId],
      );
      reply.code(201);
      return bots.botJson(rows[0]!, rows[0]!.username, rows[0]!.display_name);
    });

    app.patch('/v1/bots/:id', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const body = parse(
        z.object({
          name: z.string().max(512).transform(cleanDisplayName).refine((name) => name === null || !isTooLong(name)).optional(),
          description: z.string().trim().max(512).nullable().optional(),
          commands: commandsSchema.optional(),
          disabled: z.boolean().optional(),
        }),
        request.body,
      );
      const owned = await bots.findOwned(params.id, accountId);
      if (!owned) throw ApiError.notFound('bot_not_found', 'No such bot of yours');

      if (body.name !== undefined) {
        await pool.query('UPDATE accounts SET display_name = $2 WHERE id = $1', [params.id, body.name]);
      }
      if (body.description !== undefined) {
        await pool.query('UPDATE bots SET description = $2 WHERE account_id = $1', [
          params.id,
          body.description,
        ]);
      }
      if (body.commands !== undefined) {
        await pool.query('UPDATE bots SET commands = $2::jsonb WHERE account_id = $1', [
          params.id,
          JSON.stringify(body.commands),
        ]);
      }
      if (body.disabled !== undefined) {
        await pool.query(
          'UPDATE bots SET disabled_at = CASE WHEN $2 THEN now() ELSE NULL END WHERE account_id = $1',
          [params.id, body.disabled],
        );
      }

      const { rows } = await pool.query<bots.BotRow & { username: string; display_name: string | null }>(
        `SELECT b.*, a.username, a.display_name FROM bots b JOIN accounts a ON a.id = b.account_id
          WHERE b.account_id = $1`,
        [params.id],
      );
      return bots.botJson(rows[0]!, rows[0]!.username, rows[0]!.display_name);
    });

    app.delete('/v1/bots/:id', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const owned = await bots.findOwned(params.id, accountId);
      if (!owned) throw ApiError.notFound('bot_not_found', 'No such bot of yours');
      await assistant.deleteBot(params.id);
      return { deleted: true };
    });

    /**
     * Issues a token.
     *
     * The plaintext is in this response and nowhere else — not in a log, not in
     * a chat message, not readable again afterwards. Losing it means generating
     * another, which is the correct direction for that failure to fall.
     */
    app.post('/v1/bots/:id/token', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const owned = await bots.findOwned(params.id, accountId);
      if (!owned) throw ApiError.notFound('bot_not_found', 'No such bot of yours');

      // Rotating means the old one stops working. A "new token" that left the
      // previous one live would be an additional key, not a replacement, and
      // somebody rotating after a leak would still be leaking.
      await bots.revokeTokens(params.id);
      const token = await bots.issueToken(params.id);
      return { token };
    });

    app.delete('/v1/bots/:id/token', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const owned = await bots.findOwned(params.id, accountId);
      if (!owned) throw ApiError.notFound('bot_not_found', 'No such bot of yours');
      const revoked = await bots.revokeTokens(params.id);
      return { revoked };
    });

    // --- The assistant --------------------------------------------------------

    /**
     * One turn of the conversation with @botcreator.
     *
     * Server-side because the assistant *is* the server: it creates accounts,
     * issues tokens and deletes bots. A client-side script pretending to be it
     * would be a script anybody could lie to.
     */
    app.post(
      '/v1/botcreator/say',
      {
        ...requireAuth,
        config: { rateLimit: { max: 60 * rateLimitFactor, timeWindow: '1 minute' } },
      },
      async (request) => {
        const { accountId } = auth(request);
        const body = parse(z.object({ text: z.string().max(4096) }), request.body);
        return assistant.respond(accountId, body.text);
      },
    );

    // --- The API a bot speaks -------------------------------------------------

    app.get('/v1/bot/me', async (request) => {
      const bot = await requireBot(request);
      const { rows } = await pool.query<{ username: string; display_name: string | null }>(
        'SELECT username, display_name FROM accounts WHERE id = $1',
        [bot.account_id],
      );
      return {
        id: bot.account_id,
        username: rows[0]!.username,
        displayName: rows[0]!.display_name,
        commands: bot.commands,
      };
    });

    /**
     * The bot publishes its own command menu.
     *
     * Its commands and nothing else. The display name, the description and the
     * picture stay with the owner, who is a person with a phone and a session —
     * a token that could rewrite how a bot presents itself would make a leaked
     * token a way to impersonate the bot to everybody already talking to it.
     *
     * The commands are different: they are what the bot can do, the bot is the
     * thing that knows, and a stale menu is a menu that offers commands the code
     * no longer has. So the process that has the code publishes them, usually on
     * start-up.
     */
    app.patch('/v1/bot/me', async (request) => {
      const bot = await requireBot(request);
      const body = parse(z.object({ commands: commandsSchema }), request.body);
      await pool.query('UPDATE bots SET commands = $2 WHERE account_id = $1', [
        bot.account_id,
        JSON.stringify(body.commands),
      ]);
      return { commands: body.commands };
    });

    /**
     * Long polling for what people have said to this bot.
     *
     * Held open for up to `maxPollSeconds` and answered the moment anything
     * arrives. A plain 200 with an empty list is the correct answer to a quiet
     * minute — the caller loops.
     */
    app.get('/v1/bot/updates', async (request) => {
      const bot = await requireBot(request);
      const query = parse(
        z.object({
          timeout: z.coerce.number().int().min(0).max(bots.BOT_LIMITS.maxPollSeconds).default(25),
          limit: z.coerce.number().int().min(1).max(100).default(100),
        }),
        request.query,
      );

      const deadline = Date.now() + query.timeout * 1000;
      for (;;) {
        const updates = await bots.takeUpdates(bot.account_id, query.limit);
        if (updates.length > 0) return { updates };
        if (Date.now() >= deadline) return { updates: [] };
        // Polled rather than pushed. The bus exists and could carry this, but a
        // second delivery path for a feature nobody is using yet is a second
        // thing to get wrong; a one-second poll inside a held request is honest
        // and costs one query per second per connected bot.
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    });

    /**
     * Uploads a picture or a file the bot is about to send.
     *
     * Two steps rather than one, like the human path: the bytes go up on their
     * own and the send then points at the object. A single multipart route
     * would mean holding a file in memory while deciding whether the bot may
     * write to that person at all.
     *
     * **The bytes are not encrypted.** Everything on the bot path is plaintext
     * this server can read, and an attachment is no different; migration 040
     * says so and `docs/bots.md` says why. Sealing it to look like the rest of
     * Privio while the bot holds the key would be the dishonest option.
     *
     * The object is nobody's download until a message points at it: the rule in
     * `mayDownload` is the `bot_messages` row, not the id.
     */
    app.post(
      '/v1/bot/media',
      { bodyLimit: bots.BOT_LIMITS.maxAttachmentBytes },
      async (request, reply) => {
        const bot = await requireBot(request);
        const body = request.body;
        if (!Buffer.isBuffer(body) || body.length === 0) {
          throw ApiError.badRequest(
            'empty_body',
            'Send the bytes as application/octet-stream',
          );
        }
        const query = parse(
          z.object({
            kind: z.enum(['image', 'file']).default('file'),
            /**
             * What to call it on screen and when saving it. The bot's name for
             * the file, kept as a name: anything that could be read as a path
             * is refused rather than cleaned up, because a cleaned-up path is
             * one somebody has to be sure got cleaned.
             */
            name: z
              .string()
              .trim()
              .min(1)
              .max(200)
              .refine((value) => !/[\\/\u0000]/.test(value), {
                message: 'A file name cannot contain a path separator',
              })
              .optional(),
          }),
          request.query,
        );

        // Against the bot's own account, like anybody else's upload. A bot that
        // fills the disk is a bot whose owner has filled their own quota.
        const { rows: held } = await pool.query<{ used: string }>(
          `SELECT COALESCE(sum(byte_size), 0)::text AS used
             FROM media_objects
            WHERE owner_account_id = $1
              AND (expires_at > now() OR retained_at IS NOT NULL)`,
          [bot.account_id],
        );
        if (Number(held[0]?.used ?? 0) + body.length > config.MEDIA_QUOTA_BYTES) {
          throw ApiError.payloadTooLarge(
            'media_quota_exceeded',
            'This bot is holding as much media as it may. Older files free space as they expire.',
          );
        }

        const storageKey = await storage.put(body);
        const expiresAt = new Date(Date.now() + config.MEDIA_TTL_DAYS * 86_400_000);
        const { rows } = await pool.query<{ id: string }>(
          `INSERT INTO media_objects
             (owner_account_id, byte_size, storage_key, expires_at, kind)
           VALUES ($1, $2, $3, $4, 'bot_attachment') RETURNING id`,
          [bot.account_id, body.length, storageKey, expiresAt],
        );
        reply.code(201);
        // No download token: the row that names the recipient is what
        // authorises this one, so a token would be a second answer to the same
        // question and a second thing to leak.
        return {
          mediaId: rows[0]!.id,
          byteSize: body.length,
          kind: query.kind,
          name: query.name ?? null,
          expiresAt: expiresAt.toISOString(),
        };
      },
    );

    app.post('/v1/bot/send', async (request) => {
      const bot = await requireBot(request);
      const body = parse(
        z.object({
          to: uuidSchema,
          /** Optional only beside a poll, whose question is the message. */
          text: z.string().trim().min(1).max(4096).optional(),
          /**
           * The group this is a reply in, when it is one.
           *
           * Present or absent rather than a separate route, because everything
           * else about the send is identical and two routes would be two places
           * to forget the rate limit. What differs is which permission is
           * checked, and that is decided below.
           */
          groupId: uuidSchema.optional(),
          /**
           * Buttons to draw under this message.
           *
           * Attached to the message rather than sent separately, because a button
           * that arrived after the message would be a button appearing under
           * something a person has already read past.
           */
          buttons: buttonsSchema.optional(),
          /**
           * A picture or a file from `POST /v1/bot/media`.
           *
           * Its own upload rather than bytes inline, so this route can refuse a
           * send without having held a file in memory first.
           */
          mediaId: uuidSchema.optional(),
          /** How to draw it. Defaults to a file row, which is the safe default. */
          mediaKind: z.enum(['image', 'file']).optional(),
          /** What to call it on screen and when saving it. */
          fileName: z.string().trim().min(1).max(200).optional(),
          /**
           * A new poll, carried by this message.
           *
           * The question is the message: `text`, when given as well, is a line
           * drawn above it.
           */
          poll: pollSchema.optional(),
          /**
           * A poll this bot made before, put to one more person.
           *
           * What makes it a poll rather than a row of buttons: the same question
           * to everybody who has started the bot, and one tally read back. The
           * answers are per person and per poll, so somebody sent it twice still
           * has one answer.
           */
          pollId: z.number().int().min(1).optional(),
        }),
        request.body,
      );

      const carriesPoll = body.poll !== undefined || body.pollId !== undefined;
      if (body.poll !== undefined && body.pollId !== undefined) {
        throw ApiError.badRequest('poll_twice', 'Send a new poll or an existing pollId, not both');
      }
      if (!carriesPoll && body.text === undefined) {
        throw ApiError.badRequest('text_required', 'A message needs text');
      }
      // One thing to answer per message. Buttons under a poll would be two ways
      // to reply to the same bubble, and a poll around a file is a file nobody
      // will notice under the question.
      if (carriesPoll && (body.buttons?.length || body.mediaId)) {
        throw ApiError.badRequest(
          'poll_alone',
          'A poll cannot carry buttons or an attachment as well',
        );
      }
      if (body.poll?.closesAt && new Date(body.poll.closesAt).getTime() <= Date.now()) {
        throw ApiError.badRequest('closes_in_past', 'A poll cannot close before it is sent');
      }

      if (body.groupId) {
        // Checked on this call rather than remembered from when the bot was
        // added: an admin who takes the right away means the *next* send fails,
        // not the one after the bot notices.
        const rights = await bots.groupRightsOf(bot.account_id, body.groupId);
        if (rights === null) {
          throw ApiError.forbidden(
            'not_in_group',
            'This bot is not a member of that group.',
          );
        }
        if (!rights.maySend) {
          throw ApiError.forbidden(
            'missing_right',
            'This bot does not have permission to send messages in that group.',
          );
        }
        // `to` is the member whose device asked, which is who the reply is
        // addressed to. It still has to have written to the bot: being in a
        // group with a bot is not the same as having opened a conversation.
        if (!(await bots.mayWriteTo(bot.account_id, body.to))) {
          throw ApiError.forbidden(
            'not_contacted',
            'This bot may only reply to people who have written to it.',
          );
        }
      } else if (!(await bots.mayWriteTo(bot.account_id, body.to))) {
        // A bot may not open a conversation. The row in `bot_contacts` is the
        // record of the person having written first, and blocking removes it.
        throw ApiError.forbidden(
          'not_contacted',
          'This bot may only reply to people who have written to it.',
        );
      }
      if (await bots.isRateLimited(bot.account_id)) {
        throw ApiError.tooManyRequests('rate_limited', 'This bot is sending too fast.');
      }

      // The object has to be this bot's own and still alive. Anything else is a
      // bot naming somebody else's upload, which is how an id turns into a way
      // to hand a stranger's file to a third person.
      let mediaId: string | null = null;
      if (body.mediaId) {
        const { rows } = await pool.query<{ id: string }>(
          `SELECT id FROM media_objects
            WHERE id = $1 AND owner_account_id = $2 AND kind = 'bot_attachment'
              AND expires_at > now()`,
          [body.mediaId, bot.account_id],
        );
        if (rows.length === 0) {
          throw ApiError.notFound('media_not_found', 'No such upload of this bot');
        }
        mediaId = rows[0]!.id;
      }

      // An existing poll has to be this bot's own and still open. Another bot's
      // id is answered like no id at all, so poll ids cannot be walked.
      if (body.pollId !== undefined) {
        const existing = await bots.pollState(bot.account_id, body.pollId);
        if (!existing) throw ApiError.notFound('poll_not_found', 'No such poll of this bot');
        if (existing.closed) {
          throw ApiError.conflict('poll_closed', 'That poll has closed');
        }
      }

      // The poll and the message in one transaction: a message that claims a
      // poll which was never written would be a question nobody can answer.
      const sent = await withTransaction(async (client) => {
        let pollId: number | null = body.pollId ?? null;
        if (body.poll) {
          const { rows: made } = await client.query<{ id: string }>(
            `INSERT INTO bot_polls
               (bot_id, question, options, max_choices, show_results, closes_at)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
            [
              bot.account_id,
              body.poll.question,
              JSON.stringify(body.poll.options),
              body.poll.maxChoices,
              body.poll.showResults,
              body.poll.closesAt ?? null,
            ],
          );
          pollId = Number(made[0]!.id);
        }

        const { rows } = await client.query<{ id: string }>(
          `INSERT INTO bot_messages
             (bot_id, account_id, scope, scope_id, author, body, buttons,
              media_id, media_kind, file_name, poll_id)
           VALUES ($1, $2, $3, $4, 'bot', $5, $6, $7, $8, $9, $10) RETURNING id`,
          [
            bot.account_id,
            body.to,
            body.groupId ? 'group' : 'direct',
            body.groupId ?? null,
            // Beside a poll with no line of its own, the body is empty rather
            // than a copy of the question: the question lives in the poll, and
            // one place is the place it cannot disagree with.
            body.text ?? '',
            JSON.stringify(body.buttons ?? []),
            mediaId,
            // The constraint in migration 040 wants both or neither, so the kind
            // follows the object rather than the request: a `mediaKind` with no
            // `mediaId` is a picture frame around nothing.
            mediaId === null ? null : body.mediaKind ?? 'file',
            mediaId === null ? null : body.fileName ?? null,
            pollId,
          ],
        );
        return { messageId: Number(rows[0]!.id), pollId };
      });
      return sent.pollId === null ? { messageId: sent.messageId } : sent;
    });

    // --- Polls, from the bot's side -------------------------------------------

    /**
     * One poll's tally.
     *
     * The bot sees every count whatever `showResults` says: that switch is about
     * what the *people answering* see, and the bot is told each answer as it
     * arrives in any case.
     */
    app.get('/v1/bot/polls/:pollId', async (request) => {
      const bot = await requireBot(request);
      const params = parse(z.object({ pollId: z.coerce.number().int().min(1) }), request.params);
      const poll = await bots.pollState(bot.account_id, params.pollId);
      if (!poll) throw ApiError.notFound('poll_not_found', 'No such poll of this bot');
      return poll;
    });

    /**
     * Stops a poll taking answers, before its time or when it had none.
     *
     * Final: there is no reopening, because a poll that closes and opens again
     * is one whose result depends on when somebody looked. Closing a closed
     * poll answers the same tally rather than an error, so a retry is harmless.
     */
    app.post('/v1/bot/polls/:pollId/close', async (request) => {
      const bot = await requireBot(request);
      const params = parse(z.object({ pollId: z.coerce.number().int().min(1) }), request.params);
      const { rowCount } = await pool.query(
        `UPDATE bot_polls SET closed_at = now()
          WHERE id = $1 AND bot_id = $2 AND closed_at IS NULL
            -- One that ran out on its own keeps saying so: closed_at is the
            -- record of the bot closing it, not of anybody looking afterwards.
            AND (closes_at IS NULL OR closes_at > now())`,
        [params.pollId, bot.account_id],
      );
      const poll = await bots.pollState(bot.account_id, params.pollId);
      if (!poll) throw ApiError.notFound('poll_not_found', 'No such poll of this bot');
      return { ...poll, alreadyClosed: rowCount === 0 };
    });

    // --- What a bot may do in a group, when an admin has granted it -----------

    /**
     * The right, checked on this call.
     *
     * Never remembered from when the bot was added and never taken from the
     * request: an admin who withdraws a right breaks the bot's *next* action, not
     * the one after it notices. Null membership and no rights are different
     * answers, and the caller is told which.
     */
    async function requireGroupRight(
      botId: string,
      groupId: string,
      right: keyof bots.BotGroupRights,
    ) {
      const rights = await bots.groupRightsOf(botId, groupId);
      if (rights === null) {
        throw ApiError.forbidden('not_in_group', 'This bot is not a member of that group.');
      }
      if (!rights[right]) {
        throw ApiError.forbidden(
          'missing_right',
          'This bot does not have that permission in that group.',
        );
      }
      return rights;
    }

    /**
     * Removes a member, with **may_restrict_members**.
     *
     * Three rules a human admin is not held to, because a bot is a program
     * somebody else runs and a mistake or a compromise in it must not be able to
     * empty a group:
     *
     * * it may not remove an **admin** — a bot that could would be a bot that can
     *   take over a group by removing everybody who could switch it off;
     * * it may not remove **itself**, which is an admin's decision about the
     *   group rather than the bot's about itself;
     * * the promote-the-longest-standing-member rescue that a human removal does
     *   is not needed here, because an admin can never be the one removed.
     *
     * No group key rotation, and that is not an oversight: a group's key seals
     * the name and the description, the bot was never given it, and the messages
     * are per-device Signal ciphertext. Removing a member changes who the
     * *members' devices* will seal to next — which is their decision, made with
     * the member list this route just changed.
     */
    app.post('/v1/bot/group/members/remove', async (request) => {
      const bot = await requireBot(request);
      const body = parse(
        z.object({ groupId: uuidSchema, accountId: uuidSchema }),
        request.body,
      );
      await requireGroupRight(bot.account_id, body.groupId, 'mayRestrictMembers');

      if (body.accountId === bot.account_id) {
        throw ApiError.forbidden('not_itself', 'A bot cannot remove itself from a group.');
      }

      const removed = await withTransaction(async (client) => {
        // Locked, so the role cannot change between the check and the delete: a
        // member who is promoted to admin in that gap must not still be removed.
        const { rows } = await client.query<{ role: string }>(
          'SELECT role FROM group_members WHERE group_id = $1 AND account_id = $2 FOR UPDATE',
          [body.groupId, body.accountId],
        );
        const member = rows[0];
        if (!member) {
          throw ApiError.notFound('member_not_found', 'Not a member of this group');
        }
        if (member.role === 'admin') {
          throw ApiError.forbidden(
            'cannot_remove_admin',
            'A bot cannot remove an admin. Ask an admin to do it.',
          );
        }
        await client.query(
          'DELETE FROM group_members WHERE group_id = $1 AND account_id = $2',
          [body.groupId, body.accountId],
        );
        return true;
      });

      // After the commit: a key request left behind is a request nobody should
      // answer, and clearing it inside the transaction would undo on a rollback.
      await clearKeyRequestsFor('group', body.groupId, body.accountId);
      return { removed };
    });

    /**
     * Renews the group's invite link, with **may_manage_invites**.
     *
     * The same operation an admin has, which is what makes this right worth
     * granting: a moderation bot that notices a link being spammed can close that
     * door immediately rather than at whatever hour an admin reads about it.
     *
     * It does not return the old code, and the new one goes only to the bot that
     * asked. Nothing about the members is disclosed.
     */
    app.post('/v1/bot/group/invite/rotate', async (request) => {
      const bot = await requireBot(request);
      const body = parse(z.object({ groupId: uuidSchema }), request.body);
      await requireGroupRight(bot.account_id, body.groupId, 'mayManageInvites');

      const { rows } = await pool.query<{ invite_code: string }>(
        'UPDATE groups SET invite_code = $2 WHERE id = $1 RETURNING invite_code',
        [body.groupId, randomBytes(9).toString('base64url')],
      );
      if (!rows[0]) throw ApiError.notFound('group_not_found', 'No such group');
      return { inviteCode: rows[0].invite_code };
    });

    /** The members of a group this bot is in, with **may_restrict_members**. */
    app.get('/v1/bot/group/members', async (request) => {
      const bot = await requireBot(request);
      const query = parse(z.object({ groupId: uuidSchema }), request.query);
      // Behind the same right as removing one, not readable by any bot in the
      // group: a list of who is in a group is exactly the thing a bot should not
      // get for being present. A bot that may act on members may read them.
      await requireGroupRight(bot.account_id, query.groupId, 'mayRestrictMembers');

      const { rows } = await pool.query<{
        id: string;
        username: string;
        display_name: string | null;
        role: string;
      }>(
        `SELECT a.id, a.username, a.display_name, m.role
           FROM group_members m JOIN accounts a ON a.id = m.account_id
          WHERE m.group_id = $1 AND a.deleted_at IS NULL
          ORDER BY m.added_at ASC`,
        [query.groupId],
      );
      return {
        members: rows.map((row) => ({
          accountId: row.id,
          username: row.username,
          displayName: row.display_name,
          role: row.role,
          // So a bot does not have to find out by being refused.
          removable: row.role !== 'admin' && row.id !== bot.account_id,
        })),
      };
    });

    // --- Writing to a bot, and reading what it said back ----------------------

    /**
     * A person writes to a bot.
     *
     * This is the route that makes a bot a thing you can talk to, and the one
     * that opens the return path: it records the contact, which is what
     * `mayWriteTo` then allows. Until somebody calls this, a bot cannot reach
     * them at all.
     *
     * **The text is plaintext and this server can read it.** That is the whole
     * bargain of the bot path and it is not softened here — the app says so in
     * front of the person before the first message, and `docs/bots.md` says why
     * it cannot be otherwise while a bot is a program reached over HTTP.
     *
     * With `groupId`, the message is one a member's device chose to hand over
     * because it was addressed to this bot. The server checks the sender is in
     * that group and the bot is too; it cannot check what the message says,
     * because the group's own copy is ciphertext it cannot open. The filtering
     * happened on the device that had the plaintext. See migration 037.
     */
    app.post('/v1/bots/:id/messages', requireAuth, async (request, reply) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const body = parse(
        z.object({
          text: z.string().trim().min(1).max(4096),
          groupId: uuidSchema.optional(),
          /**
           * The sending device's own id for this message, so a retry after a
           * dropped connection is answered rather than delivered twice. Opaque
           * here, exactly as `idempotencyKey` is on an ordinary send.
           */
          clientId: z.string().min(8).max(128).optional(),
        }),
        request.body,
      );

      const bot = await bots.byAccountId(params.id);
      if (!bot || bot.disabled_at !== null) {
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }

      if (body.groupId) {
        // Both sides have to be in the group: the person writing, and the bot
        // being written to. Neither is taken on trust from the request.
        await requireGroupMembership(body.groupId, accountId);
        if ((await bots.groupRightsOf(params.id, body.groupId)) === null) {
          throw ApiError.forbidden('not_in_group', 'That bot is not in this group');
        }
      }

      // Writing is what licenses the bot to answer. In a group too: a bot that
      // could write to somebody because they share a group would be a bot that
      // opens conversations, which is the one thing it may not do.
      await bots.noteContact(params.id, accountId);

      const { rows } = await pool.query<{ id: string }>(
        `INSERT INTO bot_messages (bot_id, account_id, scope, scope_id, author, body, client_id)
         VALUES ($1, $2, $3, $4, 'user', $5, $6)
         -- The index is partial, so the predicate has to be repeated here or
         -- Postgres will not match it and refuses the whole statement. A row
         -- with no client id cannot conflict, which is exactly right: a client
         -- that sends no id has not asked for its retries to be deduplicated.
         ON CONFLICT (bot_id, account_id, client_id) WHERE client_id IS NOT NULL DO NOTHING
         RETURNING id`,
        [
          params.id,
          accountId,
          body.groupId ? 'group' : 'direct',
          body.groupId ?? null,
          body.text,
          body.clientId ?? null,
        ],
      );
      reply.code(201);
      // A retry that found the row already there is not an error: the first
      // attempt got through, and saying so is what stops a client sending it a
      // third time.
      return { messageId: rows[0] ? Number(rows[0].id) : null, duplicate: rows.length === 0 };
    });

    /** The conversation with a bot, newest last. */
    /**
     * What somebody sees before they decide to talk to a bot.
     *
     * The description and the published command list, plus whether *this* person
     * has started it and whether they stopped it — the two things the screen needs
     * to know whether to draw a **Start** button or a text field.
     *
     * Open to any signed-in account, because a bot is meant to be opened by a
     * stranger. It says nothing about the operator beyond the bot's own profile,
     * and nothing about anybody else who uses it.
     */
    async function botProfile(botId: string, accountId: string) {
      const bot = await bots.byAccountId(botId);
      if (!bot || bot.disabled_at !== null) {
        // A switched-off bot reads as gone rather than as "exists but off": the
        // owner switched it off, and a screen saying "this bot is disabled" tells
        // whoever is looking something about the owner's decisions.
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }
      const { rows } = await pool.query<{ username: string; display_name: string | null }>(
        'SELECT username, display_name FROM accounts WHERE id = $1',
        [botId],
      );
      const state = await bots.contactState(botId, accountId);
      return {
        id: botId,
        username: rows[0]!.username,
        displayName: rows[0]!.display_name,
        description: bot.description,
        commands: bot.commands,
        isBot: true,
        started: state.started,
        stopped: state.stopped,
      };
    }

    app.get('/v1/bots/by-username/:username', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ username: usernameSchema }), request.params);
      const { rows } = await pool.query<{ id: string }>(
        `SELECT id FROM accounts
          WHERE username = $1 AND deleted_at IS NULL AND is_bot = true`,
        [params.username.toLowerCase()],
      );
      // Exact username only. There is no prefix search and no directory: a
      // browsable list of every bot on a deployment is a list of every operator
      // on it.
      if (rows.length === 0) throw ApiError.notFound('bot_not_found', 'No such bot');
      return botProfile(rows[0]!.id, accountId);
    });

    app.get('/v1/bots/:id/profile', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      return botProfile(params.id, accountId);
    });

    /**
     * **Start.** What licenses a bot to write to somebody.
     *
     * Until this — or a message they typed — a bot cannot reach them at all. It
     * delivers `/start` as an ordinary message, which is how the bot knows to
     * introduce itself; every start does, including one after a stop, because
     * pressing Start is a request to be greeted.
     */
    app.post('/v1/bots/:id/start', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const bot = await bots.byAccountId(params.id);
      if (!bot || bot.disabled_at !== null) {
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }

      await bots.noteContact(params.id, accountId);
      const { rows } = await pool.query<{ id: string }>(
        `INSERT INTO bot_messages (bot_id, account_id, author, body)
         VALUES ($1, $2, 'user', '/start') RETURNING id`,
        [params.id, accountId],
      );
      return { started: true, messageId: Number(rows[0]!.id) };
    });

    /** **Stop.** The bot may no longer write, and nothing further reaches it. */
    app.post('/v1/bots/:id/stop', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      // No existence check on purpose: stopping a bot that has been deleted or
      // switched off has to work, or somebody is left unable to stop the thing
      // they wanted stopped.
      await bots.stopBot(params.id, accountId);
      return { stopped: true };
    });

    app.get('/v1/bots/:id/messages', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const query = parse(
        z.object({
          limit: z.coerce.number().int().min(1).max(200).default(50),
          /** Everything after this id, for a client catching up. */
          after: z.coerce.number().int().min(0).default(0),
        }),
        request.query,
      );

      const { rows } = await pool.query(
        `SELECT m.id, m.author, m.body, m.scope, m.scope_id, m.created_at, m.buttons,
                m.media_id, m.media_kind, m.file_name, m.poll_id,
                p.question AS poll_question, p.options AS poll_options,
                p.max_choices AS poll_max_choices, p.show_results AS poll_show_results,
                p.closes_at AS poll_closes_at,
                (p.closed_at IS NOT NULL OR (p.closes_at IS NOT NULL AND p.closes_at <= now()))
                  AS poll_closed,
                -- This person's own answer. Per poll, so the same poll sent
                -- twice shows the same answer under both.
                COALESCE(
                  (SELECT array_agg(v.option_index ORDER BY v.option_index)
                     FROM bot_poll_votes v
                    WHERE v.poll_id = m.poll_id AND v.account_id = $2),
                  '{}'
                ) AS poll_mine,
                (SELECT byte_size FROM media_objects o WHERE o.id = m.media_id) AS byte_size,
                -- Which of this message's buttons this person has already
                -- pressed. Sent so the app can show a pressed button as pressed
                -- instead of inviting a second tap that would do nothing.
                COALESCE(
                  (SELECT array_agg(p.button_id)
                     FROM bot_button_presses p
                    WHERE p.message_id = m.id AND p.account_id = $2),
                  '{}'
                ) AS pressed
           FROM bot_messages m
           -- LEFT, so a message without a poll is still a message: an inner
           -- join here would drop every ordinary line from the conversation.
           LEFT JOIN bot_polls p ON p.id = m.poll_id
          WHERE m.bot_id = $1 AND m.account_id = $2 AND m.id > $3
            -- A press is not a line in the conversation. It is delivered to the
            -- bot and the bot answers; drawing it as well would show the person
            -- a bubble they did not write.
            AND m.kind = 'text'
          ORDER BY m.id ASC LIMIT $4`,
        [params.id, accountId, query.after, query.limit],
      );
      // The tally, for the polls whose bot chose to show it and whose reader
      // has answered or can no longer answer. Fetched only for those: a count
      // the route is not going to send is one it has no reason to compute.
      const tallies = new Map<number, { counts: number[]; voters: number }>();
      for (const r of rows) {
        if (r.poll_id === null || !r.poll_show_results) continue;
        const pollId = Number(r.poll_id);
        if (tallies.has(pollId)) continue;
        if ((r.poll_mine as number[]).length === 0 && !r.poll_closed) continue;
        tallies.set(
          pollId,
          await bots.pollTally((r.poll_options as string[]).length, pollId),
        );
      }

      return {
        messages: rows.map((r) => ({
          id: Number(r.id),
          author: r.author as string,
          text: r.body as string,
          scope: r.scope as string,
          scopeId: r.scope_id as string | null,
          sentAt: (r.created_at as Date).toISOString(),
          buttons: r.buttons as Array<{ id: string; label: string }>,
          pressed: r.pressed as string[],
          // Null once the blob has expired and the sweeper has taken it: the
          // message stays in the conversation as a message whose file is gone,
          // which is what `ON DELETE SET NULL` is for.
          mediaId: r.media_id as string | null,
          mediaKind: r.media_kind as string | null,
          fileName: r.file_name as string | null,
          byteSize: r.byte_size === null ? null : Number(r.byte_size),
          poll:
            r.poll_id === null
              ? null
              : {
                  id: Number(r.poll_id),
                  question: r.poll_question as string,
                  options: r.poll_options as string[],
                  maxChoices: r.poll_max_choices as number,
                  showResults: r.poll_show_results as boolean,
                  closesAt: (r.poll_closes_at as Date | null)?.toISOString() ?? null,
                  closed: r.poll_closed as boolean,
                  myVotes: r.poll_mine as number[],
                  // Null, not zeros, when the reader may not see them: zeros
                  // would be a tally, and a wrong one.
                  counts: tallies.get(Number(r.poll_id))?.counts ?? null,
                  voters: tallies.get(Number(r.poll_id))?.voters ?? null,
                },
        })),
        // What to pass as `after` next time. Null when there is no more.
        nextAfter: rows.length === query.limit ? Number(rows[rows.length - 1]!.id) : null,
      };
    });

    /**
     * Presses a button under a bot's message.
     *
     * The three things the requirement asks to be unambiguous are each checked
     * against the database rather than taken from the request:
     *
     * * **which bot** — the message row names it, and the route refuses a message
     *   that belongs to a different bot than the one in the path;
     * * **which message** — the button has to be one this message actually
     *   carries. A button id that is not in that row's `buttons` is refused, so a
     *   caller cannot invent an action by naming one;
     * * **which person** — a direct message is only pressable by the person it
     *   was addressed to; in a group, by a member of that group. Nobody can press
     *   a button on somebody else's behalf, and the bot is told who pressed.
     *
     * And once. The press row and the delivery row are written in one
     * transaction, so a double tap, a retry and a replay all lose the race on the
     * primary key and are answered `already: true` with nothing delivered.
     */
    app.post('/v1/bots/:id/messages/:messageId/press', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(
        z.object({ id: uuidSchema, messageId: z.coerce.number().int().min(1) }),
        request.params,
      );
      const body = parse(z.object({ buttonId: z.string().min(1).max(64) }), request.body);

      const bot = await bots.byAccountId(params.id);
      if (!bot || bot.disabled_at !== null) {
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }

      const { rows: messages } = await pool.query<{
        account_id: string;
        scope: string;
        scope_id: string | null;
        author: string;
        buttons: Array<{ id: string; label: string }>;
      }>(
        `SELECT account_id, scope, scope_id, author, buttons FROM bot_messages
          WHERE id = $1 AND bot_id = $2`,
        [params.messageId, params.id],
      );
      const message = messages[0];
      // One 404 for "no such message" and "not this bot's message": telling them
      // apart would let somebody walk the id space of another bot's messages.
      if (!message || message.author !== 'bot') {
        throw ApiError.notFound('message_not_found', 'No such message from this bot');
      }

      if (!message.buttons.some((button) => button.id === body.buttonId)) {
        throw ApiError.badRequest('no_such_button', 'That message has no such button');
      }

      if (message.scope === 'group' && message.scope_id !== null) {
        // A button under a message in a group is pressable by the group, not only
        // by whoever the bot happened to address it to.
        await requireGroupMembership(message.scope_id, accountId);
      } else if (message.account_id !== accountId) {
        throw ApiError.forbidden('not_yours', 'That message was not addressed to you');
      }

      // A person who has stopped or blocked the bot has withdrawn the licence to
      // be answered. A button they pressed afterwards must not be the way back
      // in — checked here rather than left to the send, so nothing is delivered.
      if (!(await bots.mayWriteTo(params.id, accountId))) {
        throw ApiError.forbidden('not_contacted', 'Start this bot before using it');
      }

      const delivered = await withTransaction(async (client) => {
        const press = await client.query(
          `INSERT INTO bot_button_presses (message_id, account_id, button_id)
           VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
          [params.messageId, accountId, body.buttonId],
        );
        // Already pressed. Nothing is written and nothing is delivered, which is
        // what stops a second tap causing a second booking.
        if (press.rowCount === 0) return null;

        const { rows } = await client.query<{ id: string }>(
          `INSERT INTO bot_messages
             (bot_id, account_id, scope, scope_id, author, body, kind, pressed_message_id)
           VALUES ($1, $2, $3, $4, 'user', $5, 'button', $6) RETURNING id`,
          [
            params.id,
            accountId,
            message.scope,
            message.scope_id,
            body.buttonId,
            params.messageId,
          ],
        );
        return Number(rows[0]!.id);
      });

      return { pressed: true, already: delivered === null };
    });

    /**
     * Answers a poll a bot sent, or changes or takes back an answer.
     *
     * The whole answer, not one more vote: the list given *is* the answer from
     * now on, exactly as for a channel poll, because changing a single choice
     * otherwise takes two calls with a moment between them where the person has
     * answered twice or not at all. An empty list takes the answer back.
     *
     * Who may answer is who the message was addressed to, and nobody else —
     * including in a group. A bot's message is only ever shown to its addressee,
     * and a vote from somebody who could not see the question would be a number
     * in the bot's tally that nobody can account for.
     *
     * Each change reaches the bot once, in order with everything else the person
     * did; answering the same thing again changes nothing and delivers nothing,
     * so a double tap is not two votes.
     */
    app.put('/v1/bots/:id/messages/:messageId/vote', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(
        z.object({ id: uuidSchema, messageId: z.coerce.number().int().min(1) }),
        request.params,
      );
      const body = parse(
        z.object({
          options: z
            .array(z.number().int().min(0).max(bots.BOT_LIMITS.maxPollOptions - 1))
            .max(bots.BOT_LIMITS.maxPollOptions),
        }),
        request.body,
      );

      const bot = await bots.byAccountId(params.id);
      if (!bot || bot.disabled_at !== null) {
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }

      const { rows: messages } = await pool.query<{
        account_id: string;
        scope: string;
        scope_id: string | null;
        author: string;
        poll_id: string | null;
      }>(
        `SELECT account_id, scope, scope_id, author, poll_id FROM bot_messages
          WHERE id = $1 AND bot_id = $2`,
        [params.messageId, params.id],
      );
      const message = messages[0];
      // The same one 404 as a press, for the same reason.
      if (!message || message.author !== 'bot') {
        throw ApiError.notFound('message_not_found', 'No such message from this bot');
      }
      if (message.poll_id === null) {
        throw ApiError.badRequest('no_poll', 'That message is not a poll');
      }
      if (message.account_id !== accountId) {
        throw ApiError.forbidden('not_yours', 'That message was not addressed to you');
      }
      // Stopping a bot withdraws the answers too, as it withdraws presses.
      if (!(await bots.mayWriteTo(params.id, accountId))) {
        throw ApiError.forbidden('not_contacted', 'Start this bot before using it');
      }

      const chosen = [...new Set(body.options)].sort((a, b) => a - b);
      if (chosen.length !== body.options.length) {
        throw ApiError.badRequest('duplicate_option', 'An answer was picked twice');
      }
      const pollId = Number(message.poll_id);

      const result = await withTransaction(async (client) => {
        // The poll row, locked: two answers from the same person racing each
        // other are put one after the other, so the second sees the first and
        // a double tap cannot become two deliveries.
        const { rows: polls } = await client.query<{
          options: string[];
          max_choices: number;
          show_results: boolean;
          closed: boolean;
        }>(
          `SELECT options, max_choices, show_results,
                  (closed_at IS NOT NULL OR (closes_at IS NOT NULL AND closes_at <= now())) AS closed
             FROM bot_polls WHERE id = $1 AND bot_id = $2 FOR UPDATE`,
          [pollId, params.id],
        );
        const poll = polls[0];
        if (!poll) throw ApiError.notFound('poll_not_found', 'No such poll');
        if (poll.closed) throw ApiError.conflict('poll_closed', 'This poll has closed');
        if (chosen.some((index) => index >= poll.options.length)) {
          throw ApiError.badRequest('no_such_option', 'That poll has no such answer');
        }
        if (chosen.length > poll.max_choices) {
          throw ApiError.badRequest(
            'too_many_options',
            `This poll takes ${poll.max_choices} answer${poll.max_choices === 1 ? '' : 's'}`,
          );
        }

        const { rows: before } = await client.query<{ option_index: number }>(
          `SELECT option_index FROM bot_poll_votes
            WHERE poll_id = $1 AND account_id = $2 ORDER BY option_index`,
          [pollId, accountId],
        );
        const previous = before.map((r) => r.option_index);
        const changed =
          previous.length !== chosen.length || previous.some((v, i) => v !== chosen[i]);

        if (changed) {
          await client.query(
            'DELETE FROM bot_poll_votes WHERE poll_id = $1 AND account_id = $2',
            [pollId, accountId],
          );
          for (const index of chosen) {
            await client.query(
              `INSERT INTO bot_poll_votes (poll_id, account_id, option_index)
               VALUES ($1, $2, $3)`,
              [pollId, accountId, index],
            );
          }
          // The delivery row, in the same transaction as the answer it reports:
          // an answer the bot was never told about, or told about but never
          // recorded, would be two different polls.
          await client.query(
            `INSERT INTO bot_messages
               (bot_id, account_id, scope, scope_id, author, body, kind, poll_id)
             VALUES ($1, $2, $3, $4, 'user', $5, 'vote', $6)`,
            [
              params.id,
              accountId,
              message.scope,
              message.scope_id,
              JSON.stringify(chosen),
              pollId,
            ],
          );
        }

        // What the person may now see, under the same rule as the conversation.
        const visible = poll.show_results && chosen.length > 0;
        const tally = visible
          ? await bots.pollTally(poll.options.length, pollId, client)
          : null;
        return {
          changed,
          myVotes: chosen,
          counts: tally?.counts ?? null,
          voters: tally?.voters ?? null,
        };
      });

      return result;
    });

    // --- Where to post this bot's updates -------------------------------------

    /**
     * Registers a webhook, and answers with its signing secret **once**.
     *
     * Authenticated with the bot's token, because this is the bot operator's own
     * configuration rather than something the owner does from a phone.
     *
     * The URL is checked twice: here, for shape — HTTPS, no credentials, not a
     * private address — and again before every delivery, because a name that
     * resolves publicly today may not tomorrow. `util/outbound.ts` does both and
     * is the same guard the push endpoints use.
     */
    app.put('/v1/bot/webhook', async (request) => {
      const bot = await requireBot(request);
      const body = parse(z.object({ url: z.string().min(8).max(2048) }), request.body);

      const url = parsePushEndpoint(body.url, { code: 'invalid_webhook' });
      try {
        await assertResolvesPublicly(url);
      } catch {
        // Deliberately not echoing what it resolved to. That is a probe of the
        // server's own network, and answering it in detail turns this route
        // into a scanner.
        throw ApiError.badRequest('invalid_webhook', 'That URL must resolve to a public address');
      }

      const secret = await webhooks.setWebhook(bot.account_id, url.toString());
      return {
        url: url.toString(),
        // Shown once. There is no route that reads it back: a secret that can be
        // fetched again is a secret with two places to leak from.
        secret: secret.toString('hex'),
        note: 'Store this now. It is shown once and cannot be read back.',
      };
    });

    /** What the webhook is doing, without the secret. */
    app.get('/v1/bot/webhook', async (request) => {
      const bot = await requireBot(request);
      const status = await webhooks.webhookStatus(bot.account_id);
      return status ?? { url: null };
    });

    /** Removes it. Updates then wait for a poller, and nothing is lost. */
    app.delete('/v1/bot/webhook', async (request) => {
      const bot = await requireBot(request);
      await webhooks.clearWebhook(bot.account_id);
      return { removed: true };
    });

    // --- A group's bots, managed by its admins --------------------------------

    /**
     * The bots in a group.
     *
     * Every member may read it, not only admins. A device has to know which
     * bots are present in order to decide what to forward to them — see
     * migration 037 — and somebody writing in a group is entitled to know who
     * ends up receiving it.
     */
    app.get('/v1/groups/:id/bots', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      await requireGroupMembership(params.id, accountId);
      return { bots: await bots.botsInGroup(params.id) };
    });

    /**
     * Adds a bot to a group, with **no rights at all**.
     *
     * Rights are a second call. That is not an extra step for its own sake: a
     * route that took rights here would be a route somebody calls with all of
     * them set, and the screen that explains what a bot can read would become a
     * formality somebody scrolled past.
     */
    app.post('/v1/groups/:id/bots', requireAuth, async (request, reply) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const body = parse(z.object({ botId: uuidSchema }), request.body);
      await requireGroupMembership(params.id, accountId, true);

      const bot = await bots.byAccountId(body.botId);
      if (!bot || bot.disabled_at !== null) {
        throw ApiError.notFound('bot_not_found', 'No such bot');
      }

      await pool.query(
        `INSERT INTO bot_group_members (bot_id, group_id, added_by)
         VALUES ($1, $2, $3)
         ON CONFLICT (bot_id, group_id) DO NOTHING`,
        [body.botId, params.id, accountId],
      );
      reply.code(201);
      return { bots: await bots.botsInGroup(params.id) };
    });

    /** Changes what a bot may do in a group. Admins only, one right at a time. */
    app.patch('/v1/groups/:id/bots/:botId', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(
        z.object({ id: uuidSchema, botId: uuidSchema }),
        request.params,
      );
      const body = parse(
        z.object({
          maySend: z.boolean().optional(),
          mayModerate: z.boolean().optional(),
          mayRestrictMembers: z.boolean().optional(),
          mayManageInvites: z.boolean().optional(),
          readsAllMessages: z.boolean().optional(),
        }),
        request.body,
      );
      await requireGroupMembership(params.id, accountId, true);

      /*
       * Deleting other people's messages is not a right this server can grant,
       * and granting it anyway would be the worst kind of permission: one an
       * admin has agreed to and that quietly does nothing.
       *
       * A deletion in Privio is an encrypted protocol message to every member's
       * devices, and the rule the devices enforce is that **only the author may
       * delete for everyone** — a protocol that let anyone delete anyone's
       * messages would be a way to erase a conversation you were losing. A bot
       * holds no group key and no Signal session with the members, so it cannot
       * send that message at all, and no server-side flag changes that.
       *
       * So the right is refused here rather than stored. Withdrawing it stays
       * allowed, because a group that was granted it before this check existed
       * has to be able to tidy up. When a bot can be a cryptographic endpoint of
       * its own — `docs/bots.md`, "What it would take to do better" — this is the
       * check to revisit, and not before.
       */
      if (body.mayModerate === true) {
        throw ApiError.badRequest(
          'right_not_available',
          'Deleting other people\'s messages is not something a bot can do in Privio. '
            + 'Only the author of a message can delete it for everyone.',
        );
      }

      // Each column named on its own, and only the ones the caller sent. There
      // is deliberately no "grant everything" shape: a bot ends up with every
      // admin right when one call can give it every admin right.
      const columns: Record<string, boolean | undefined> = {
        may_send: body.maySend,
        may_moderate: body.mayModerate,
        may_restrict_members: body.mayRestrictMembers,
        may_manage_invites: body.mayManageInvites,
        reads_all_messages: body.readsAllMessages,
      };
      const set = Object.entries(columns).filter(([, value]) => value !== undefined);
      if (set.length === 0) {
        throw ApiError.badRequest('nothing_to_update', 'No rights were given');
      }

      const assignments = set.map(([column], index) => `${column} = $${index + 3}`);
      const { rowCount } = await pool.query(
        `UPDATE bot_group_members SET ${assignments.join(', ')}
          WHERE bot_id = $1 AND group_id = $2`,
        [params.botId, params.id, ...set.map(([, value]) => value)],
      );
      if (!rowCount) throw ApiError.notFound('bot_not_in_group', 'That bot is not in this group');
      return { bots: await bots.botsInGroup(params.id) };
    });

    /**
     * Takes a bot out of a group.
     *
     * Delivery stops because the members' devices stop forwarding — they read
     * this list before they send — and because every route that acts on the
     * bot's behalf asks `groupRightsOf`, which now answers null.
     *
     * **No group key is rotated, and none needs to be.** A bot never held one: a
     * group's messages are Signal ciphertext addressed to member devices, and
     * the group key seals only the name and description, which are not given to
     * bots either. There is nothing in the bot's hands to invalidate. What it
     * already received, it keeps — that is a copy on somebody else's server and
     * no amount of re-keying here reaches it, which the app says rather than
     * implying otherwise.
     */
    app.delete('/v1/groups/:id/bots/:botId', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(
        z.object({ id: uuidSchema, botId: uuidSchema }),
        request.params,
      );
      await requireGroupMembership(params.id, accountId, true);
      await pool.query(
        'DELETE FROM bot_group_members WHERE bot_id = $1 AND group_id = $2',
        [params.botId, params.id],
      );
      return { bots: await bots.botsInGroup(params.id) };
    });
  };
}

export default botRoutes;
