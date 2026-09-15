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

  // A sticker is downloadable by anybody who can reach the pack it is in:
  // its owner, anybody who installed it, and anybody presenting a live share
  // code. The pack route is what checks the code; by the time an id is being
  // downloaded, membership is the question, and an object no pack points at
  // belongs to its uploader alone.
  if (object.kind === 'sticker') {
    const { rows } = await pool.query(
      `SELECT 1
         FROM sticker_items i
         JOIN sticker_packs p ON p.id = i.pack_id
        WHERE i.media_id = $1 AND p.deleted_at IS NULL
          AND (p.owner_account_id = $2
               OR EXISTS (SELECT 1 FROM sticker_installs s
                           WHERE s.pack_id = p.id AND s.account_id = $2))
        LIMIT 1`,
      [object.id, accountId],
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
        const storageKey = await storage.put(body);
        const defaultTtl = config.MEDIA_TTL_DAYS * 86_400_000;
        // Only ever shorter. An uploader asking for longer is asking for the
        // retention it would have had anyway, and an avatar is not a message
        // attachment: it stays as long as it is somebody's picture.
        const ttl =
          kind === 'attachment' && expiresInSeconds
            ? Math.min(expiresInSeconds * 1000, defaultTtl)
            : defaultTtl;
        // A sticker outlives the attachment window, like an avatar: a pack
        // whose images were swept away is a pack of empty squares. The sweep
        // also skips referenced objects; this keeps the row's own expiry
        // honest rather than relying on that alone.
        const expiresAt =
          kind === 'sticker' || kind === 'avatar' || kind === 'channel_avatar'
            ? new Date(Date.now() + 100 * 365 * 86_400_000)
            : new Date(Date.now() + ttl);

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
        `SELECT id, storage_key, byte_size, kind, owner_account_id, download_token_hash
           FROM media_objects WHERE id = $1 AND expires_at > now()`,
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
