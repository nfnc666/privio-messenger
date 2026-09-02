import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import type { BlobStorage } from '../services/storage.js';
import { ApiError } from '../util/errors.js';
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
  storage_key: string;
  byte_size: string | number;
  kind: string;
  owner_account_id: string;
  download_token_hash: Buffer | null;
}

const TOKEN_HEADER = 'x-privio-media-token';

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
        const { kind } = parse(
          z.object({ kind: z.enum(['attachment', 'avatar']).default('attachment') }),
          request.query,
        );
        const storageKey = await storage.put(body);
        const expiresAt = new Date(Date.now() + config.MEDIA_TTL_DAYS * 86_400_000);

        // Handed back once and never stored. Losing it means losing the blob,
        // which is the point: the server keeps nothing that opens it.
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
        `SELECT storage_key, byte_size, kind, owner_account_id, download_token_hash
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
