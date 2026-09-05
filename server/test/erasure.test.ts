import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * What is left on disk after an account is destroyed.
 *
 * Its own file because these tests end accounts, and because the sweeper cannot
 * clean up after them: a row that has been deleted no longer names the file it
 * stood for, so anything missed here is missed for good.
 */
describe('destroying an account', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const octet = (body: Buffer, user: TestUser, url: string, method: 'POST' | 'PUT') =>
    h.app.inject({
      method,
      url,
      headers: { ...bearer(user), 'content-type': 'application/octet-stream' },
      payload: body,
    });

  /** Every storage key the account owns, read before the rows go. */
  async function keysOf(accountId: string): Promise<string[]> {
    const media = await pool.query<{ storage_key: string }>(
      'SELECT storage_key FROM media_objects WHERE owner_account_id = $1',
      [accountId],
    );
    const backup = await pool.query<{ storage_key: string }>(
      'SELECT storage_key FROM backups WHERE account_id = $1',
      [accountId],
    );
    return [...media.rows, ...backup.rows].map((r) => r.storage_key);
  }

  async function onDisk(key: string): Promise<boolean> {
    try {
      await h.storage.size(key);
      return true;
    } catch {
      return false;
    }
  }

  async function withContent(username: string) {
    const user = await registerUser(h.app, username);
    await octet(Buffer.from('sealed attachment bytes'), user, '/v1/media', 'POST');
    await octet(Buffer.from('sealed backup bytes'), user, '/v1/backup', 'PUT');
    const keys = await keysOf(user.accountId);
    assert.equal(keys.length, 2, 'an attachment and a backup are on disk to begin with');
    for (const key of keys) assert.ok(await onDisk(key), 'written');
    return { user, keys };
  }

  it('deleting the account takes the bytes with it, not just the rows', async () => {
    // Deleting the row that names a file and leaving the file is worse than not
    // deleting either: the sweeper works from `media_objects.expires_at`, so an
    // orphan is unreachable and stays until the disk is thrown away.
    const { user, keys } = await withContent('erasing');

    const deleted = await h.app.inject({
      method: 'DELETE',
      url: '/v1/accounts/me',
      headers: bearer(user),
      payload: { currentPassword: 'correct-horse-battery' },
    });
    assert.equal(deleted.statusCode, 200);

    for (const key of keys) {
      assert.equal(await onDisk(key), false, `${key} is still on disk`);
    }
  });

  it('the duress wipe destroys the content, which is the whole point of it', async () => {
    // Somebody is standing over the phone. "Deleted" has to mean the bytes.
    const { user, keys } = await withContent('coerced');
    await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/duress-code',
      headers: bearer(user),
      payload: { currentPassword: 'correct-horse-battery', duressCode: '911911' },
    });

    const wiped = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts/me/wipe',
      headers: bearer(user),
      payload: { duressCode: '911911' },
    });
    assert.equal(wiped.statusCode, 200);

    for (const key of keys) {
      assert.equal(await onDisk(key), false, `${key} survived the wipe`);
    }
  });
});
