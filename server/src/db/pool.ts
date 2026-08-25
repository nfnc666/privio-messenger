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
