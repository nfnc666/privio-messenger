import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import * as bots from '../services/bots.js';
import * as assistant from '../services/botcreator.js';
import { cleanDisplayName, isTooLong } from '../services/display_name.js';
import { ApiError } from '../util/errors.js';
import { requireGroupMembership } from '../services/group_membership.js';
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

/** Pulls the bearer token off a bot request. Never logged, anywhere. */
function botToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

const botRoutes: FastifyPluginAsync = async (app) => {
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

  app.post('/v1/bot/send', async (request) => {
    const bot = await requireBot(request);
    const body = parse(
      z.object({
        to: uuidSchema,
        text: z.string().trim().min(1).max(4096),
        /**
         * The group this is a reply in, when it is one.
         *
         * Present or absent rather than a separate route, because everything
         * else about the send is identical and two routes would be two places
         * to forget the rate limit. What differs is which permission is
         * checked, and that is decided below.
         */
        groupId: uuidSchema.optional(),
      }),
      request.body,
    );

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

    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO bot_messages (bot_id, account_id, scope, scope_id, author, body)
       VALUES ($1, $2, $3, $4, 'bot', $5) RETURNING id`,
      [
        bot.account_id,
        body.to,
        body.groupId ? 'group' : 'direct',
        body.groupId ?? null,
        body.text,
      ],
    );
    return { messageId: Number(rows[0]!.id) };
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
      `SELECT id, author, body, scope, scope_id, created_at
         FROM bot_messages
        WHERE bot_id = $1 AND account_id = $2 AND id > $3
        ORDER BY id ASC LIMIT $4`,
      [params.id, accountId, query.after, query.limit],
    );
    return {
      messages: rows.map((r) => ({
        id: Number(r.id),
        author: r.author as string,
        text: r.body as string,
        scope: r.scope as string,
        scopeId: r.scope_id as string | null,
        sentAt: (r.created_at as Date).toISOString(),
      })),
      // What to pass as `after` next time. Null when there is no more.
      nextAfter: rows.length === query.limit ? Number(rows[rows.length - 1]!.id) : null,
    };
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

export default botRoutes;
