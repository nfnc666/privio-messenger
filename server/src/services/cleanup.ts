import { pool } from '../db/pool.js';
import { config } from '../config.js';
import type { BlobStorage } from './storage.js';

/** Deletes expired attachments and abandoned envelopes. Safe to run concurrently. */
export async function runRetentionSweep(storage: BlobStorage): Promise<{
  mediaDeleted: number;
  envelopesDeleted: number;
}> {
  const { rows } = await pool.query<{ storage_key: string }>(
    `DELETE FROM media_objects
     WHERE expires_at <= now()
       -- An avatar is not a message attachment: it stays as long as it is
       -- someone's picture, and the sweep must not quietly blank profiles.
       AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.avatar_media_id = media_objects.id)
     RETURNING storage_key`,
  );
  await Promise.all(rows.map((r) => storage.delete(r.storage_key).catch(() => {})));

  // An envelope this old belongs to a device that is never coming back.
  const { rowCount } = await pool.query(
    `DELETE FROM envelopes WHERE created_at < now() - ($1 || ' days')::interval`,
    [config.ENVELOPE_TTL_DAYS],
  );

  return { mediaDeleted: rows.length, envelopesDeleted: rowCount ?? 0 };
}

/** Starts the hourly sweep. Returns a stop function. */
export function startRetentionSweeper(
  storage: BlobStorage,
  onError: (err: unknown) => void,
  intervalMs = 3_600_000,
): () => void {
  const timer = setInterval(() => {
    runRetentionSweep(storage).catch(onError);
  }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
