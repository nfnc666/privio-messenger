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
});
