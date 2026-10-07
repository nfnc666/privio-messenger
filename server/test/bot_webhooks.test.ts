import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { createServer, type Server } from 'node:http';
import { pool } from '../src/db/pool.js';
import {
  deliverOnce,
  dueNow,
  postDelivery,
  signatureFor,
  signatureMatches,
  type WebhookRow,
} from '../src/services/bot_webhooks.js';
import { takeUpdates } from '../src/services/bots.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Bot webhooks.
 *
 * The URL is the dangerous part: a bot owner chooses it and this server then
 * fetches it, from inside whatever network the server runs in. So most of this
 * is about what is refused, and the refusals are the tests that matter.
 *
 * What is **not** covered here is a real delivery to a real public URL. The
 * guard refuses private addresses, which is every address a test can listen
 * on, and weakening it for a test would be testing something other than what
 * ships. `deliverOnce` is exercised against a local receiver by calling it
 * directly, which skips the resolve check and is stated rather than hidden.
 */
describe('a bot webhook', () => {
  let h: TestHarness;
  let owner: TestUser;
  let botId: string;
  let botToken: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'hookowner');

    const bot = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(owner),
      payload: { name: 'Hooked', username: 'hookedbot' },
    });
    botId = bot.json().id as string;

    const token = await h.app.inject({
      method: 'POST',
      url: `/v1/bots/${botId}/token`,
      headers: bearer(owner),
    });
    botToken = token.json().token as string;
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = () => ({ authorization: `Bearer ${botToken}` });

  const register = (url: string) =>
    h.app.inject({
      method: 'PUT',
      url: '/v1/bot/webhook',
      headers: asBot(),
      payload: { url },
    });

  it('refuses everything that is not a public https URL', async () => {
    const refused = [
      'http://example.com/hook',
      'https://127.0.0.1/hook',
      'https://10.0.0.5/hook',
      'https://192.168.1.1/hook',
      'https://172.16.0.1/hook',
      'https://169.254.169.254/latest/meta-data/',
      'https://[::1]/hook',
      'https://[::ffff:127.0.0.1]/hook',
      'https://user:password@example.com/hook',
      'not-a-url',
    ];
    for (const url of refused) {
      const response = await register(url);
      assert.equal(response.statusCode, 400, `${url} was accepted`);
      assert.equal(response.json().error, 'invalid_webhook', url);
    }
  });

  it('and does not say what a private name resolved to', async () => {
    // Answering that in detail turns this route into a network scanner for
    // whoever holds a bot token.
    const response = await register('https://localhost/hook');
    assert.equal(response.statusCode, 400);
    const said = JSON.stringify(response.json());
    assert.ok(!said.includes('127.0.0.1'), said);
    assert.ok(!said.includes('::1'), said);
  });

  it('a session cannot register one, and a bot token cannot reach the owner routes',
    async () => {
      // The two credentials are not interchangeable, which is what stops a
      // leaked webhook receiver from becoming a way to manage the bot.
      const asOwner = await h.app.inject({
        method: 'PUT',
        url: '/v1/bot/webhook',
        headers: bearer(owner),
        payload: { url: 'https://example.com/hook' },
      });
      assert.equal(asOwner.statusCode, 401);

      const listing = await h.app.inject({
        method: 'GET',
        url: '/v1/bots',
        headers: asBot(),
      });
      assert.equal(listing.statusCode, 401);
    });

  it('the secret is shown once and never read back', async () => {
    const set = await register('https://example.com/hook');
    assert.equal(set.statusCode, 200, set.body);
    const secret = set.json().secret as string;
    assert.equal(secret.length, 64, 'thirty-two bytes as hex');

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/bot/webhook',
      headers: asBot(),
    });
    assert.equal(status.statusCode, 200);
    assert.equal(status.json().url, 'https://example.com/hook');
    assert.equal(
      'secret' in status.json(),
      false,
      'a secret that can be fetched again has two places to leak from',
    );
  });

  it('registering again replaces the secret rather than adding one', async () => {
    const first = (await register('https://example.com/one')).json().secret as string;
    const second = (await register('https://example.com/two')).json().secret as string;
    assert.notEqual(first, second);

    const { rows } = await pool.query<{ n: string }>(
      'SELECT count(*) AS n FROM bot_webhooks WHERE bot_id = $1',
      [botId],
    );
    assert.equal(Number(rows[0]!.n), 1);
  });

  it('removing it leaves the bot polling, with nothing lost', async () => {
    const removed = await h.app.inject({
      method: 'DELETE',
      url: '/v1/bot/webhook',
      headers: asBot(),
    });
    assert.equal(removed.statusCode, 200);

    const status = await h.app.inject({
      method: 'GET',
      url: '/v1/bot/webhook',
      headers: asBot(),
    });
    assert.equal(status.json().url, null);
  });

  describe('the signature a receiver checks', () => {
    const secret = Buffer.from('a'.repeat(64), 'hex');

    it('matches what the same inputs produce', () => {
      const signature = signatureFor(secret, '1700000000000', '{"updates":[]}');
      assert.ok(signatureMatches(secret, '1700000000000', '{"updates":[]}', signature));
    });

    it('and not a different secret, body or timestamp', () => {
      const signature = signatureFor(secret, '1700000000000', '{"updates":[]}');
      const other = Buffer.from('b'.repeat(64), 'hex');
      assert.equal(signatureMatches(other, '1700000000000', '{"updates":[]}', signature), false);
      assert.equal(signatureMatches(secret, '1700000000000', '{"updates":[1]}', signature), false);
      assert.equal(signatureMatches(secret, '1700000000001', '{"updates":[]}', signature), false);
    });

    it('covers the timestamp, so a delivery cannot be replayed later', () => {
      // Signing the body alone would make every captured delivery valid
      // forever.
      const now = signatureFor(secret, '1700000000000', 'x');
      const later = signatureFor(secret, '1800000000000', 'x');
      assert.notEqual(now, later);
    });
  });

  describe('backing off', () => {
    it('a healthy hook is due every tick', () => {
      assert.equal(dueNow(0, 0), true);
      assert.equal(dueNow(0, 12_345), true);
    });

    it('a failing one is tried less and less often', () => {
      // Every 2^n ticks, so eight failures means once every 256 seconds
      // rather than once a second.
      let tries = 0;
      for (let tick = 0; tick < 1000; tick++) {
        if (dueNow(8, tick * 1000)) tries += 1;
      }
      assert.ok(tries < 10, `tried ${tries} times in a thousand ticks`);
      assert.ok(tries > 0, 'and still tried sometimes');
    });
  });

  describe('delivering', () => {
    let receiver: Server;
    let received: Array<{ signature: string; timestamp: string; body: string }>;
    let port: number;
    let answer = 200;

    before(async () => {
      received = [];
      receiver = createServer((request, response) => {
        let body = '';
        request.on('data', (chunk) => (body += chunk));
        request.on('end', () => {
          received.push({
            signature: String(request.headers['x-privio-signature'] ?? ''),
            timestamp: String(request.headers['x-privio-timestamp'] ?? ''),
            body,
          });
          response.writeHead(answer).end();
        });
      });
      await new Promise<void>((resolve) => receiver.listen(0, '127.0.0.1', resolve));
      port = (receiver.address() as { port: number }).port;
    });
    after(() => receiver.close());

    const hook = async (): Promise<WebhookRow> => {
      const { rows } = await pool.query<{ secret: Buffer; failures: number }>(
        'SELECT secret, failures FROM bot_webhooks WHERE bot_id = $1',
        [botId],
      );
      return {
        bot_id: botId,
        url: 'https://example.com/hook',
        secret: rows[0]!.secret,
        failures: rows[0]!.failures,
        disabled_at: null,
      };
    };

    it('signs the body together with the timestamp', async () => {
      answer = 200;
      await register('https://example.com/hook');
      const sent = await postDelivery(await hook(), new URL(`http://127.0.0.1:${port}/hook`), [
        { updateId: 1, text: '/help' },
      ]);
      assert.equal(sent, true);
      assert.equal(received.length, 1);

      const delivery = received[0]!;
      assert.ok(delivery.signature.startsWith('sha256='), delivery.signature);
      assert.deepEqual(JSON.parse(delivery.body), { updates: [{ updateId: 1, text: '/help' }] });
      assert.ok(
        signatureMatches(
          (await hook()).secret,
          delivery.timestamp,
          delivery.body,
          delivery.signature.slice('sha256='.length),
        ),
        'a receiver following the documented steps could not verify this',
      );
    });

    it('and carries nothing a receiver could act as the bot with', async () => {
      // A receiver is a URL the owner chose. It learns how to check a delivery
      // and no more; the token stays between the bot process and this server.
      const sent = JSON.stringify(received[0]!);
      assert.ok(!sent.includes(botToken), 'the token reached the receiver');
      assert.ok(!sent.toLowerCase().includes('authorization'), sent);
    });

    it('a refusal is counted, with the status and no headers in the note', async () => {
      answer = 500;
      received = [];
      await postDelivery(await hook(), new URL(`http://127.0.0.1:${port}/hook`), [{ updateId: 2 }]);
      assert.equal(received.length, 1);

      const { rows } = await pool.query<{ failures: number; last_status: number | null; last_error: string | null }>(
        'SELECT failures, last_status, last_error FROM bot_webhooks WHERE bot_id = $1',
        [botId],
      );
      assert.equal(rows[0]!.failures, 1);
      assert.equal(rows[0]!.last_status, 500);
      assert.equal(rows[0]!.last_error, 'HTTP 500');
    });

    it('a success clears the count again', async () => {
      answer = 200;
      await postDelivery(await hook(), new URL(`http://127.0.0.1:${port}/hook`), [{ updateId: 3 }]);
      const { rows } = await pool.query<{ failures: number }>(
        'SELECT failures FROM bot_webhooks WHERE bot_id = $1',
        [botId],
      );
      assert.equal(rows[0]!.failures, 0);
    });

    it('the address is checked again at delivery time, not only at registration',
      async () => {
        // The whole path: a hook row whose URL now points inside the network is
        // not fetched, even though it was accepted once.
        received = [];
        await h.app.inject({
          method: 'POST',
          url: `/v1/bots/${botId}/messages`,
          headers: bearer(owner),
          payload: { text: 'would be delivered' },
        });

        const inside = { ...(await hook()), url: `http://127.0.0.1:${port}/hook` };
        assert.equal(await deliverOnce(inside), false);
        assert.equal(received.length, 0, 'the delivery was made anyway');

        const { rows } = await pool.query<{ failures: number; last_error: string | null }>(
          'SELECT failures, last_error FROM bot_webhooks WHERE bot_id = $1',
          [botId],
        );
        assert.ok(rows[0]!.failures >= 1);
        assert.ok(rows[0]!.last_error, 'the owner is told nothing about why');
      });

    it('and the update it did not deliver is still there for the poller',
      async () => {
        // A refused delivery must not eat the message. `takeUpdates` runs after
        // the check, so nothing was taken.
        const { rows } = await pool.query<{ n: string }>(
          `SELECT count(*) AS n FROM bot_messages
            WHERE bot_id = $1 AND author = 'user' AND delivered_at IS NULL`,
          [botId],
        );
        assert.equal(Number(rows[0]!.n), 1);
      });

    it('a delivered update is not handed to a poller as well', async () => {
      // One update, two possible paths out. Whichever takes it first, the other
      // gets nothing: the take is a single `UPDATE … RETURNING`.
      const taken = await takeUpdates(botId, 50);
      assert.equal(taken.length, 1, 'expected the undelivered one above');
      assert.equal(taken[0]!.text, 'would be delivered');

      // The per-bot poll gate answers empty for the best part of a second, so a
      // poll straight after would be empty whatever the rows said. Wait it out,
      // otherwise this test proves nothing.
      await new Promise((resolve) => setTimeout(resolve, 1000));
      const polled = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/updates?timeout=0',
        headers: asBot(),
      });
      assert.equal(polled.statusCode, 200);
      assert.deepEqual(polled.json().updates, []);
    });
  });
});
