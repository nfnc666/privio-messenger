import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
import { wipeAccount } from '../src/services/accounts.js';
import { blindPhone, hashesFor } from '../src/services/phone.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('private unverified account phone', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;
  const path = '/v1/accounts/me/phone-note';
  const number = '+41791234567';
  const changed = '+447911123456';
  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'note_alice');
    bob = await registerUser(h.app, 'note_bob');
  });
  after(async () => { await h?.close(); await closePool(); });
  beforeEach(async () => {
    await pool.query('DELETE FROM account_phone_notes');
    await pool.query('DELETE FROM phone_links');
    await pool.query('DELETE FROM phone_verifications');
  });
  const read = (user = alice) => h.app.inject({ method: 'GET', url: path, headers: bearer(user) });
  const save = (phoneNumber: string | null, user = alice) => h.app.inject({ method: 'PUT', url: path, headers: bearer(user), payload: { phoneNumber } });
  const remove = (user = alice) => h.app.inject({ method: 'DELETE', url: path, headers: bearer(user) });

  it('is optional, private and never verified', async () => {
    assert.equal((await h.app.inject({ method: 'GET', url: path })).statusCode, 401);
    assert.deepEqual((await read()).json(), { phoneNumber: null, hasVerifiedNumber: false, verified: false, usedForDiscovery: false });
  });

  it('normalizes, stores, changes and removes with no SMS configuration', async () => {
    const old = { provider: config.SMS_PROVIDER, echo: config.SMS_DEV_ECHO, pepper: config.CONTACT_DISCOVERY_PEPPER };
    try {
      config.SMS_PROVIDER = 'none'; config.SMS_DEV_ECHO = false; config.CONTACT_DISCOVERY_PEPPER = '';
      assert.equal((await save('0041 79 123-45-67')).json().phoneNumber, number);
      assert.equal((await read()).json().phoneNumber, number);
      assert.equal((await save(changed)).json().phoneNumber, changed);
      assert.equal((await remove()).json().phoneNumber, null);
      await save(number);
      assert.equal((await save('   ')).json().phoneNumber, null);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM phone_verifications')).rows[0].n, 0);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM phone_links')).rows[0].n, 0);
    } finally {
      config.SMS_PROVIDER = old.provider; config.SMS_DEV_ECHO = old.echo; config.CONTACT_DISCOVERY_PEPPER = old.pepper;
    }
  });

  it('rejects malformed numbers and authority flags without overwriting a saved value', async () => {
    await save(number);
    for (const value of ['0791234567', '+00012345678', '+411', '+4179abc123', '+417912345678901234']) {
      assert.equal((await save(value)).statusCode, 400);
    }
    for (const extra of [{ accountId: bob.accountId }, { verified: true }, { discoverable: true }]) {
      const denied = await h.app.inject({ method: 'PUT', url: path, headers: bearer(alice), payload: { phoneNumber: changed, ...extra } });
      assert.equal(denied.statusCode, 400);
    }
    assert.equal((await read()).json().phoneNumber, number);
    assert.equal((await read(bob)).json().phoneNumber, null);
  });

  it('persists beyond a server restart and isolates accounts even with the same number', async () => {
    await save(number);
    await save(number, bob);
    // Rebuild routes against the same DB, without createHarness (which truncates).
    const { buildApp } = await import('../src/app.js');
    const restarted = await buildApp({ bus: h.bus, storage: h.storage, push: h.push });
    try {
      const loaded = await restarted.inject({ method: 'GET', url: path, headers: bearer(alice) });
      assert.equal(loaded.json().phoneNumber, number);
    } finally { await restarted.close(); }
    await remove();
    assert.equal((await read(bob)).json().phoneNumber, number);
    assert.equal((await read()).json().phoneNumber, null);
  });

  it('does not expose annotations through public lookups or contact discovery', async () => {
    await save(number);
    for (const url of [`/v1/users/${alice.username}`, `/v1/users/id/${alice.accountId}`, '/v1/contacts']) {
      const response = await h.app.inject({ method: 'GET', url, headers: bearer(bob) });
      assert.equal(response.statusCode, 200);
      assert.ok(!response.body.includes(number));
      assert.ok(!response.body.includes('phoneNumber'));
    }
    const discovery = await h.app.inject({ method: 'POST', url: '/v1/contacts/discover', headers: bearer(bob), payload: { blinded: [blindPhone(number).toString('base64')] } });
    assert.equal(discovery.statusCode, 200);
    assert.deepEqual(discovery.json().matches, []);
  });

  it('never changes or grants a verified discovery mapping', async () => {
    await pool.query('INSERT INTO phone_links(account_id,discovery_hash,hint,discoverable) VALUES($1,$2,$3,true)', [alice.accountId, hashesFor(number), '+41 … 67']);
    const before = (await pool.query('SELECT * FROM phone_links WHERE account_id=$1', [alice.accountId])).rows[0];
    const response = await save(changed);
    assert.equal(response.json().verified, false);
    assert.equal(response.json().hasVerifiedNumber, true);
    // Bob may type Alice's number too; no verification is transferred.
    await save(number, bob);
    await remove();
    const after = (await pool.query('SELECT * FROM phone_links WHERE account_id=$1', [alice.accountId])).rows[0];
    assert.deepEqual(after, before);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM phone_links WHERE account_id=$1', [bob.accountId])).rows[0].n, 0);
  });

  it('removes the private annotation during account wipe', async () => {
    const disposable = await registerUser(h.app, 'note_wipe');
    await save(number, disposable);
    await wipeAccount(disposable.accountId, h.storage);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM account_phone_notes WHERE account_id=$1', [disposable.accountId])).rows[0].n, 0);
  });
});
