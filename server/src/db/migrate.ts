import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool, withTransaction } from './pool.js';

const migrationsDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'migrations');

/** Applies every migration file that is not yet recorded in schema_migrations. */
export async function migrate(): Promise<string[]> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);

  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  const { rows } = await pool.query<{ name: string }>('SELECT name FROM schema_migrations');
  const applied = new Set(rows.map((r) => r.name));
  const ran: string[] = [];

  // A database that records a migration this checkout does not have is ahead of
  // the code, and nothing below would notice: the loop only ever adds. That
  // happens on a long-lived dev or test database — a branch is checked out,
  // migrated, and then abandoned — and it turns into test failures that read
  // like broken code and are not. CI never sees it, because CI gets an empty
  // database every run, so the person who hits it is alone with it. Say so
  // instead, and name the fix.
  const unknown = [...applied].filter((name) => !files.includes(name)).sort();
  if (unknown.length > 0) {
    throw new Error(
      `Database is ahead of this checkout: it has applied ${unknown.join(', ')}, ` +
        'which no migration file here provides. This is schema drift, not a code ' +
        'fault — recreate the database, or check out the branch those migrations ' +
        'came from.',
    );
  }

  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = await readFile(join(migrationsDir, file), 'utf8');
    await withTransaction(async (client) => {
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    });
    ran.push(file);
  }
  return ran;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const ran = await migrate();
  console.log(ran.length ? `applied: ${ran.join(', ')}` : 'already up to date');
  await pool.end();
}
