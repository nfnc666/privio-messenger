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

/**
 * Where a connection-level failure is reported.
 *
 * `pg` raises `error` on the pool when a *idle* client's connection breaks —
 * Postgres restarting, a failover, a network drop — and Node throws on an
 * `error` event that nobody listens to. Without this listener the whole process
 * died the moment Postgres went away, which CI caught: the container stopped
 * answering entirely instead of reporting itself unhealthy, and a platform
 * would have restarted it in a loop through every routine database maintenance
 * window.
 *
 * The pool recovers on its own — the broken client is discarded and the next
 * request opens a new one — so the right response is to say what happened and
 * keep serving. It is a settable sink rather than a direct call to a logger
 * because the pool is constructed at import time, before the application and
 * its logger exist.
 */
let reportPoolError: (err: Error) => void = (err) => {
  // Before the app is up there is no logger; stderr is better than silence.
  console.error('postgres pool error', err);
};

/** Routes pool-level failures into the application logger. */
export function onPoolError(report: (err: Error) => void): void {
  reportPoolError = report;
}

pool.on('error', (err: unknown) => {
  reportPoolError(err instanceof Error ? err : new Error(String(err)));
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
