import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { after, before, beforeEach, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import * as phone from '../src/services/phone.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * A phone number is optional, provable, and not an identity.
 *
 * The tests below are the brief's own list: registering without a number, a
 * verification that works and one that does not, changing a number, removing
 * one, and — the one that matters most — that somebody who did not ask to be
 * found is not found.
 */

/** What a client sends: the number under the public context key. */
const blind = (e164: string) =>
  createHmac('sha256', phone.DISCOVERY_CONTEXT).update(e164).digest().toString('base64');

describe('phone numbers and contact discovery', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
    bob = await registerUser(h.app, 'bob');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  beforeEach(async () => {
    // Each test starts with nobody linked. Written explicitly rather than
    // relying on order: a test that depends on the one before it is a test that
    // fails for the wrong reason the day somebody reorders the file.
    await pool.query('DELETE FROM phone_links');
    await pool.query('DELETE FROM phone_verifications');
    await pool.query('DELETE FROM contact_lookup_budget');
  });

  /** Asks for a code and returns it, using the development echo. */
  const askFor = async (user: TestUser, number: string) => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/phone/verifications',
      headers: bearer(user),
      payload: { phone: number },
    });
    assert.equal(response.statusCode, 200, response.body);
    const body = response.json() as { code?: string; developmentStub?: boolean; hint: string };
    assert.equal(body.developmentStub, true, 'the test harness uses the development stub');
    return body;
  };

  const verify = (user: TestUser, code: string) =>
    h.app.inject({ method: 'POST', url: '/v1/phone', headers: bearer(user), payload: { code } });

  const link = async (user: TestUser, number: string) => {
    const asked = await askFor(user, number);
    const done = await verify(user, asked.code!);
    assert.equal(done.statusCode, 200, done.body);
    return done.json();
  };

  const setDiscoverable = (user: TestUser, discoverable: boolean) =>
    h.app.inject({
      method: 'PUT',
      url: '/v1/phone/discoverable',
      headers: bearer(user),
      payload: { discoverable },
    });

  const discover = (user: TestUser, numbers: string[]) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/contacts/discover',
      headers: bearer(user),
      payload: { blinded: numbers.map(blind) },
    });

  describe('an account works without one', () => {
    it('registers and reads its own account with no number at all', async () => {
      const carol = await registerUser(h.app, 'carol_nophone');
      const me = await h.app.inject({
        method: 'GET',
        url: '/v1/phone',
        headers: bearer(carol),
      });

      assert.equal(me.statusCode, 200);
      assert.equal(me.json().linked, false);
      assert.equal(me.json().hint, null);
      assert.equal(me.json().discoverable, false);
    });

    it('registration takes no phone field and refuses none', async () => {
      // The registration route is unchanged: there is no number in it, so an
      // account made the ordinary way is a complete account. Registered through
      // the same helper every other test uses, so this cannot pass against a
      // fixture that has drifted from the real request shape.
      const made = await registerUser(h.app, 'nophone_at_all');
      assert.ok(made.accountId);

      const me = await h.app.inject({
        method: 'GET',
        url: '/v1/phone',
        headers: bearer(made),
      });
      assert.equal(me.json().linked, false);
    });
  });

  describe('verifying a number', () => {
    it('links it, and leaves it not discoverable', async () => {
      const result = await link(alice, '+49 151 23456789');

      assert.equal(result.linked, true);
      // The hint, and never the number: the server does not have the number.
      assert.equal(result.hint, '+49 … 89');
      assert.equal(
        result.discoverable,
        false,
        'attaching a number is not consent to be found by it',
      );
    });

    it('stores no phone number anywhere', async () => {
      await link(alice, '+49 151 23456789');

      // The column is bytea and the value is a keyed hash. Asserting the *type*
      // rather than the contents is what makes this hold when somebody changes
      // the hashing: a text column here would be a number in the clear.
      const { rows } = await pool.query<{ data_type: string }>(
        `SELECT data_type FROM information_schema.columns
          WHERE table_name = 'phone_links' AND column_name = 'discovery_hash'`,
      );
      assert.equal(rows[0]?.data_type, 'bytea');

      // And nothing anywhere in the row resembles the number.
      const { rows: stored } = await pool.query('SELECT * FROM phone_links');
      const dump = JSON.stringify(stored);
      assert.ok(!dump.includes('23456789'), 'the number must not be in the row');
      assert.ok(!dump.includes('4915123456789'));
    });

    it('a wrong code does not link, and spends an attempt', async () => {
      await askFor(alice, '+49 151 23456789');

      const wrong = await verify(alice, '000000');
      assert.equal(wrong.statusCode, 400);
      assert.equal(wrong.json().error, 'wrong_code');

      const { rows } = await pool.query<{ attempts: number }>(
        'SELECT attempts FROM phone_verifications WHERE consumed_at IS NULL',
      );
      assert.equal(rows[0]?.attempts, 1);

      const me = await h.app.inject({ method: 'GET', url: '/v1/phone', headers: bearer(alice) });
      assert.equal(me.json().linked, false);
    });

    it('gives up after the attempt limit rather than allowing forever', async () => {
      const asked = await askFor(alice, '+49 151 23456789');

      for (let i = 0; i < phone.PHONE_LIMITS.maxAttempts; i++) {
        const response = await verify(alice, '000000');
        assert.equal(response.statusCode, 400, `attempt ${i}`);
      }

      // Even the right code, now: the window is spent.
      const correct = await verify(alice, asked.code!);
      assert.equal(correct.statusCode, 429);
      assert.equal(correct.json().error, 'too_many_attempts');
    });

    it('an expired code is refused', async () => {
      const asked = await askFor(alice, '+49 151 23456789');
      await pool.query('UPDATE phone_verifications SET expires_at = now() - interval \'1 minute\'');

      const response = await verify(alice, asked.code!);
      assert.equal(response.statusCode, 400);
      assert.equal(response.json().error, 'code_expired');
    });

    it('stores the code as a digest, not as six digits', async () => {
      const asked = await askFor(alice, '+49 151 23456789');
      const { rows } = await pool.query<{ code_hash: string }>(
        'SELECT code_hash FROM phone_verifications WHERE consumed_at IS NULL',
      );
      assert.ok(rows[0]!.code_hash.startsWith('$argon2'), 'Argon2id, like every other credential');
      assert.ok(!rows[0]!.code_hash.includes(asked.code!));
    });

    it('resending too soon is refused', async () => {
      await askFor(alice, '+49 151 23456789');
      const again = await h.app.inject({
        method: 'POST',
        url: '/v1/phone/verifications',
        headers: bearer(alice),
        payload: { phone: '+49 151 23456789' },
      });
      assert.equal(again.statusCode, 429);
      assert.equal(again.json().error, 'resend_too_soon');
    });

    it('refuses a number that is not one', async () => {
      for (const bad of ['hello', '12345', '+', '+49', '+999999 123', '0151 2345678']) {
        const response = await h.app.inject({
          method: 'POST',
          url: '/v1/phone/verifications',
          headers: bearer(alice),
          payload: { phone: bad },
        });
        assert.equal(response.statusCode, 400, `"${bad}" should be refused`);
        assert.equal(response.json().error, 'invalid_phone', `"${bad}"`);
      }
    });
  });

  describe('being found, and not being found', () => {
    it('a verified but not discoverable number is never a match', async () => {
      await link(alice, '+49 151 23456789');
      // Deliberately not switching discoverability on.

      const found = await discover(bob, ['+4915123456789']);
      assert.equal(found.statusCode, 200);
      assert.deepEqual(
        found.json().matches,
        [],
        'this is the rule the whole feature stands on',
      );
    });

    it('a discoverable number is found, and answers which entry it was', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);

      const found = await discover(bob, ['+4915123456789', '+4915100000000']);
      const matches = found.json().matches as { username: string; blinded: string }[];

      assert.equal(matches.length, 1);
      assert.equal(matches[0]!.username, 'alice');
      // Answered against the *server's* hash of the submitted blind, so the
      // client can line it up with its own address book entry.
      assert.ok(typeof matches[0]!.blinded === 'string');
    });

    it('switching discoverability off stops the matching at once', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);
      assert.equal((await discover(bob, ['+4915123456789'])).json().matches.length, 1);

      await setDiscoverable(alice, false);
      assert.deepEqual((await discover(bob, ['+4915123456789'])).json().matches, []);
    });

    it('removing the number deletes the server-side link', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);

      const removed = await h.app.inject({
        method: 'DELETE',
        url: '/v1/phone',
        headers: bearer(alice),
      });
      assert.equal(removed.statusCode, 200);

      const { rowCount } = await pool.query('SELECT 1 FROM phone_links WHERE account_id = $1', [
        alice.accountId,
      ]);
      assert.equal(rowCount, 0, 'the row goes, not a flag on it');
      assert.deepEqual((await discover(bob, ['+4915123456789'])).json().matches, []);
    });

    it('a changed number has to be made discoverable again', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);

      await link(alice, '+49 151 99999999');

      const me = await h.app.inject({ method: 'GET', url: '/v1/phone', headers: bearer(alice) });
      assert.equal(me.json().hint, '+49 … 99');
      assert.equal(
        me.json().discoverable,
        false,
        'consent given for the old number does not carry to a new one',
      );
      assert.deepEqual((await discover(bob, ['+4915199999999'])).json().matches, []);
    });

    it('a number taken over by somebody else does not merge the accounts', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);

      // Bob proves the same number — a recycled SIM.
      await link(bob, '+49 151 23456789');

      // Alice keeps her account and everything in it; she simply is no longer
      // findable by that number.
      const aliceNow = await h.app.inject({
        method: 'GET',
        url: '/v1/phone',
        headers: bearer(alice),
      });
      assert.equal(aliceNow.statusCode, 200);
      assert.equal(aliceNow.json().linked, false);

      const aliceAccount = await h.app.inject({
        method: 'GET',
        url: '/v1/accounts/me',
        headers: bearer(alice),
      });
      assert.equal(aliceAccount.statusCode, 200, 'the account itself is untouched');
      assert.equal(aliceAccount.json().username, 'alice');
    });

    it('never returns the account doing the asking', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);

      const found = await discover(alice, ['+4915123456789']);
      assert.deepEqual(found.json().matches, []);
    });

    it('does not return somebody who blocked you', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);
      await h.app.inject({
        method: 'POST',
        url: '/v1/blocks',
        headers: bearer(alice),
        payload: { accountId: bob.accountId },
      });

      assert.deepEqual((await discover(bob, ['+4915123456789'])).json().matches, []);
    });

    it('writes down nothing about what was asked', async () => {
      await link(alice, '+49 151 23456789');
      await setDiscoverable(alice, true);
      await discover(bob, ['+4915123456789', '+4915100000000', '+12025550123']);

      // The only thing a lookup leaves behind is how much of the budget it
      // spent. Everything else about the question is gone.
      const { rows } = await pool.query<{ table_name: string }>(
        `SELECT table_name FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name LIKE '%lookup%'`,
      );
      assert.deepEqual(rows.map((r) => r.table_name), ['contact_lookup_budget']);

      const { rows: budget } = await pool.query('SELECT * FROM contact_lookup_budget');
      assert.equal(budget.length, 1);
      assert.equal(budget[0]!.looked_up, 3);
      assert.ok(!Object.keys(budget[0]!).some((key) => key.includes('hash')));
    });

    it('refuses a batch bigger than the per-request cap', async () => {
      const many = Array.from({ length: phone.PHONE_LIMITS.lookupsPerRequest + 1 }, (_, i) =>
        blind(`+4915100${String(i).padStart(5, '0')}`),
      );
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/contacts/discover',
        headers: bearer(bob),
        payload: { blinded: many },
      });
      assert.equal(response.statusCode, 400);
    });

    it('refuses anything that is not a 32-byte hash', async () => {
      // A client that sent a plaintext number here should be refused rather
      // than quietly hashed and answered.
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/contacts/discover',
        headers: bearer(bob),
        payload: { blinded: ['+4915123456789'] },
      });
      assert.equal(response.statusCode, 400);
    });

    it('stops answering once the daily budget is spent', async () => {
      await pool.query(
        `INSERT INTO contact_lookup_budget (account_id, day, looked_up)
         VALUES ($1, current_date, $2)`,
        [bob.accountId, phone.PHONE_LIMITS.lookupsPerDay],
      );

      const response = await discover(bob, ['+4915123456789']);
      assert.equal(response.statusCode, 429);
      assert.equal(response.json().error, 'lookup_budget_spent');
    });
  });

  describe('normalising what people type', () => {
    it('accepts the shapes people actually write', () => {
      for (const written of [
        '+49 151 23456789',
        '+49-151-23456789',
        '+49 (151) 23456789',
        '0049 151 23456789',
        '+4915123456789',
      ]) {
        assert.equal(
          phone.normalisePhone(written)?.e164,
          '+4915123456789',
          `"${written}"`,
        );
      }
    });

    it('refuses a number with no country, rather than guessing one', () => {
      // Guessing would quietly attach somebody to a number in a country they
      // have never been to.
      assert.equal(phone.normalisePhone('0151 23456789'), null);
      assert.equal(phone.normalisePhone('151 23456789'), null);
    });

    it('the hint says the country and two digits, and nothing else', () => {
      const hint = phone.normalisePhone('+1 202 555 0123')?.hint;
      assert.equal(hint, '+1 … 23');
      assert.ok(!hint!.includes('5550'));
    });

    it('the client and the server blind a number identically', () => {
      // The two implementations have to agree exactly or nothing ever matches,
      // and the failure looks like "discovery finds nobody" rather than like a
      // hashing bug. So both are pinned to the same literal: this one, and
      // `app/test/phone_test.dart`. Changing one side without the other turns
      // one of the two red.
      const vector = 'S8FSbBRRbtPyuNx83jrw3rU0g5BqVqrtctNJhuZuHVw=';
      assert.equal(phone.blindPhone('+4915123456789').toString('base64'), vector);
      assert.equal(blind('+4915123456789'), vector);
    });
  });
});
