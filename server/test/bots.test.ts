import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Bots.
 *
 * Three properties are under test, and they are the three that matter if this
 * feature is wrong: only an owner can touch their bot, a revoked token is dead
 * immediately, and a bot cannot write to somebody who has not written to it.
 */
describe('bots', () => {
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

  const createBot = async (user: TestUser, username: string, name = 'Helper') => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(user),
      payload: { name, username },
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; username: string };
  };

  const tokenFor = async (user: TestUser, botId: string) => {
    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/bots/${botId}/token`,
      headers: bearer(user),
    });
    assert.equal(response.statusCode, 200, response.body);
    return (response.json() as { token: string }).token;
  };

  const asBot = (token: string) => ({ authorization: `Bearer ${token}` });

  describe('@botcreator is reserved', () => {
    it('cannot be registered by an ordinary account', async () => {
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/accounts',
        payload: {
          username: 'botcreator',
          password: 'correct-horse-battery',
          device: (await import('./helpers.js')).deviceBody(
            (await import('./helpers.js')).deviceFixture(),
          ),
        },
      });
      assert.equal(response.statusCode, 409);
    });

    it('nor can the other reserved names', async () => {
      const { deviceBody, deviceFixture } = await import('./helpers.js');
      for (const username of ['support', 'admin', 'privio', 'system']) {
        const response = await h.app.inject({
          method: 'POST',
          url: '/v1/accounts',
          payload: {
            username,
            password: 'correct-horse-battery',
            device: deviceBody(deviceFixture()),
          },
        });
        assert.equal(response.statusCode, 409, username);
      }
    });

    it('exists as an account nobody can sign into', async () => {
      const { rows } = await pool.query<{ password_hash: string; is_bot: boolean }>(
        `SELECT password_hash, is_bot FROM accounts WHERE username = 'botcreator'`,
      );
      assert.equal(rows.length, 1);
      assert.equal(rows[0]!.is_bot, true);
      // `!` is not a valid Argon2 encoding, so `verifySecret` throws and is
      // caught as false — there is no password that opens this account.
      const login = await h.app.inject({
        method: 'POST',
        url: '/v1/sessions',
        payload: {
          username: 'botcreator',
          password: '!',
          device: (await import('./helpers.js')).deviceBody(
            (await import('./helpers.js')).deviceFixture(),
          ),
        },
      });
      assert.equal(login.statusCode, 401);
    });
  });

  describe('a bot belongs to its owner', () => {
    it('is listed for its owner and for nobody else', async () => {
      const bot = await createBot(alice, 'alicebot');

      const mine = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(alice) });
      assert.ok((mine.json().bots as { id: string }[]).some((row) => row.id === bot.id));

      const theirs = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(bob) });
      assert.equal((theirs.json().bots as unknown[]).length, 0);
    });

    it('refuses every write from somebody else', async () => {
      const bot = await createBot(alice, 'ownedbot');
      const attempts = [
        { method: 'PATCH' as const, url: `/v1/bots/${bot.id}`, payload: { name: 'Stolen' } },
        { method: 'DELETE' as const, url: `/v1/bots/${bot.id}` },
        { method: 'POST' as const, url: `/v1/bots/${bot.id}/token` },
        { method: 'DELETE' as const, url: `/v1/bots/${bot.id}/token` },
      ];
      for (const attempt of attempts) {
        const response = await h.app.inject({ ...attempt, headers: bearer(bob) });
        assert.equal(response.statusCode, 404, `${attempt.method} ${attempt.url}`);
      }
    });

    it('cannot take a reserved username', async () => {
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/bots',
        headers: bearer(alice),
        payload: { name: 'Impostor', username: 'botcreator' },
      });
      assert.equal(response.statusCode, 409);
    });
  });

  describe('tokens', () => {
    it('authenticate the bot and nothing else', async () => {
      const bot = await createBot(alice, 'tokenbot');
      const token = await tokenFor(alice, bot.id);

      const me = await h.app.inject({ method: 'GET', url: '/v1/bot/me', headers: asBot(token) });
      assert.equal(me.statusCode, 200);
      assert.equal(me.json().username, 'tokenbot');

      // A token is not a session: it cannot reach the owner's routes.
      const asOwner = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: asBot(token) });
      assert.equal(asOwner.statusCode, 401);
    });

    it('stop working the moment they are revoked', async () => {
      const bot = await createBot(alice, 'revokebot');
      const token = await tokenFor(alice, bot.id);

      const before = await h.app.inject({ method: 'GET', url: '/v1/bot/me', headers: asBot(token) });
      assert.equal(before.statusCode, 200);

      const revoked = await h.app.inject({
        method: 'DELETE',
        url: `/v1/bots/${bot.id}/token`,
        headers: bearer(alice),
      });
      assert.equal(revoked.json().revoked, 1);

      const after = await h.app.inject({ method: 'GET', url: '/v1/bot/me', headers: asBot(token) });
      assert.equal(after.statusCode, 401, 'a revoked token must be dead at once');
    });

    it('are replaced, not added to, when a new one is issued', async () => {
      const bot = await createBot(alice, 'rotatebot');
      const first = await tokenFor(alice, bot.id);
      const second = await tokenFor(alice, bot.id);
      assert.notEqual(first, second);

      // Rotating after a leak has to stop the leaked one. A "new token" that
      // left the old one live would be an extra key, not a replacement.
      const old = await h.app.inject({ method: 'GET', url: '/v1/bot/me', headers: asBot(first) });
      assert.equal(old.statusCode, 401);
      const fresh = await h.app.inject({ method: 'GET', url: '/v1/bot/me', headers: asBot(second) });
      assert.equal(fresh.statusCode, 200);
    });

    it('are never stored in the clear', async () => {
      const bot = await createBot(alice, 'digestbot');
      const token = await tokenFor(alice, bot.id);
      const { rows } = await pool.query<{ token_hash: Buffer }>(
        'SELECT token_hash FROM bot_tokens WHERE bot_id = $1 AND revoked_at IS NULL',
        [bot.id],
      );
      assert.equal(rows.length, 1);
      // Bytes, like every other credential digest here, and 32 of them: a
      // SHA-256 and not the token with something done to it.
      assert.ok(Buffer.isBuffer(rows[0]!.token_hash));
      assert.equal(rows[0]!.token_hash.length, 32);
      // Whatever encoding somebody reads it back in, the token is not in it.
      assert.ok(!rows[0]!.token_hash.toString('utf8').includes(token));
      assert.ok(!rows[0]!.token_hash.toString('base64').includes(token));
      assert.ok(!rows[0]!.token_hash.toString('hex').includes(token));
    });

    it('a made-up token is refused', async () => {
      const response = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/me',
        headers: asBot('not-a-real-token-at-all'),
      });
      assert.equal(response.statusCode, 401);
    });
  });

  describe('a bot may not open a conversation', () => {
    it('is refused until the person has written first', async () => {
      const bot = await createBot(alice, 'politebot');
      const token = await tokenFor(alice, bot.id);

      const unsolicited = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(token),
        payload: { to: bob.accountId, text: 'buy my thing' },
      });
      assert.equal(unsolicited.statusCode, 403);
      assert.equal(unsolicited.json().error, 'not_contacted');

      // Bob writes to it, which is what opens the return path.
      await pool.query(
        `INSERT INTO bot_messages (bot_id, account_id, author, body) VALUES ($1, $2, 'user', $3)`,
        [bot.id, bob.accountId, '/start'],
      );
      await pool.query('INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)', [
        bot.id,
        bob.accountId,
      ]);

      const replied = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(token),
        payload: { to: bob.accountId, text: 'hello' },
      });
      assert.equal(replied.statusCode, 200);
    });

    it('is shut out again when the person blocks it', async () => {
      const bot = await createBot(alice, 'blockedbot');
      const token = await tokenFor(alice, bot.id);
      await pool.query('INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)', [
        bot.id,
        bob.accountId,
      ]);

      const allowed = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(token),
        payload: { to: bob.accountId, text: 'hi' },
      });
      assert.equal(allowed.statusCode, 200);

      await pool.query(
        'UPDATE bot_contacts SET blocked_at = now() WHERE bot_id = $1 AND account_id = $2',
        [bot.id, bob.accountId],
      );

      const blocked = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(token),
        payload: { to: bob.accountId, text: 'hi again' },
      });
      assert.equal(blocked.statusCode, 403);
    });
  });

  describe('updates', () => {
    it('are delivered once and only once', async () => {
      const bot = await createBot(alice, 'pollbot');
      const token = await tokenFor(alice, bot.id);
      await pool.query('INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)', [
        bot.id,
        bob.accountId,
      ]);
      for (const text of ['one', 'two']) {
        await pool.query(
          `INSERT INTO bot_messages (bot_id, account_id, author, body) VALUES ($1, $2, 'user', $3)`,
          [bot.id, bob.accountId, text],
        );
      }

      const first = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/updates?timeout=0',
        headers: asBot(token),
      });
      const updates = first.json().updates as { text: string }[];
      assert.deepEqual(updates.map((u) => u.text), ['one', 'two']);

      // Taken, so a second poll sees nothing rather than the same two again.
      const second = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/updates?timeout=0',
        headers: asBot(token),
      });
      assert.deepEqual(second.json().updates, []);
    });

    it('do not include what the bot itself said', async () => {
      const bot = await createBot(alice, 'echobot');
      const token = await tokenFor(alice, bot.id);
      await pool.query(
        `INSERT INTO bot_messages (bot_id, account_id, author, body) VALUES ($1, $2, 'bot', 'mine')`,
        [bot.id, bob.accountId],
      );
      const response = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/updates?timeout=0',
        headers: asBot(token),
      });
      assert.deepEqual(response.json().updates, []);
    });

    it('reach only the bot they belong to', async () => {
      const mine = await createBot(alice, 'minebot');
      const theirs = await createBot(bob, 'theirsbot');
      const theirToken = await tokenFor(bob, theirs.id);
      await pool.query(
        `INSERT INTO bot_messages (bot_id, account_id, author, body) VALUES ($1, $2, 'user', 'secret')`,
        [mine.id, bob.accountId],
      );

      const response = await h.app.inject({
        method: 'GET',
        url: '/v1/bot/updates?timeout=0',
        headers: asBot(theirToken),
      });
      assert.deepEqual(response.json().updates, [], 'one bot must not read another’s messages');
    });
  });

  describe('the assistant', () => {
    const say = async (user: TestUser, text: string) => {
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/botcreator/say',
        headers: bearer(user),
        payload: { text },
      });
      assert.equal(response.statusCode, 200, response.body);
      return response.json() as { text: string; action?: { kind: string; botId?: string } };
    };

    it('walks through creating a bot', async () => {
      const carol = await registerUser(h.app, 'carol');

      const start = await say(carol, '/start');
      assert.match(start.text, /\/newbot/);

      await say(carol, '/newbot');
      await say(carol, 'Weather');
      const done = await say(carol, 'carolweatherbot');

      assert.match(done.text, /@carolweatherbot/);
      // The token is not in the message. It is an instruction to the app to
      // open its protected sheet and fetch one over the ordinary API.
      assert.equal(done.action?.kind, 'showToken');
      assert.doesNotMatch(done.text, /[A-Za-z0-9_-]{40,}/, 'no token in the chat text');

      const listed = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(carol) });
      assert.ok(
        (listed.json().bots as { username: string }[]).some((b) => b.username === 'carolweatherbot'),
      );
    });

    it('refuses a username that is taken or reserved', async () => {
      const dave = await registerUser(h.app, 'dave');
      await say(dave, '/newbot');
      await say(dave, 'Impostor');
      const refused = await say(dave, 'botcreator');
      assert.match(refused.text, /not available|taken/i);
    });

    it('never puts a token in a message, even for /token', async () => {
      const erin = await registerUser(h.app, 'erin');
      await say(erin, '/newbot');
      await say(erin, 'Tokens');
      await say(erin, 'erintokenbot');

      const asked = await say(erin, '/token');
      assert.equal(asked.action?.kind, 'showToken');
      assert.doesNotMatch(asked.text, /[A-Za-z0-9_-]{40,}/);
    });

    it('will not act on somebody else’s bot', async () => {
      const frank = await registerUser(h.app, 'frank');
      await say(frank, '/newbot');
      await say(frank, 'Frank’s');
      await say(frank, 'frankbot');

      const grace = await registerUser(h.app, 'grace');
      const attempt = await say(grace, '/revoke @frankbot');
      assert.match(attempt.text, /no bots yet|no bot called/i);

      // And Frank's token still works.
      const { rows } = await pool.query<{ n: string }>(
        `SELECT count(*) AS n FROM bot_tokens t
           JOIN accounts a ON a.id = t.bot_id
          WHERE a.username = 'frankbot' AND t.revoked_at IS NOT NULL`,
      );
      assert.equal(Number(rows[0]!.n), 0, 'grace must not have revoked frank’s token');
    });

    it('deletes only after the username is typed back', async () => {
      const heidi = await registerUser(h.app, 'heidi');
      await say(heidi, '/newbot');
      await say(heidi, 'Doomed');
      await say(heidi, 'heidibot');

      await say(heidi, '/deletebot');
      const wrong = await say(heidi, 'something else');
      assert.match(wrong.text, /not the username/i);

      const stillThere = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(heidi) });
      assert.equal((stillThere.json().bots as unknown[]).length, 1);

      await say(heidi, '/deletebot');
      const gone = await say(heidi, 'heidibot');
      assert.match(gone.text, /is gone/i);

      const after = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(heidi) });
      assert.equal((after.json().bots as unknown[]).length, 0);
    });

    it('sets commands from the block it asks for', async () => {
      const ivan = await registerUser(h.app, 'ivan');
      await say(ivan, '/newbot');
      await say(ivan, 'Commands');
      await say(ivan, 'ivanbot');

      await say(ivan, '/setcommands');
      const set = await say(ivan, 'start - begin\nhelp - show help');
      assert.match(set.text, /2 commands/);

      const listed = await h.app.inject({ method: 'GET', url: '/v1/bots', headers: bearer(ivan) });
      const bot = (listed.json().bots as { commands: { command: string }[] }[])[0]!;
      assert.deepEqual(bot.commands.map((c) => c.command), ['start', 'help']);
    });
  });

  describe('a bot conversation is not in the encrypted path', () => {
    it('never writes to the envelopes table', async () => {
      const bot = await createBot(alice, 'plainbot');
      const token = await tokenFor(alice, bot.id);
      await pool.query('INSERT INTO bot_contacts (bot_id, account_id) VALUES ($1, $2)', [
        bot.id,
        bob.accountId,
      ]);

      const { rows: before } = await pool.query<{ n: string }>('SELECT count(*) AS n FROM envelopes');
      await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(token),
        payload: { to: bob.accountId, text: 'plain text, and it says so' },
      });
      const { rows: after } = await pool.query<{ n: string }>('SELECT count(*) AS n FROM envelopes');

      // The whole reason `bot_messages` is its own table: what the server can
      // read stays answerable by looking at the schema. If this ever starts
      // writing envelopes, the two paths have been merged and the guarantee
      // that `envelopes` holds only ciphertext is gone.
      assert.equal(after[0]!.n, before[0]!.n);
    });
  });
});
