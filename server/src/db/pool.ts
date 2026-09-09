import pg from 'pg';
import { config } from '../config.js';

// node-postgres hands back bigint as a string by default so precision survives;
// envelope ids fit comfortably in a JS number, so parse them for the API layer.
pg.types.setTypeParser(pg.types.builtins.INT8, (value: string) => Number(value));

export type Pool = pg.Pool;
export type PoolClient = pg.PoolClient;

export const pool: Pool = new pg.Pool({
  connectionString: config.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30_000,
});

export async function withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * One round trip to Postgres, for the health check.
 *
 * Bounded, because an unreachable database is not the same as a refused
 * connection: a host that has vanished (a failover, a network partition, a
 * managed database being resized) accepts the TCP handshake and then says
 * nothing, and `pg` has no default connection timeout, so the query would hang
 * until the OS gives up. A platform health check that hangs is read as a
 * timeout and eventually as a failure, but only after minutes — this answers in
 * seconds.
 *
 * The losing promise is not cancellable, so its eventual rejection is swallowed
 * deliberately; without that, a late failure would surface as an unhandled
 * rejection long after the request it belonged to was answered.
 */
export async function pingDatabase(timeoutMs = 2_000): Promise<void> {
  let timer: NodeJS.Timeout | undefined;
  const query = pool.query('SELECT 1');
  query.catch(() => {});
  try {
    await Promise.race([
      query,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`database did not answer within ${timeoutMs}ms`)), timeoutMs);
        timer.unref();
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}
