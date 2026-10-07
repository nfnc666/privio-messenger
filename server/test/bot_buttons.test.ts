import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { takeUpdates } from '../src/services/bots.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Buttons under a bot's message, and opening, starting and stopping a bot.
 *
 * The requirement these tests exist for: a press is attributable to one bot,
 * one message and one permitted person, and pressing twice does not make the
 * same thing happen twice.
 */
describe('using a bot', () => {
  let h: TestHarness;
  let owner: TestUser;
  let person: TestUser;
  let other: TestUser;
  let botId: string;
  let botToken: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'buttonowner');
    person = await registerUser(h.app, 'buttonperson');
    other = await registerUser(h.app, 'buttonother');

    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(owner),
      payload: { name: 'Presser', username: 'presserbot' },
    });
    botId = created.json().id as string;
    await h.app.inject({
      method: 'PATCH',
      url: `/v1/bots/${botId}`,
      headers: bearer(owner),
      payload: {
        description: 'Presses things',
        commands: [{ command: 'help', description: 'what I can do' }],
      },
    });
    botToken = (
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/token`, headers: bearer(owner) })
    ).json().token as string;
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = () => ({ authorization: `Bearer ${botToken}` });

  /**
   * Takes what is waiting for the bot.
   *
   * Waits out the per-bot poll gate first: `takeUpdates` answers empty for the
   * best part of a second after the last call, so a take straight after another
   * one would come back empty whatever the rows said and the test would prove
   * nothing.
   */
  const take = async () => {
    await new Promise((resolve) => setTimeout(resolve, 950));
    return takeUpdates(botId, 10);
  };

  /** A message from the bot to [person], with buttons. */
  const sendWithButtons = async (
    buttons: Array<{ id: string; label: string }>,
    to = person,
  ) => {
    const sent = await h.app.inject({
      method: 'POST',
      url: '/v1/bot/send',
      headers: asBot(),
      payload: { to: to.accountId, text: 'Book it?', buttons },
    });
    assert.equal(sent.statusCode, 200, sent.body);
    return sent.json().messageId as number;
  };

  const press = (messageId: number, buttonId: string, as = person) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/bots/${botId}/messages/${messageId}/press`,
      headers: bearer(as),
      payload: { buttonId },
    });

  describe('opening one', () => {
    it('shows the description and the commands, by exact username only', async () => {
      const found = await h.app.inject({
        method: 'GET',
        url: '/v1/bots/by-username/presserbot',
        headers: bearer(person),
      });
      assert.equal(found.statusCode, 200, found.body);
      assert.equal(found.json().description, 'Presses things');
      assert.deepEqual(found.json().commands, [
        { command: 'help', description: 'what I can do' },
      ]);
      assert.equal(found.json().started, false);
      assert.equal(found.json().isBot, true);

      // No prefix search: a directory of bots is a directory of operators.
      const prefix = await h.app.inject({
        method: 'GET',
        url: '/v1/bots/by-username/presser',
        headers: bearer(person),
      });
      assert.equal(prefix.statusCode, 404);
    });

    it('and is not readable without signing in', async () => {
      const out = await h.app.inject({ method: 'GET', url: `/v1/bots/${botId}/profile` });
      assert.equal(out.statusCode, 401);
    });

    it('a person is not a bot, and does not answer on this route', async () => {
      const notABot = await h.app.inject({
        method: 'GET',
        url: '/v1/bots/by-username/buttonperson',
        headers: bearer(person),
      });
      assert.equal(notABot.statusCode, 404);
    });
  });

  describe('starting and stopping', () => {
    it('a bot cannot write before it is started', async () => {
      const early = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: person.accountId, text: 'psst' },
      });
      assert.equal(early.statusCode, 403);
      assert.equal(early.json().error, 'not_contacted');
    });

    it('start licenses it, and delivers /start so it knows to greet', async () => {
      const started = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/start`,
        headers: bearer(person),
      });
      assert.equal(started.statusCode, 200, started.body);

      const updates = await take();
      assert.equal(updates.length, 1);
      assert.equal(updates[0]!.text, '/start');
      assert.equal(updates[0]!.command?.name, 'start');

      const now = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/profile`,
        headers: bearer(person),
      });
      assert.equal(now.json().started, true);
      assert.equal(now.json().stopped, false);
    });

    it('stop takes the licence away again', async () => {
      const stopped = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/stop`,
        headers: bearer(person),
      });
      assert.equal(stopped.statusCode, 200);

      const refused = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: person.accountId, text: 'still here?' },
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'not_contacted');

      const profile = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/profile`,
        headers: bearer(person),
      });
      assert.equal(profile.json().stopped, true);
    });

    it('and what was already waiting is not delivered after a stop', async () => {
      // A stop that let the queue drain would be a stop the operator still
      // hears through.
      await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(other),
        payload: { text: 'from somebody else' },
      });
      await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/stop`,
        headers: bearer(other),
      });

      const updates = await take();
      assert.equal(
        updates.some((u) => u.text === 'from somebody else'),
        false,
      );

      // Still there in the table, not deleted: they stopped the bot, they did
      // not ask for their message to be destroyed.
      const { rows } = await pool.query<{ n: string }>(
        `SELECT count(*) AS n FROM bot_messages
          WHERE bot_id = $1 AND account_id = $2 AND delivered_at IS NULL`,
        [botId, other.accountId],
      );
      assert.equal(Number(rows[0]!.n), 1);
    });

    it('writing to it again is a restart', async () => {
      const written = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(person),
        payload: { text: 'hello again' },
      });
      assert.equal(written.statusCode, 201);
      const profile = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/profile`,
        headers: bearer(person),
      });
      assert.equal(profile.json().started, true);
    });
  });

  describe('a button', () => {
    it('is drawn from what the bot sent, with what this person already pressed',
      async () => {
        const messageId = await sendWithButtons([
          { id: 'yes', label: 'Yes, book it' },
          { id: 'no', label: 'No thanks' },
        ]);

        const conversation = await h.app.inject({
          method: 'GET',
          url: `/v1/bots/${botId}/messages`,
          headers: bearer(person),
        });
        const message = (conversation.json().messages as Array<Record<string, unknown>>).find(
          (m) => m.id === messageId,
        );
        assert.ok(message, conversation.body);
        assert.deepEqual(message.buttons, [
          { id: 'yes', label: 'Yes, book it' },
          { id: 'no', label: 'No thanks' },
        ]);
        assert.deepEqual(message.pressed, []);

        assert.equal((await press(messageId, 'yes')).statusCode, 200);
        const after = await h.app.inject({
          method: 'GET',
          url: `/v1/bots/${botId}/messages`,
          headers: bearer(person),
        });
        const again = (after.json().messages as Array<Record<string, unknown>>).find(
          (m) => m.id === messageId,
        );
        assert.deepEqual(again!.pressed, ['yes']);
      });

    it('reaches the bot naming the button and the message it was under', async () => {
      const messageId = await sendWithButtons([{ id: 'ok', label: 'Fine' }]);
      assert.equal((await press(messageId, 'ok')).statusCode, 200);

      const updates = await take();
      // By message, not "the first press in the batch": an earlier test pressed
      // a button too, and its update is still in the queue behind this one.
      const button = updates.find((u) => u.button?.messageId === messageId);
      assert.ok(button, JSON.stringify(updates));
      assert.deepEqual(button.button, { id: 'ok', messageId });
      assert.equal(button.chat.accountId, person.accountId);
      // A press is not something somebody typed, and must not read like it.
      assert.equal(button.text, '');
      assert.equal(button.command, null);
    });

    it('is not drawn as a line in the conversation', async () => {
      // The person did not write "ok"; the bot answers, and that is what shows.
      const conversation = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(person),
      });
      const texts = (conversation.json().messages as Array<{ text: string }>).map((m) => m.text);
      assert.equal(texts.includes('ok'), false, texts.join(' | '));
    });

    it('presses once, however many times it is tapped', async () => {
      const messageId = await sendWithButtons([{ id: 'book', label: 'Book' }]);
      const first = await press(messageId, 'book');
      const second = await press(messageId, 'book');
      const third = await press(messageId, 'book');

      assert.deepEqual(first.json(), { pressed: true, already: false });
      assert.deepEqual(second.json(), { pressed: true, already: true });
      assert.deepEqual(third.json(), { pressed: true, already: true });

      const updates = await take();
      assert.equal(
        updates.filter((u) => u.button?.id === 'book').length,
        1,
        'a second tap became a second action',
      );
    });

    it('cannot be invented: only a button the message carries', async () => {
      const messageId = await sendWithButtons([{ id: 'yes', label: 'Yes' }]);
      const made_up = await press(messageId, 'admin');
      assert.equal(made_up.statusCode, 400);
      assert.equal(made_up.json().error, 'no_such_button');
    });

    it('cannot be pressed by somebody else in a direct chat', async () => {
      const messageId = await sendWithButtons([{ id: 'yes', label: 'Yes' }]);
      const stranger = await press(messageId, 'yes', other);
      assert.equal(stranger.statusCode, 403);
      assert.equal(stranger.json().error, 'not_yours');
    });

    it('cannot be pressed on another bot s message', async () => {
      const second = await h.app.inject({
        method: 'POST',
        url: '/v1/bots',
        headers: bearer(owner),
        payload: { name: 'Second', username: 'secondbot' },
      });
      const secondId = second.json().id as string;
      const messageId = await sendWithButtons([{ id: 'yes', label: 'Yes' }]);

      const crossed = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${secondId}/messages/${messageId}/press`,
        headers: bearer(person),
        payload: { buttonId: 'yes' },
      });
      assert.equal(crossed.statusCode, 404);
    });

    it('cannot be pressed after stopping the bot', async () => {
      const messageId = await sendWithButtons([{ id: 'yes', label: 'Yes' }]);
      await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/stop`,
        headers: bearer(person),
      });
      const refused = await press(messageId, 'yes');
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'not_contacted');

      // Put it back for anything after this.
      await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/start`,
        headers: bearer(person),
      });
    });

    it('and two buttons with the same id are refused when sent', async () => {
      const sent = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: {
          to: person.accountId,
          text: 'Which?',
          buttons: [
            { id: 'same', label: 'One' },
            { id: 'same', label: 'Two' },
          ],
        },
      });
      assert.equal(sent.statusCode, 400);
    });

    it('nine buttons are refused', async () => {
      const sent = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: {
          to: person.accountId,
          text: 'Too many',
          buttons: Array.from({ length: 9 }, (_, i) => ({ id: `b${i}`, label: `B${i}` })),
        },
      });
      assert.equal(sent.statusCode, 400);
    });
  });
});
