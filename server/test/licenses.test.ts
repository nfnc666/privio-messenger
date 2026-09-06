import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
import { licenseHash, normaliseLicenseKey } from '../src/services/licenses.js';
import { DEFAULT_DEVICE_LIMIT } from '../src/services/devices.js';
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

describe('device entitlement', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    // The pool is closed by the last describe in this file, not here: node's
    // test runner runs them in order in one process, and ending it early
    // leaves the ones after it without a database.
  });

  /** Buys a license covering a given number of devices. */
  async function issueFor(reference: string, maxDevices?: number): Promise<string> {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/internal/licenses',
      headers: issuer,
      payload: { paymentProvider: 'stripe', paymentReference: reference, maxDevices },
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json().licenseKey as string;
  }

  async function addDevice(user: TestUser) {
    return h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: user.username,
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
  }

  it('tells an unauthenticated client whether a key is needed', async () => {
    // The app asks for a key on first launch, before anyone has signed in, so
    // this is the only place it can learn the answer.
    const response = await h.app.inject({ method: 'GET', url: '/v1/server' });

    assert.equal(response.statusCode, 200);
    assert.equal(response.json().licenseRequired, config.LICENSE_REQUIRED);
    assert.equal(
      response.json().token,
      undefined,
      'the public endpoint carries policy, never state',
    );
  });

  it('reports how many devices the license covers and how many are in use', async () => {
    const kim = await registerUser(h.app, 'kim');
    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(kim),
      payload: { licenseKey: await issueFor('stripe_kim', 2) },
    });

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: bearer(kim),
    });

    assert.equal(status.json().maxDevices, 2);
    assert.equal(status.json().devices, 1, 'the device it registered with');
  });

  it('caps devices at what the license was sold with', async () => {
    const leo = await registerUser(h.app, 'leo');
    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(leo),
      payload: { licenseKey: await issueFor('stripe_leo', 2) },
    });

    const second = await addDevice(leo);
    assert.equal(second.statusCode, 200, 'the second device is within the licence');

    const third = await addDevice(leo);
    assert.equal(third.statusCode, 409);
    assert.equal(third.json().error, 'too_many_devices');
    assert.match(third.json().message, /2 active devices/);
  });

  it('a revoked license drops the account back to the default limit', async () => {
    // Not to zero: an account that has lost its licence can still reach itself
    // and read what already arrived, which is the same split the send gate uses.
    const mia = await registerUser(h.app, 'mia');
    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(mia),
      payload: { licenseKey: await issueFor('stripe_mia', 1) },
    });

    const blocked = await addDevice(mia);
    assert.equal(blocked.statusCode, 409, 'one device is all that licence covers');

    await h.app.inject({
      method: 'POST',
      url: '/v1/internal/licenses/revoke',
      headers: issuer,
      payload: { paymentProvider: 'stripe', paymentReference: 'stripe_mia' },
    });

    const allowed = await addDevice(mia);
    assert.equal(allowed.statusCode, 200, response(allowed));
  });

  it('an account with no license gets the default limit', async () => {
    const nora = await registerUser(h.app, 'nora');

    for (let i = 1; i < DEFAULT_DEVICE_LIMIT; i += 1) {
      const added = await addDevice(nora);
      assert.equal(added.statusCode, 200, `device ${i + 1}: ${added.body}`);
    }

    const overflow = await addDevice(nora);
    assert.equal(overflow.statusCode, 409);
    assert.equal(overflow.json().error, 'too_many_devices');
  });
});

function response(r: { statusCode: number; body: string }): string {
  return `${r.statusCode}: ${r.body}`;
}

/**
 * What a client may and may not assert about its own entitlement.
 *
 * The rule holds for all four distributions: entitlement is the server's to
 * decide. A build anyone can compile with the activation screen deleted must
 * not be able to talk its way past the gate, and a store build must not be able
 * to claim a purchase nobody verified.
 */
describe('the entitlement boundary', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('no client-facing route lets an account declare itself licensed', async () => {
    const routes = h.app.printRoutes({ commonPrefix: false });
    const licenseRoutes = routes
      .split('\n')
      .filter((line) => line.includes('license'))
      .join('\n');

    assert.ok(licenseRoutes.includes('redeem'), 'redemption exists');
    assert.equal(
      /grant|activate|entitle|unlock/i.test(licenseRoutes),
      false,
      'and nothing that would let a client set its own entitlement',
    );
  });

  it('the shapes a modified client might try are not routes', async () => {
    const fresh = await registerUser(h.app, 'selfdeclarer');

    for (const attempt of [
      { method: 'POST' as const, url: '/v1/licenses/me' },
      { method: 'PUT' as const, url: '/v1/licenses/me' },
      { method: 'POST' as const, url: '/v1/licenses/activate' },
    ]) {
      const answer = await h.app.inject({
        ...attempt,
        headers: bearer(fresh),
        payload: {},
      });
      assert.ok(
        answer.statusCode === 404 || answer.statusCode === 405,
        `${attempt.method} ${attempt.url} answered ${answer.statusCode}`,
      );
    }

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: bearer(fresh),
    });
    assert.equal(status.json().licensed, false, 'and it is still unlicensed');
  });

  it('a store purchase cannot be claimed, because nothing verifies one yet', async () => {
    // Deliberately asserting an absence. The schema has `source` values for
    // apple and google and there is no route that sets them: verifying a
    // receipt needs credentials this deployment does not have, and a route that
    // accepted one without checking would be worse than no route at all — a
    // free pass wearing a lock. See docs/distribution.md.
    const routes = h.app.printRoutes({ commonPrefix: false });
    assert.equal(
      /receipt|purchase|subscription/i.test(routes),
      false,
      'no purchase-verification endpoint exists yet',
    );
  });

  it('a licence follows the account, so a new phone keeps it', async () => {
    const owner = await registerUser(h.app, 'newphone');
    const key = await issue(h, 'order-new-phone');
    const redeemed = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(owner),
      payload: { licenseKey: key },
    });
    assert.equal(redeemed.statusCode, 200, redeemed.body);

    // The old handset is gone; a replacement signs in to the same account.
    const replacement = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: owner.username,
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(replacement.statusCode, 200, replacement.body);

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: { authorization: `Bearer ${replacement.json().token}` },
    });
    assert.equal(status.statusCode, 200, status.body);
    assert.equal(status.json().licensed, true, "the entitlement is the account's");
  });

  it('and a redeemed key cannot be used again by somebody else', async () => {
    const owner = await registerUser(h.app, 'newphone2');
    const key = await issue(h, 'order-new-phone-2');
    await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(owner),
      payload: { licenseKey: key },
    });

    const opportunist = await registerUser(h.app, 'opportunist');
    const stolen = await h.app.inject({
      method: 'POST',
      url: '/v1/licenses/redeem',
      headers: bearer(opportunist),
      payload: { licenseKey: key },
    });

    assert.ok(stolen.statusCode >= 400, stolen.body);
    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/licenses/me',
      headers: bearer(opportunist),
    });
    assert.equal(status.json().licensed, false);
  });
});
