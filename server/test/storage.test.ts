import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { runRetentionSweep } from '../src/services/cleanup.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('media and backup', () => {
  let h: TestHarness;
  let alice: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
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

  it('stores an encrypted attachment and returns it byte for byte', async () => {
    const sealed = Buffer.from('this is already ciphertext when it arrives');
    const upload = await octet(sealed, alice, '/v1/media', 'POST');
    assert.equal(upload.statusCode, 201);
    const { id, expiresAt } = upload.json();
    assert.ok(new Date(expiresAt) > new Date(), 'attachments always carry an expiry');

    const download = await h.app.inject({ method: 'GET', url: `/v1/media/${id}`, headers: bearer(alice) });
    assert.equal(download.statusCode, 200);
    assert.deepEqual(download.rawPayload, sealed);
  });

  it('requires authentication to download an attachment', async () => {
    const upload = await octet(Buffer.from('secret'), alice, '/v1/media', 'POST');
    const anonymous = await h.app.inject({ method: 'GET', url: `/v1/media/${upload.json().id}` });
    assert.equal(anonymous.statusCode, 401);
  });

  it('versions an encrypted backup and drops the superseded blob', async () => {
    const first = await octet(Buffer.from('backup-v1'), alice, '/v1/backup', 'PUT');
    assert.equal(first.json().version, 1);
    const second = await octet(Buffer.from('backup-v2-longer'), alice, '/v1/backup', 'PUT');
    assert.equal(second.json().version, 2);

    const meta = await h.app.inject({ method: 'GET', url: '/v1/backup', headers: bearer(alice) });
    assert.equal(meta.json().byteSize, Buffer.from('backup-v2-longer').length);

    const content = await h.app.inject({
      method: 'GET',
      url: '/v1/backup/content',
      headers: bearer(alice),
    });
    assert.equal(content.rawPayload.toString(), 'backup-v2-longer');

    const { rows } = await pool.query('SELECT count(*) FROM backups WHERE account_id = $1', [alice.accountId]);
    assert.equal(Number(rows[0].count), 1, 'one backup per account, not a growing pile');
  });

  it('sweeps expired attachments away with their bytes', async () => {
    const upload = await octet(Buffer.from('short-lived'), alice, '/v1/media', 'POST');
    const { id } = upload.json();
    const { rows } = await pool.query<{ storage_key: string }>(
      'UPDATE media_objects SET expires_at = now() - interval \'1 day\' WHERE id = $1 RETURNING storage_key',
      [id],
    );

    const swept = await runRetentionSweep(h.storage);
    assert.ok(swept.mediaDeleted >= 1);

    const gone = await h.app.inject({ method: 'GET', url: `/v1/media/${id}`, headers: bearer(alice) });
    assert.equal(gone.statusCode, 404);
    assert.ok(rows[0], 'the row existed before the sweep');
  });
  it('an avatar is not swept away with the attachments', async () => {
    const upload = await octet(Buffer.from('sealed-avatar'), alice, '/v1/media', 'POST');
    const { id } = upload.json();

    const set = await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/avatar',
      headers: bearer(alice),
      payload: { mediaId: id },
    });
    assert.equal(set.statusCode, 200);

    // Becoming an avatar lifts the attachment expiry: a picture is not a
    // message and must not disappear after the retention window.
    const { rows } = await pool.query<{ expires_at: Date }>(
      'SELECT expires_at FROM media_objects WHERE id = $1',
      [id],
    );
    assert.ok(
      rows[0]!.expires_at.getTime() > Date.now() + 365 * 86_400_000,
      'the expiry should now be far out, not the attachment window',
    );

    // And should anything push it back anyway, the sweep still skips a picture
    // somebody is using.
    await pool.query("UPDATE media_objects SET expires_at = now() - interval '1 day' WHERE id = $1", [id]);
    await runRetentionSweep(h.storage);

    const after = await pool.query('SELECT id FROM media_objects WHERE id = $1', [id]);
    assert.equal(after.rowCount, 1, 'a profile picture must not silently vanish');
  });

  it('replacing an avatar lets the old picture go', async () => {
    const first = (await octet(Buffer.from('avatar-one'), alice, '/v1/media', 'POST')).json();
    const second = (await octet(Buffer.from('avatar-two'), alice, '/v1/media', 'POST')).json();

    for (const media of [first, second]) {
      await h.app.inject({
        method: 'PUT',
        url: '/v1/accounts/me/avatar',
        headers: bearer(alice),
        payload: { mediaId: media.id },
      });
    }
    await runRetentionSweep(h.storage);

    const old = await h.app.inject({ method: 'GET', url: `/v1/media/${first.id}`, headers: bearer(alice) });
    assert.equal(old.statusCode, 404, 'the replaced picture is nobody\'s and goes');
    const current = await h.app.inject({ method: 'GET', url: `/v1/media/${second.id}`, headers: bearer(alice) });
    assert.equal(current.statusCode, 200);
  });

  it('refuses an avatar that is not the caller\'s own upload', async () => {
    const mallory = await registerUser(h.app, 'mallory');
    const upload = (await octet(Buffer.from('someone-elses'), alice, '/v1/media', 'POST')).json();

    const stolen = await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/avatar',
      headers: bearer(mallory),
      payload: { mediaId: upload.id },
    });
    assert.equal(stolen.statusCode, 404, 'and the error says nothing about whether it exists');
  });

  it('the server stores a pointer to ciphertext, never a picture', async () => {
    const sealed = Buffer.from('this was sealed with a profile key');
    const upload = (await octet(sealed, alice, '/v1/media', 'POST')).json();
    await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/avatar',
      headers: bearer(alice),
      payload: { mediaId: upload.id },
    });

    const { rows } = await pool.query('SELECT avatar_media_id FROM accounts WHERE id = $1', [alice.accountId]);
    assert.equal(rows[0].avatar_media_id, upload.id);

    // A contact sees the pointer; opening it still needs a key the server has
    // never held.
    const bob = await registerUser(h.app, 'bob');
    const profile = await h.app.inject({ method: 'GET', url: '/v1/users/alice', headers: bearer(bob) });
    assert.equal(profile.json().avatarMediaId, upload.id);
    assert.ok(profile.json().avatarUpdatedAt);
  });
});
