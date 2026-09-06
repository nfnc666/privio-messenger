import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';
import { migrate } from '../src/db/migrate.js';
import { pool } from '../src/db/pool.js';
import { closePool } from './helpers.js';

/**
 * Drift between a database and the checkout that is supposed to describe it.
 *
 * This is not hypothetical: a test database carried a migration from an
 * abandoned branch, five tests failed with `column "alias" does not exist`, and
 * the failure read exactly like broken application code. The point of the guard
 * is that the next person is told what actually happened.
 */
describe('migrate', () => {
  after(async () => {
    await pool.query('DELETE FROM schema_migrations WHERE name = $1', ['999_from_a_branch.sql']);
    await closePool();
  });

  it('applies every migration and is idempotent', async () => {
    await migrate();
    assert.deepEqual(await migrate(), [], 'a second run has nothing left to apply');
  });

  it('refuses to run against a database that is ahead of the checkout', async () => {
    await migrate();
    await pool.query('INSERT INTO schema_migrations (name) VALUES ($1)', [
      '999_from_a_branch.sql',
    ]);

    await assert.rejects(migrate(), (err: Error) => {
      assert.match(err.message, /ahead of this checkout/);
      assert.match(err.message, /999_from_a_branch\.sql/, 'names the migration it cannot find');
      return true;
    });
  });
});
