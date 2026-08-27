import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
import { licenseHash, normaliseLicenseKey } from '../src/services/licenses.js';
import {
  bearer,
  closePool,
  createHarness,
  deviceBody,
  deviceFixture,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

const issuer = { authorization: `Bearer ${process.env.LICENSE_ISSUER_TOKEN}` };

/** Buys a license the way the website does, and returns the key it was shown. */
async function issue(h: TestHarness, reference: string): Promise<string> {
  const response = await h.app.inject({
    method: 'POST',
    url: '/v1/internal/licenses',
    headers: issuer,
    payload: { paymentProvider: 'stripe', paymentReference: reference },
  });
  assert.equal(response.statusCode, 201, response.body);
  return response.json().licenseKey as string;
}

describe('licenses', () => {
  let h: TestHarness;
  let alice: TestUser;
  /** Kept so the retry case can re-send the very same key. */
  let aliceKey: string;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
  });
  // The pool is shared across both suites in this file; the last one closes it.
  after(async () => {
    await h.close();
  });

  it('issues a key in the documented format', async () => {
    const key = await issue(h, 'cs_issue_format');
    assert.match(key, /^PRIVIO-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/);
  });

  it('stores only a hash of the key', async () => {
    const key = await issue(h, 'cs_hash_only');
    const { rows } = await pool.query<{ key_hash: Buffer }>(
      'SELECT key_hash FROM licenses WHERE payment_reference = $1',
      ['cs_hash_only'],
    );
    assert.equal(rows[0]!.key_hash.length, 32, 'an HMAC-SHA256 digest and nothing else');
    assert.ok(rows[0]!.key_hash.equals(licenseHash(key)));

    const dump = await pool.query("SELECT * FROM licenses WHERE payment_reference = 'cs_hash_only'");
    const columns = Object.values(dump.rows[0]!).map((v) => String(v));
    assert.ok(!columns.some((value) => value.includes(key.slice(7))), 'no column holds the plaintext');
  });

  it('refuses to mint a second key for the same order', async () => {
    await issue(h, 'cs_retry');
    const retry = await h.app.inject({
      method: 'POST',
      url: '/v1/internal/licenses',
      headers: issuer,
      payload: { paymentProvider: 'stripe', paymentReference: 'cs_retry' },
    });
    assert.equal(retry.statusCode, 409);
    assert.equal(retry.json().error, 'license_already_issued');
    assert.ok(retry.json().licenseId, 'the caller is told which license the order has');

    const { rows } = await pool.query('SELECT id FROM licenses WHERE payment_reference = $1', ['cs_retry']);
    assert.equal(rows.length, 1);
  });

  it('rejects issuing without the issuer token', async () => {
    for (const headers of [{}, { authorization: 'Bearer wrong-token' }]) {
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/internal/licenses',
        headers,
        payload: { paymentProvider: 'stripe', paymentReference: 'cs_no_auth' },
      });
      assert.equal(response.statusCode, 401);
    }
    const { rows } = await pool.query('SELECT id FROM licenses WHERE payment_reference = $1', ['cs_no_auth']);
    assert.equal(rows.length, 0, 'nothing was issued');
  });

  it('redeems a key and binds it to the account', async () => {
    aliceKey = await issue(h, 'cs_redeem');
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(alice),
      payload: { licenseKey: aliceKey },
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().licensed, true);

    const { rows } = await pool.query<{ redeemed_by: string }>(
      'SELECT redeemed_by FROM licenses WHERE payment_reference = $1',
      ['cs_redeem'],
    );
    assert.equal(rows[0]!.redeemed_by, alice.accountId);
  });

  it('reports the status to the client', async () => {
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: bearer(alice),
    });
    assert.equal(response.statusCode, 200);
    const body = response.json();
    assert.equal(body.licensed, true);
    assert.equal(body.source, 'key');
    assert.equal(body.required, false, 'a self-hosted server tells the app not to ask for a key');
  });

  it('treats re-sending the same key from the same account as a retry', async () => {
    // What a client does when a response was lost on the way back.
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(alice),
      payload: { licenseKey: aliceKey },
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().licensed, true);
  });

  it('does not burn a second key on an account that already has one', async () => {
    const key = await issue(h, 'cs_second_key');
    const claim = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(alice),
      payload: { licenseKey: key },
    });
    assert.equal(claim.statusCode, 409);
    assert.equal(claim.json().error, 'account_already_licensed');

    const { rows } = await pool.query<{ redeemed_by: string | null }>(
      "SELECT redeemed_by FROM licenses WHERE payment_reference = 'cs_second_key'",
    );
    assert.equal(rows[0]!.redeemed_by, null, 'the rejected key is still worth something');
  });

  it('refuses a key that someone else already redeemed', async () => {
    const key = await issue(h, 'cs_taken');
    const bob = await registerUser(h.app, 'bob');
    const carol = await registerUser(h.app, 'carol');

    const first = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(bob),
      payload: { licenseKey: key },
    });
    assert.equal(first.statusCode, 200);

    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(carol),
      payload: { licenseKey: key },
    });
    assert.equal(second.statusCode, 409);
    assert.equal(second.json().error, 'license_already_redeemed');
  });

  it('lets only one of two racing redemptions win', async () => {
    const key = await issue(h, 'cs_race');
    const dave = await registerUser(h.app, 'dave');
    const erin = await registerUser(h.app, 'erin');

    const [a, b] = await Promise.all(
      [dave, erin].map((user) =>
        h.app.inject({
          method: 'POST',
          url: '/v1/licenses/redeem',
          headers: bearer(user),
          payload: { licenseKey: key },
        }),
      ),
    );
    const codes = [a!.statusCode, b!.statusCode].sort();
    assert.deepEqual(codes, [200, 409], 'exactly one claim succeeds');
  });

  it('accepts a key typed with the ambiguous characters', async () => {
    const key = await issue(h, 'cs_typos');
    const frank = await registerUser(h.app, 'frank');

    // O for zero, I for one, and no separators — the folding the docs promise.
    const mistyped = key.toLowerCase().replace(/-/g, ' ').replace(/0/g, 'O').replace(/1/g, 'I');
    assert.equal(normaliseLicenseKey(mistyped), normaliseLicenseKey(key));

    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(frank),
      payload: { licenseKey: mistyped },
    });
    assert.equal(response.statusCode, 200, response.body);
  });

  it('rejects an unknown key', async () => {
    const grace = await registerUser(h.app, 'grace');
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(grace),
      payload: { licenseKey: 'PRIVIO-ZZZZ-ZZZZ-ZZZZ-ZZZZ' },
    });
    assert.equal(response.statusCode, 404);
    assert.equal(response.json().error, 'license_not_found');
  });

  it('rejects a revoked key and stops it counting once redeemed', async () => {
    const key = await issue(h, 'cs_chargeback');
    const heidi = await registerUser(h.app, 'heidi');
    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(heidi),
      payload: { licenseKey: key },
    });

    const revoke = await h.app.inject({
      method: 'POST',
      url: '/v1/internal/licenses/revoke',
      headers: issuer,
      payload: { paymentProvider: 'stripe', paymentReference: 'cs_chargeback' },
    });
    assert.equal(revoke.statusCode, 200);

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: bearer(heidi),
    });
    assert.equal(status.json().licensed, false, 'a chargeback takes the entitlement with it');
  });

  it('requires authentication to redeem', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      payload: { licenseKey: 'PRIVIO-AAAA-AAAA-AAAA-AAAA' },
    });
    assert.equal(response.statusCode, 401);
  });
});

describe('license enforcement', () => {
  let h: TestHarness;
  let ivan: TestUser;
  let judy: TestUser;

  before(async () => {
    h = await createHarness();
    ivan = await registerUser(h.app, 'ivan');
    judy = await registerUser(h.app, 'judy');
    // The gate reads the flag per request, so a hosted deployment can be
    // simulated without rebuilding the app.
    (config as { LICENSE_REQUIRED: boolean }).LICENSE_REQUIRED = true;
  });
  after(async () => {
    (config as { LICENSE_REQUIRED: boolean }).LICENSE_REQUIRED = false;
    await h.close();
    await closePool();
  });

  it('refuses a send from an unlicensed account', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(ivan),
      payload: { username: 'judy', envelopes: [] },
    });
    assert.equal(response.statusCode, 403);
    assert.equal(response.json().error, 'license_required');
  });

  it('still lets an unlicensed account sign in, fetch and register a device', async () => {
    const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(ivan) });
    assert.equal(me.statusCode, 200);

    const inbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(ivan) });
    assert.equal(inbox.statusCode, 200, 'what was already delivered stays reachable');

    const login = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: 'ivan',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(login.statusCode, 200);
  });

  it('refuses group and channel creation while unlicensed', async () => {
    const group = await h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(ivan),
      payload: { encryptedMetadata: Buffer.from('x').toString('base64'), memberIds: [] },
    });
    assert.equal(group.statusCode, 403);

    const channel = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(ivan),
      payload: { handle: 'news', encryptedMetadata: Buffer.from('x').toString('base64') },
    });
    assert.equal(channel.statusCode, 403);
  });

  it('lets the account through once a key is redeemed', async () => {
    const issued = await h.app.inject({
      method: 'POST',
      url: '/v1/internal/licenses',
      headers: issuer,
      payload: { paymentProvider: 'paypal', paymentReference: 'pp_gate' },
    });
    const key = issued.json().licenseKey as string;

    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(ivan),
      payload: { licenseKey: key },
    });

    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(ivan),
      payload: { username: 'judy', envelopes: [] },
    });
    assert.notEqual(response.statusCode, 403, 'the license gate is out of the way');
    assert.ok(judy.accountId);
  });
});
