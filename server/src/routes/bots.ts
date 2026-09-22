import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import * as bots from '../services/bots.js';
import * as assistant from '../services/botcreator.js';
import { cleanDisplayName, isTooLong } from '../services/display_name.js';
import { ApiError } from '../util/errors.js';
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
      z.object({ to: uuidSchema, text: z.string().trim().min(1).max(4096) }),
      request.body,
    );

    // A bot may not open a conversation. The row in `bot_contacts` is the
    // record of the person having written first, and blocking removes it.
    if (!(await bots.mayWriteTo(bot.account_id, body.to))) {
      throw ApiError.forbidden(
        'not_contacted',
        'This bot may only reply to people who have written to it.',
      );
    }
    if (await bots.isRateLimited(bot.account_id)) {
      throw ApiError.tooManyRequests('rate_limited', 'This bot is sending too fast.');
    }

    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO bot_messages (bot_id, account_id, author, body)
       VALUES ($1, $2, 'bot', $3) RETURNING id`,
      [bot.account_id, body.to, body.text],
    );
    return { messageId: Number(rows[0]!.id) };
  });
};

export default botRoutes;
