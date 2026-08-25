import type { FastifyPluginAsync } from 'fastify';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { auth } from '../plugins/auth.js';
import type { BlobStorage } from '../services/storage.js';
import { ApiError } from '../util/errors.js';

/**
 * Cloud backup is opt-in and end-to-end encrypted: the client seals its local
 * database with a key derived from a recovery phrase the user keeps. Losing that
 * phrase means losing the backup — there is no server-side reset, by design.
 */
export function backupRoutes(storage: BlobStorage): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

    app.put('/v1/backup', { ...requireAuth, bodyLimit: config.MAX_BACKUP_BYTES }, async (request) => {
      const { accountId } = auth(request);
      const body = request.body;
      if (!Buffer.isBuffer(body) || body.length === 0) {
        throw ApiError.badRequest('empty_body', 'Send the encrypted backup as application/octet-stream');
      }
      const { rows: existing } = await pool.query<{ storage_key: string }>(
        'SELECT storage_key FROM backups WHERE account_id = $1',
        [accountId],
      );
      const storageKey = await storage.put(body);
      const { rows } = await pool.query<{ version: number }>(
        `INSERT INTO backups (account_id, storage_key, byte_size)
         VALUES ($1, $2, $3)
         ON CONFLICT (account_id) DO UPDATE
           SET storage_key = EXCLUDED.storage_key,
               byte_size = EXCLUDED.byte_size,
               version = backups.version + 1,
               updated_at = now()
         RETURNING version`,
        [accountId, storageKey, body.length],
      );
      // Drop the superseded blob only once the new one is committed.
      const previous = existing[0]?.storage_key;
      if (previous && previous !== storageKey) await storage.delete(previous);
      return { stored: true, byteSize: body.length, version: rows[0]!.version };
    });

    app.get('/v1/backup', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const { rows } = await pool.query(
        'SELECT byte_size, version, updated_at FROM backups WHERE account_id = $1',
        [accountId],
      );
      const backup = rows[0];
      if (!backup) throw ApiError.notFound('no_backup', 'No backup stored');
      return {
        byteSize: Number(backup.byte_size),
        version: backup.version,
        updatedAt: (backup.updated_at as Date).toISOString(),
      };
    });

    app.get('/v1/backup/content', requireAuth, async (request, reply) => {
      const { accountId } = auth(request);
      const { rows } = await pool.query(
        'SELECT storage_key, byte_size FROM backups WHERE account_id = $1',
        [accountId],
      );
      const backup = rows[0];
      if (!backup) throw ApiError.notFound('no_backup', 'No backup stored');
      reply.header('content-type', 'application/octet-stream');
      reply.header('content-length', String(backup.byte_size));
      reply.header('cache-control', 'private, no-store');
      return reply.send(storage.open(backup.storage_key));
    });

    app.delete('/v1/backup', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const { rows } = await pool.query<{ storage_key: string }>(
        'DELETE FROM backups WHERE account_id = $1 RETURNING storage_key',
        [accountId],
      );
      if (rows[0]) await storage.delete(rows[0].storage_key);
      return { deleted: Boolean(rows[0]) };
    });
  };
}

export default backupRoutes;
