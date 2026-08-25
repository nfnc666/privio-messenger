import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { authenticator } from 'otplib';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, deviceBody, deviceFixture, registerUser, type TestHarness } from './helpers.js';

describe('accounts', () => {
  let h: TestHarness;
  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('registers an account with its first device and no phone number', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username: 'Alice', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(response.statusCode, 201);
    const body = response.json();
    assert.equal(body.username, 'alice', 'usernames are normalised to lowercase');
    assert.ok(body.token && body.accountId && body.deviceId);
  });

  it('rejects a duplicate username', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username: 'alice', password: 'another-good-password', device: deviceBody(deviceFixture()) },
    });
    assert.equal(response.statusCode, 409);
    assert.equal(response.json().error, 'username_taken');
  });

  it('rejects a weak password', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username: 'shorty', password: 'short', device: deviceBody(deviceFixture()) },
    });
    assert.equal(response.statusCode, 400);
  });

  it('never stores the password or the session token', async () => {
    const { rows } = await pool.query('SELECT password_hash FROM accounts WHERE username = $1', ['alice']);
    assert.ok(rows[0].password_hash.startsWith('$argon2id$'));
    const sessions = await pool.query('SELECT token_hash FROM sessions LIMIT 1');
    assert.equal(sessions.rows[0].token_hash.length, 32, 'only a SHA-256 digest is kept');
  });

  it('logs in and issues a token for the new device', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: 'alice',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(response.statusCode, 200);
    assert.ok(response.json().token);
  });

  it('gives the same answer for a wrong password and an unknown user', async () => {
    const wrongPassword = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'alice', password: 'not-the-password', device: deviceBody(deviceFixture()) },
    });
    const unknownUser = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'nobody', password: 'not-the-password', device: deviceBody(deviceFixture()) },
    });
    assert.equal(wrongPassword.statusCode, 401);
    assert.deepEqual(wrongPassword.json(), unknownUser.json());
  });

  it('rejects requests without a valid token', async () => {
    const anonymous = await h.app.inject({ method: 'GET', url: '/v1/accounts/me' });
    assert.equal(anonymous.statusCode, 401);
    const bogus = await h.app.inject({
      method: 'GET',
      url: '/v1/accounts/me',
      headers: { authorization: 'Bearer not-a-real-token' },
    });
    assert.equal(bogus.statusCode, 401);
  });

  it('enables two-factor auth and then demands a code at login', async () => {
    const user = await registerUser(h.app, 'twofactor');
    const setup = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts/me/totp/setup',
      headers: bearer(user),
    });
    assert.equal(setup.statusCode, 200);
    const { secret } = setup.json();

    const enabled = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts/me/totp/enable',
      headers: bearer(user),
      payload: { code: authenticator.generate(secret) },
    });
    assert.equal(enabled.statusCode, 200);

    const withoutCode = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: 'twofactor',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(withoutCode.statusCode, 401);
    assert.equal(withoutCode.json().error, 'totp_required');

    const withCode = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: 'twofactor',
        password: 'correct-horse-battery',
        totpCode: authenticator.generate(secret),
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(withCode.statusCode, 200);
  });

  it('wipes the account when the duress code is entered instead of the password', async () => {
    const user = await registerUser(h.app, 'duress');
    const set = await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/wipe-code',
      headers: bearer(user),
      payload: { currentPassword: 'correct-horse-battery', wipeCode: '911911' },
    });
    assert.equal(set.statusCode, 200);

    const attempt = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'duress', password: '911911', device: deviceBody(deviceFixture()) },
    });
    assert.equal(attempt.statusCode, 401);
    assert.equal(attempt.json().error, 'invalid_credentials', 'a wipe must be indistinguishable from a typo');

    const { rows } = await pool.query('SELECT count(*) FROM devices WHERE account_id = $1', [user.accountId]);
    assert.equal(Number(rows[0].count), 0, 'every device is gone');

    const afterWipe = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
    assert.equal(afterWipe.statusCode, 401, 'the wiped session no longer authenticates');
  });

  it('revokes other sessions when the password changes', async () => {
    const user = await registerUser(h.app, 'rotator');
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: 'rotator',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    const secondToken = second.json().token;

    const changed = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts/me/password',
      headers: bearer(user),
      payload: { currentPassword: 'correct-horse-battery', newPassword: 'an-entirely-new-password' },
    });
    assert.equal(changed.statusCode, 200);

    const stale = await h.app.inject({
      method: 'GET',
      url: '/v1/accounts/me',
      headers: { authorization: `Bearer ${secondToken}` },
    });
    assert.equal(stale.statusCode, 401);
    const current = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
    assert.equal(current.statusCode, 200, 'the session that made the change survives');
  });
});
