import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import type { BlobStorage } from '../services/storage.js';
import { ApiError } from '../util/errors.js';
import { checkSticker, STICKER_LIMITS, type ImageRefusal } from '../services/image_header.js';
import { parse, uuidSchema } from '../util/validate.js';

/**
 * Attachments are uploaded already encrypted: the client picks a random key,
 * seals the file with it, and sends that key inside the E2EE message. The
 * server holds ciphertext plus a length.
 *
 * Downloading is a capability, not a recipient check. The server cannot know
 * who a message went to without being told, and telling it would hand it the
 * one piece of metadata this design refuses to hold — so the uploader gets an
 * unguessable token, carries it inside the sealed payload next to the media
 * key, and whoever can open the message can fetch the blob.
 *
 * The id used to be that capability on its own. It is 122 random bits, so it
 * was not guessable — but it is also the primary key, sitting in the clear
 * beside the ciphertext, which makes a read of this table a set of download
 * capabilities for everything in it. Only the token's hash is stored now, for
 * the same reason a password's is.
 *
 * Avatars are the exception and are marked as such: their id is deliberately
 * published to contacts, so a token would be published with it and buy
 * nothing. They are authorised by the contact list instead.
 */
interface MediaRow {
  id: string;
  storage_key: string;
  byte_size: string | number;
  kind: string;
  owner_account_id: string;
  download_token_hash: Buffer | null;
}

const TOKEN_HEADER = 'x-privio-media-token';

/**
 * The shortest life a caller may ask for a blob, whatever its message's timer.
 *
 * An hour, because the deletion that matters is the one the devices do and this
 * is only about not keeping ciphertext longer than it can be of use. A
 * recipient whose phone was off for the last five minutes still has to be able
 * to fetch the photo before their own copy of the timer starts.
 */
const MIN_MEDIA_TTL_SECONDS = 3600;

function hash(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

/**
 * Whether this caller may have these bytes.
 *
 * The uploader always may — it is their own upload, and a device restoring its
 * own history should not need the token back. Everyone else needs the
 * capability for an attachment, or the owner in their contact list for an
 * avatar.
 */
async function mayDownload(
  object: MediaRow,
  accountId: string,
  headers: Record<string, unknown>,
): Promise<boolean> {
  if (object.owner_account_id === accountId) return true;

  // A channel's picture, which is not sealed.
  //
  // A **public** channel's is meant to be seen by people who are not in it: it
  // is on the invite page, it is what a messenger draws in a link preview, and
  // it is how somebody picks the channel out of search results. Its title,
  // description and handle are already plaintext for the same reason.
  //
  // A **private** channel's is not published. It used to be encrypted; now it
  // is withheld instead — only members get it. That is a weaker promise than
  // encryption and it is the one being made: the posts stay end-to-end
  // encrypted, the picture on the door does not.
  //
  // An object of this kind that no channel points at is nobody's picture, so
  // nobody but its uploader may have it — that is the `false` at the end, and
  // it stops an id from being a download before it has been attached.
  if (object.kind === 'channel_avatar') {
    const { rows } = await pool.query<{ visibility: string }>(
      `SELECT c.visibility FROM channels c
        WHERE c.avatar_media_id = $1 AND c.deleted_at IS NULL
          AND (c.visibility = 'public'
               OR EXISTS (SELECT 1 FROM channel_members m
                           WHERE m.channel_id = c.id AND m.account_id = $2))
        LIMIT 1`,
      [object.id, accountId],
    );
    return rows.length > 0;
  }

  // A sticker's **picture** is downloadable by any signed-in account that can
  // name its id. The id is the capability.
  //
  // This is deliberately wider than "the pack's owner and whoever installed
  // it", and the reason is the thing stickers are for. A sticker is sent to
  // people, and almost nobody you send one to has installed the pack it came
  // from. Under the narrower rule the recipient's client fetched, got a 404,
  // and drew the fallback character — so sending a sticker to anyone outside
  // your own pack's audience did not work at all.
  //
  // What that costs, stated plainly rather than left to be discovered: a
  // sticker picture is not private. It was never encrypted — see
  // `docs/stickers.md` — and now anybody holding its id can fetch it. The id
  // is a random uuid that travels only inside sealed envelopes, so the server
  // still never learns who was sent one, and it cannot be guessed; but a
  // recipient can pass it on, exactly as they could pass on the picture.
  //
  // Two things this does **not** open, which is what keeps it narrow enough to
  // be worth having:
  //
  //  - The pack. Its title, its other stickers and installing it all still go
  //    through `findForViewer`, which wants ownership, an install or a live
  //    share code. One sticker's id gets you that sticker.
  //  - An upload nobody has put in a pack. That is still its uploader's alone,
  //    which is what stops an id being a download before it has been attached.
  if (object.kind === 'sticker') {
    if (object.owner_account_id === accountId) return true;
    const { rows } = await pool.query(
      `SELECT 1
         FROM sticker_items i
         JOIN sticker_packs p ON p.id = i.pack_id
        WHERE i.media_id = $1 AND p.deleted_at IS NULL
        LIMIT 1`,
      [object.id],
    );
    return rows.length > 0;
  }

  if (object.kind === 'avatar') {
    const { rows } = await pool.query(
      'SELECT 1 FROM contacts WHERE account_id = $1 AND contact_account_id = $2',
      [accountId, object.owner_account_id],
    );
    return rows.length > 0;
  }

  const presented = headers[TOKEN_HEADER];
  const stored = object.download_token_hash;
  if (typeof presented !== 'string' || stored === null) return false;
  const offered = hash(presented);
  // Constant time, so a wrong token cannot be walked into a right one.
  return offered.length === stored.length && timingSafeEqual(offered, stored);
}

/**
 * Why a sticker upload was refused, in words the app can show.
 *
 * English here and translated on the device, like every other server message:
 * the server cannot know which language the person uploading reads, so what
 * travels is the code and this is the fallback for a client that does not know
 * it yet.
 */
function stickerRefusalMessage(refusal: ImageRefusal): string {
  switch (refusal) {
    case 'not_an_image':
      return 'That file is not a PNG or a WebP image.';
    case 'unsupported_format':
      return 'Animated stickers are not supported yet. Use a static PNG or WebP.';
    case 'too_large':
      return `A sticker must be under ${Math.round(STICKER_LIMITS.maxBytes / 1024)} KB.`;
    case 'dimensions_too_large':
      return `A sticker must be at most ${STICKER_LIMITS.maxEdge}×${STICKER_LIMITS.maxEdge} pixels.`;
    case 'dimensions_too_small':
      return `A sticker must be at least ${STICKER_LIMITS.minEdge}×${STICKER_LIMITS.minEdge} pixels.`;
  }
}

export function mediaRoutes(storage: BlobStorage): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

    app.post(
      '/v1/media',
      { ...requireAuth, bodyLimit: config.MAX_MEDIA_BYTES },
      async (request, reply) => {
        const { accountId } = auth(request);
        const body = request.body;
        if (!Buffer.isBuffer(body) || body.length === 0) {
          throw ApiError.badRequest('empty_body', 'Send the encrypted bytes as application/octet-stream');
        }
        const { kind, expiresInSeconds } = parse(
          z.object({
            kind: z.enum(['attachment', 'avatar', 'channel_avatar', 'sticker']).default('attachment'),
            /**
             * How long this blob is worth keeping, for an attachment to a
             * message that is set to disappear.
             *
             * A shorter life than the default, asked for by the uploader and
             * never longer than it: the picture in a message that vanishes in
             * a minute should not sit in storage for the ordinary retention
             * period. The screen timer alone does not delete anything here,
             * which is the whole point of this parameter.
             *
             * It is a duration, not the message's timer: the client sends
             * enough for the recipient's own clock to run too — see
             * `MEDIA_GRACE_SECONDS` in the app. The floor stops a rounding
             * error or a hostile client from expiring a blob before the
             * message carrying its key has even been fetched.
             */
            expiresInSeconds: z.coerce
              .number()
              .int()
              .min(MIN_MEDIA_TTL_SECONDS)
              .optional(),
          }),
          request.query,
        );
        // A sticker is the one upload whose *contents* are checked, and it is
        // checked here rather than trusted from the client: the type comes from
        // the magic bytes, the dimensions from the header, and the declared
        // content type is not consulted at all. See `services/image_header.ts`.
        //
        // Every other kind stays opaque on purpose — an attachment is
        // ciphertext and the server could not look inside it if it wanted to.
        // A sticker is stored unencrypted because a pack is shared by link with
        // people who hold no key, so this is the one place where looking is
        // both possible and worth doing.
        if (kind === 'sticker') {
          const checked = checkSticker(body);
          if (checked.refusal) {
            throw ApiError.badRequest(checked.refusal, stickerRefusalMessage(checked.refusal));
          }
        }
        // **Before the bytes touch storage.** Checking after would mean writing
        // the blob and then refusing it, which is the cost this limit exists to
        // avoid paying.
        //
        // Counted over what has not expired, so the quota frees itself as
        // attachments age out rather than needing anybody to delete anything.
        // Avatars and stickers count too: they are smaller, but an account that
        // uploaded ten thousand of them would cost exactly as much.
        const { rows: held } = await pool.query<{ used: string }>(
          // Retained objects count too. They occupy exactly as much storage as
          // anything else, and leaving them out would make a Saved area a way
          // to hold an unbounded amount of it: the quota would free itself as
          // the ordinary expiry passed while the bytes stayed.
          `SELECT COALESCE(sum(byte_size), 0)::text AS used
             FROM media_objects
            WHERE owner_account_id = $1
              AND (expires_at > now() OR retained_at IS NOT NULL)`,
          [accountId],
        );
        const used = Number(held[0]?.used ?? 0);
        if (used + body.length > config.MEDIA_QUOTA_BYTES) {
          throw ApiError.payloadTooLarge(
            'media_quota_exceeded',
            'This account is holding as much media as it may. Older attachments free space as they expire.',
          );
        }

        const storageKey = await storage.put(body);
        const defaultTtl = config.MEDIA_TTL_DAYS * 86_400_000;
        // Only ever shorter. An uploader asking for longer is asking for the
        // retention it would have had anyway, and an avatar is not a message
        // attachment: it stays as long as it is somebody's picture.
        const ttl =
          kind === 'attachment' && expiresInSeconds
            ? Math.min(expiresInSeconds * 1000, defaultTtl)
            : defaultTtl;
        // Every kind is uploaded with the ordinary window, including a
        // sticker. An upload is not yet anybody's picture: it becomes one when
        // something points at it, and *that* is where its life is extended —
        // `PUT /v1/accounts/me/avatar`, the channel avatar route and
        // `POST /v1/sticker-packs/:id/items` all promote the object they
        // adopt, and set it back to now() when they let it go. Granting the
        // long life here instead would keep an upload nobody ever attached for
        // a hundred years.
        const expiresAt = new Date(Date.now() + ttl);

        // Handed back once and never stored. Losing it means losing the blob,
        // which is the point: the server keeps nothing that opens it.
        // Only an attachment gets one. The two avatar kinds are authorised by
        // who is asking rather than by what they hold, so a token would be
        // published alongside the id and buy nothing.
        const token = kind === 'attachment' ? randomBytes(32).toString('base64url') : null;
        const { rows } = await pool.query<{ id: string }>(
          `INSERT INTO media_objects
             (owner_account_id, byte_size, storage_key, expires_at, kind, download_token_hash)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
          [accountId, body.length, storageKey, expiresAt, kind, token && hash(token)],
        );
        reply.code(201);
        return {
          id: rows[0]!.id,
          byteSize: body.length,
          expiresAt: expiresAt.toISOString(),
          ...(token === null ? {} : { token }),
        };
      },
    );

    app.get('/v1/media/:id', requireAuth, async (request, reply) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const { rows } = await pool.query<MediaRow>(
        // `retained_at` widens this rather than replacing the expiry test: a
        // saved item is deliberately still readable after the ordinary
        // attachment window, and everything else still is not. Without this
        // the sweep would leave the row alone and the download would 404 —
        // the object kept and unreachable, which is the worst of both.
        `SELECT id, storage_key, byte_size, kind, owner_account_id, download_token_hash
           FROM media_objects
          WHERE id = $1 AND (expires_at > now() OR retained_at IS NOT NULL)`,
        [params.id],
      );
      const object = rows[0];
      // The same answer for "no such object" and "not yours": which of the two
      // it is would itself say whether an id exists.
      if (!object || !(await mayDownload(object, accountId, request.headers))) {
        throw ApiError.notFound('media_not_found', 'No such attachment');
      }
      reply.header('content-type', 'application/octet-stream');
      reply.header('content-length', String(object.byte_size));
      reply.header('cache-control', 'private, no-store');
      return reply.send(storage.open(object.storage_key));
    });

    /**
     * Keep this object past the ordinary attachment retention.
     *
     * For the owner's own Saved area, and **only ever by its owner** — the
     * `owner_account_id` test is in the statement rather than in a check
     * before it, so there is no path that retains somebody else's blob. The
     * answer for "not yours" is the same 404 as for "no such object", because
     * telling the two apart would say whether an id exists.
     *
     * Idempotent: retaining twice is retaining once. A client that saves,
     * loses its answer and retries must not end up with two of anything, and
     * there is nothing here to have two of.
     *
     * The server learns nothing by this. The blob is ciphertext it has no key
     * for, and "retained" says only that its owner asked for it to be kept.
     */
    app.post('/v1/media/:id/retain', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const { rows } = await pool.query<{ retained_at: Date }>(
        `UPDATE media_objects
            SET retained_at = COALESCE(retained_at, now())
          WHERE id = $1 AND owner_account_id = $2
          RETURNING retained_at`,
        [params.id, accountId],
      );
      if (!rows[0]) throw ApiError.notFound('media_not_found', 'No such attachment');
      return { retained: true, retainedAt: rows[0].retained_at.toISOString() };
    });

    /**
     * Let it go back to the ordinary retention.
     *
     * What a deleted saved entry does. Deliberately not a delete: the same
     * blob may still be the attachment of an ordinary message somebody sent,
     * and removing a saved copy must not reach into that conversation. It goes
     * when its ordinary expiry comes, like any other attachment — and if that
     * has already passed, the next sweep takes it.
     */
    app.delete('/v1/media/:id/retain', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const { rowCount } = await pool.query(
        'UPDATE media_objects SET retained_at = NULL WHERE id = $1 AND owner_account_id = $2',
        [params.id, accountId],
      );
      if (!rowCount) throw ApiError.notFound('media_not_found', 'No such attachment');
      return { retained: false };
    });

    app.delete('/v1/media/:id', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const { rows } = await pool.query<{ storage_key: string }>(
        'DELETE FROM media_objects WHERE id = $1 AND owner_account_id = $2 RETURNING storage_key',
        [params.id, accountId],
      );
      if (!rows[0]) throw ApiError.notFound('media_not_found', 'No such attachment');
      await storage.delete(rows[0].storage_key);
      return { deleted: true };
    });
  };
}

export default mediaRoutes;
