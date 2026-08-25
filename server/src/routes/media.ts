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
 * seals the file with it, and sends that key inside the E2EE message. The server
 * holds ciphertext plus a length, and the object id acts as the download
 * capability — which is why ids are unguessable and objects always expire.
 */
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
        const storageKey = await storage.put(body);
        const expiresAt = new Date(Date.now() + config.MEDIA_TTL_DAYS * 86_400_000);
        const { rows } = await pool.query<{ id: string }>(
          `INSERT INTO media_objects (owner_account_id, byte_size, storage_key, expires_at)
           VALUES ($1, $2, $3, $4) RETURNING id`,
          [accountId, body.length, storageKey, expiresAt],
        );
        reply.code(201);
        return { id: rows[0]!.id, byteSize: body.length, expiresAt: expiresAt.toISOString() };
      },
    );

    app.get('/v1/media/:id', requireAuth, async (request, reply) => {
      auth(request);
      const params = parse(z.object({ id: uuidSchema }), request.params);
      const { rows } = await pool.query(
        'SELECT storage_key, byte_size FROM media_objects WHERE id = $1 AND expires_at > now()',
        [params.id],
      );
      const object = rows[0];
      if (!object) throw ApiError.notFound('media_not_found', 'No such attachment');
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
