// A deployment that never configured a key. The config is read once at import,
// so this has to be set before the first one.
process.env.TOTP_SECRET_KEY = '';

import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import type { FastifyInstance } from 'fastify';
import type { TestHarness } from './helpers.js';

const { openSecret, sealSecret, canStoreSecrets } = await import('../src/services/totp.js');
const { bearer, closePool, createHarness, registerUser } = await import('./helpers.js');

const KEY = Buffer.alloc(32, 7).toString('base64');
const OTHER = Buffer.alloc(32, 9).toString('base64');

describe('sealing a TOTP secret', () => {
  it('round-trips', () => {
    const sealed = sealSecret('JBSWY3DPEHPK3PXP', KEY);
    assert.notEqual(sealed, 'JBSWY3DPEHPK3PXP');
    assert.equal(openSecret(sealed, KEY), 'JBSWY3DPEHPK3PXP');
  });

  it('is different bytes every time, for the same secret', () => {
    const once = sealSecret('JBSWY3DPEHPK3PXP', KEY);
    const twice = sealSecret('JBSWY3DPEHPK3PXP', KEY);
    // Otherwise the column says which accounts share a secret, and a
    // re-enrolment says which account this is.
    assert.notEqual(once, twice);
    assert.equal(openSecret(twice, KEY), 'JBSWY3DPEHPK3PXP');
  });

  it('will not open under another key', () => {
    assert.equal(openSecret(sealSecret('JBSWY3DPEHPK3PXP', KEY), OTHER), null);
  });

  it('will not open if a byte was changed', () => {
    const sealed = sealSecret('JBSWY3DPEHPK3PXP', KEY);
    const parts = sealed.split('.');
    const body = Buffer.from(parts[2]!, 'base64');
    body[0] = body[0]! ^ 0xff;
    const tampered = [parts[0], parts[1], body.toString('base64')].join('.');

    // GCM catches it, so a row someone edited in the database is refused
    // rather than opened into a secret of their choosing.
    assert.equal(openSecret(tampered, KEY), null);
  });

  it('leaves a secret stored before sealing existed alone', () => {
    // Already-enrolled accounts keep working; the next secret written is sealed.
    assert.equal(openSecret('JBSWY3DPEHPK3PXP', KEY), 'JBSWY3DPEHPK3PXP');
  });

  it('refuses to seal without a key', () => {
    assert.equal(canStoreSecrets(), false, 'this process has none configured');
    assert.throws(() => sealSecret('JBSWY3DPEHPK3PXP', undefined));
    assert.throws(() => sealSecret('JBSWY3DPEHPK3PXP', 'too-short'));
  });
});

describe('a server with no TOTP key', () => {
  let h: TestHarness;
  let app: FastifyInstance;

  before(async () => {
    h = await createHarness();
    app = h.app;
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('refuses to enrol anyone rather than storing a secret in the clear', async () => {
    const user = await registerUser(app, 'nokey');
    const setup = await app.inject({
      method: 'POST',
      url: '/v1/accounts/me/totp/setup',
      headers: bearer(user),
    });

    assert.equal(setup.statusCode, 503);
    assert.equal(setup.json().error, 'totp_unavailable');
    // The person reading this cannot fix the server's configuration, so the
    // message points them at someone who can rather than naming a variable.
    assert.match(setup.json().message, /Ask whoever runs it/);
    assert.ok(!setup.json().message.includes('TOTP_SECRET_KEY'));
  });
});
