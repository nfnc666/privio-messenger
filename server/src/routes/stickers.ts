import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import * as packs from '../services/stickers.js';
import { ApiError } from '../util/errors.js';
import { parse, uuidSchema } from '../util/validate.js';

/**
 * Sticker and custom-emoji packs.
 *
 * Every route here answers to one rule: **a pack is its owner's until they
 * share it, and a share is a code they can take back.** There is no listing of
 * other people's packs, no search, and no id that is a capability on its own —
 * reaching somebody else's pack takes a live share code or an existing install,
 * and revoking the code kills the first without confiscating the second.
 */

const titleSchema = z.string().trim().min(1).max(64);
const emojiSchema = z.string().trim().min(1).max(16);

const stickerRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = {
    preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
  };

  /** Everything this account owns, plus everything it has installed. */
  app.get('/v1/sticker-packs', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows: owned } = await pool.query<packs.PackRow>(
      `SELECT * FROM sticker_packs
        WHERE owner_account_id = $1 AND deleted_at IS NULL
        ORDER BY created_at`,
      [accountId],
    );
    const installed = await packs.installedFor(accountId);
    const installedIds = new Set(installed.map((pack) => pack.id));

    const seen = new Set<string>();
    const all: packs.PackRow[] = [];
    for (const pack of [...owned, ...installed]) {
      if (seen.has(pack.id)) continue;
      seen.add(pack.id);
      all.push(pack);
    }

    return {
      packs: await Promise.all(
        all.map(async (pack) =>
          packs.packJson(pack, await packs.itemsOf(pack.id), installedIds.has(pack.id)),
        ),
      ),
    };
  });

  app.post('/v1/sticker-packs', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const body = parse(
      z.object({ title: titleSchema, kind: z.enum(['sticker', 'emoji']) }),
      request.body,
    );

    const { rows: count } = await pool.query<{ n: string }>(
      'SELECT count(*) AS n FROM sticker_packs WHERE owner_account_id = $1 AND deleted_at IS NULL',
      [accountId],
    );
    if (Number(count[0]!.n) >= packs.PACK_LIMITS.packsPerAccount) {
      throw ApiError.badRequest('too_many_packs', 'You have reached the limit on packs.');
    }

    const { rows } = await pool.query<packs.PackRow>(
      `INSERT INTO sticker_packs (owner_account_id, kind, title)
       VALUES ($1, $2, $3) RETURNING *`,
      [accountId, body.kind, body.title],
    );
    reply.code(201);
    return packs.packJson(rows[0]!, []);
  });

  /**
   * One pack, as this viewer may see it.
   *
   * The share code travels as a query parameter because that is what a link
   * carries. An owner needs none; anybody else needs a live one or an install.
   */
  app.get('/v1/sticker-packs/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const query = parse(z.object({ code: z.string().max(64).optional() }), request.query);

    const found = await packs.findForViewer(params.id, accountId, query.code ?? null);
    if (!found) throw ApiError.notFound('pack_not_found', 'No such pack');

    const { rowCount } = await pool.query(
      'SELECT 1 FROM sticker_installs WHERE account_id = $1 AND pack_id = $2',
      [accountId, params.id],
    );
    const json = packs.packJson(found.pack, await packs.itemsOf(params.id), rowCount === 1);
    // The code is the owner's to hand out. Returning it to a viewer would let
    // somebody who was given a link pass on a link the owner thinks only they
    // have — the same capability, one hop further from the person who granted
    // it. They can still forward the URL they were sent; what they cannot do is
    // read it back out of the API.
    return found.isOwner ? json : { ...json, shareCode: null };
  });

  /** Preview by code alone, for the screen shown before installing. */
  app.get('/v1/sticker-packs/by-code/:code', requireAuth, async (request) => {
    const params = parse(z.object({ code: z.string().min(8).max(64) }), request.params);
    const pack = await packs.findByShareCode(params.code);
    if (!pack) throw ApiError.notFound('pack_not_found', 'That link is no longer valid');
    return { ...packs.packJson(pack, await packs.itemsOf(pack.id)), shareCode: null };
  });

  app.patch('/v1/sticker-packs/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ title: titleSchema }), request.body);

    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    const { rows } = await pool.query<packs.PackRow>(
      'UPDATE sticker_packs SET title = $2, updated_at = now() WHERE id = $1 RETURNING *',
      [params.id, body.title],
    );
    return packs.packJson(rows[0]!, await packs.itemsOf(params.id));
  });

  /**
   * Deletes a pack.
   *
   * Soft, and deliberately: messages already sent carry the pack id, and a tap
   * on one of those stickers should say "this pack is gone" rather than fail to
   * resolve. The images stop being downloadable at the same moment, because
   * `mayDownload` joins through `deleted_at IS NULL`.
   */
  app.delete('/v1/sticker-packs/:id', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    await pool.query(
      `UPDATE sticker_packs SET deleted_at = now(), share_code = NULL WHERE id = $1`,
      [params.id],
    );
    return { deleted: true };
  });

  // --- Sharing --------------------------------------------------------------

  app.post('/v1/sticker-packs/:id/share', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    // A fresh code every time, even when one exists. "Share" on a pack that is
    // already shared is how somebody replaces a link they regret sending, and
    // reusing the old code would make that button do nothing.
    const code = packs.newShareCode();
    const { rows } = await pool.query<packs.PackRow>(
      'UPDATE sticker_packs SET share_code = $2, shared_at = now() WHERE id = $1 RETURNING *',
      [params.id, code],
    );
    return packs.packJson(rows[0]!, await packs.itemsOf(params.id));
  });

  app.delete('/v1/sticker-packs/:id/share', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    const { rows } = await pool.query<packs.PackRow>(
      'UPDATE sticker_packs SET share_code = NULL, shared_at = NULL WHERE id = $1 RETURNING *',
      [params.id],
    );
    return packs.packJson(rows[0]!, await packs.itemsOf(params.id));
  });

  // --- Items ----------------------------------------------------------------

  app.post('/v1/sticker-packs/:id/items', requireAuth, async (request, reply) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(
      z.object({ mediaId: uuidSchema, emoji: emojiSchema }),
      request.body,
    );
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    // The upload has to be this account's own, and of the sticker kind — which
    // is the kind whose bytes were checked on the way in. Without this, a pack
    // could point at somebody else's object id, or at an attachment nobody
    // verified was an image at all.
    const { rows: media } = await pool.query<{ id: string }>(
      `SELECT id FROM media_objects
        WHERE id = $1 AND owner_account_id = $2 AND kind = 'sticker'`,
      [body.mediaId, accountId],
    );
    if (!media[0]) throw ApiError.notFound('media_not_found', 'No such sticker upload of yours');

    const { rows: count } = await pool.query<{ n: string }>(
      'SELECT count(*) AS n FROM sticker_items WHERE pack_id = $1',
      [params.id],
    );
    if (Number(count[0]!.n) >= packs.PACK_LIMITS.itemsPerPack) {
      throw ApiError.badRequest('pack_full', 'This pack is full.');
    }

    const { rows } = await pool.query<packs.ItemRow>(
      `INSERT INTO sticker_items (pack_id, media_id, emoji, position)
       VALUES ($1, $2, $3,
               COALESCE((SELECT max(position) + 1 FROM sticker_items WHERE pack_id = $1), 0))
       RETURNING *`,
      [params.id, body.mediaId, body.emoji],
    );
    await pool.query('UPDATE sticker_packs SET updated_at = now() WHERE id = $1', [params.id]);
    reply.code(201);
    return { id: rows[0]!.id, mediaId: rows[0]!.media_id, emoji: rows[0]!.emoji, position: rows[0]!.position };
  });

  app.patch('/v1/sticker-packs/:id/items/:itemId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, itemId: uuidSchema }), request.params);
    const body = parse(z.object({ emoji: emojiSchema }), request.body);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    const { rows } = await pool.query<packs.ItemRow>(
      'UPDATE sticker_items SET emoji = $3 WHERE id = $2 AND pack_id = $1 RETURNING *',
      [params.id, params.itemId, body.emoji],
    );
    if (!rows[0]) throw ApiError.notFound('item_not_found', 'No such sticker in this pack');
    return { id: rows[0].id, mediaId: rows[0].media_id, emoji: rows[0].emoji, position: rows[0].position };
  });

  app.delete('/v1/sticker-packs/:id/items/:itemId', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema, itemId: uuidSchema }), request.params);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    await withTransaction(async (client) => {
      const { rows } = await client.query<{ media_id: string }>(
        'DELETE FROM sticker_items WHERE id = $2 AND pack_id = $1 RETURNING media_id',
        [params.id, params.itemId],
      );
      // The image goes with it: nothing else points at it, and a sticker
      // removed from the only pack holding it is nobody's picture.
      if (rows[0]) {
        await client.query('UPDATE media_objects SET expires_at = now() WHERE id = $1', [
          rows[0].media_id,
        ]);
      }
      await client.query('UPDATE sticker_packs SET updated_at = now() WHERE id = $1', [params.id]);
    });
    return { deleted: true };
  });

  app.put('/v1/sticker-packs/:id/order', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ itemIds: z.array(uuidSchema).max(500) }), request.body);
    const owned = await packs.findOwned(params.id, accountId);
    if (!owned) throw ApiError.notFound('pack_not_found', 'No such pack of yours');

    await packs.reorder(params.id, body.itemIds);
    return packs.packJson(owned, await packs.itemsOf(params.id), true);
  });

  // --- Installing -----------------------------------------------------------

  app.post('/v1/sticker-packs/:id/install', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    const body = parse(z.object({ code: z.string().max(64).optional() }), request.body ?? {});

    // The same visibility question as a read: installing is not a way round it.
    const found = await packs.findForViewer(params.id, accountId, body.code ?? null);
    if (!found) throw ApiError.notFound('pack_not_found', 'That link is no longer valid');

    await pool.query(
      `INSERT INTO sticker_installs (account_id, pack_id, position)
       VALUES ($1, $2, COALESCE((SELECT max(position) + 1 FROM sticker_installs WHERE account_id = $1), 0))
       ON CONFLICT (account_id, pack_id) DO NOTHING`,
      [accountId, params.id],
    );
    return packs.packJson(found.pack, await packs.itemsOf(params.id), true);
  });

  app.delete('/v1/sticker-packs/:id/install', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ id: uuidSchema }), request.params);
    await pool.query('DELETE FROM sticker_installs WHERE account_id = $1 AND pack_id = $2', [
      accountId,
      params.id,
    ]);
    return { installed: false };
  });

  // --- Favourites and recents ----------------------------------------------

  app.get('/v1/sticker-uses', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const { rows } = await pool.query<{
      item_id: string;
      pack_id: string;
      media_id: string;
      emoji: string;
      favourite: boolean;
      used_at: Date;
    }>(
      `SELECT u.item_id, i.pack_id, i.media_id, i.emoji, u.favourite, u.used_at
         FROM sticker_uses u
         JOIN sticker_items i ON i.id = u.item_id
         JOIN sticker_packs p ON p.id = i.pack_id
        WHERE u.account_id = $1 AND p.deleted_at IS NULL
        ORDER BY u.used_at DESC
        LIMIT 120`,
      [accountId],
    );
    return {
      uses: rows.map((row) => ({
        itemId: row.item_id,
        packId: row.pack_id,
        mediaId: row.media_id,
        emoji: row.emoji,
        favourite: row.favourite,
        usedAt: row.used_at.toISOString(),
      })),
    };
  });

  app.post('/v1/sticker-uses', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const body = parse(z.object({ itemIds: z.array(uuidSchema).min(1).max(50) }), request.body);
    await packs.noteUsed(accountId, body.itemIds);
    return { recorded: body.itemIds.length };
  });

  app.put('/v1/sticker-uses/:itemId/favourite', requireAuth, async (request) => {
    const { accountId } = auth(request);
    const params = parse(z.object({ itemId: uuidSchema }), request.params);
    const body = parse(z.object({ favourite: z.boolean() }), request.body);

    // Only an item this account can actually reach. Without the join, any uuid
    // would become a row in somebody's favourites.
    const { rowCount } = await pool.query(
      `SELECT 1 FROM sticker_items i
         JOIN sticker_packs p ON p.id = i.pack_id
        WHERE i.id = $1 AND p.deleted_at IS NULL
          AND (p.owner_account_id = $2
               OR EXISTS (SELECT 1 FROM sticker_installs s
                           WHERE s.pack_id = p.id AND s.account_id = $2))`,
      [params.itemId, accountId],
    );
    if (rowCount !== 1) throw ApiError.notFound('item_not_found', 'No such sticker');

    await pool.query(
      `INSERT INTO sticker_uses (account_id, item_id, favourite)
       VALUES ($1, $2, $3)
       ON CONFLICT (account_id, item_id) DO UPDATE SET favourite = $3`,
      [accountId, params.itemId, body.favourite],
    );
    return { favourite: body.favourite };
  });
};

export default stickerRoutes;
