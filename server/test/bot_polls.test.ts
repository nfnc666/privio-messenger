import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { takeUpdates } from '../src/services/bots.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Polls a bot sends.
 *
 * What these tests hold the feature to: an answer is one the poll offers, from
 * the one person the message was addressed to, reaches the bot once per change
 * and in order, and the tally is shown to the people answering only when the
 * bot asked for that. The other half is honesty — a poll is plaintext like the
 * rest of the bot path and the bot is told who answered what — which the schema
 * test and the docs carry.
 */
describe('polls from a bot', () => {
  let h: TestHarness;
  let owner: TestUser;
  let alice: TestUser;
  let bruno: TestUser;
  let stranger: TestUser;
  let botId: string;
  let botToken: string;
  let otherBotToken: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'pollowner');
    alice = await registerUser(h.app, 'pollalice');
    bruno = await registerUser(h.app, 'pollbruno');
    stranger = await registerUser(h.app, 'pollstranger');

    const makeBot = async (username: string) => {
      const created = await h.app.inject({
        method: 'POST',
        url: '/v1/bots',
        headers: bearer(owner),
        payload: { name: username, username },
      });
      const id = created.json().id as string;
      const token = (
        await h.app.inject({ method: 'POST', url: `/v1/bots/${id}/token`, headers: bearer(owner) })
      ).json().token as string;
      return { id, token };
    };
    const asker = await makeBot('askerbot');
    botId = asker.id;
    botToken = asker.token;
    const other = await makeBot('otheraskerbot');
    otherBotToken = other.token;
    // Alice has started the other bot too, so a refusal of its send below is
    // about the poll and not about never having been written to.
    await h.app.inject({ method: 'POST', url: `/v1/bots/${other.id}/start`, headers: bearer(alice) });

    for (const person of [alice, bruno]) {
      const started = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/start`,
        headers: bearer(person),
      });
      assert.equal(started.statusCode, 200, started.body);
    }
    // Drain the two /start updates so every test below sees only its own.
    await take();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = (token = botToken) => ({ authorization: `Bearer ${token}` });

  /** What is waiting for the bot, after the per-bot poll gate. */
  async function take() {
    await new Promise((resolve) => setTimeout(resolve, 950));
    return takeUpdates(botId, 20);
  }

  const send = (payload: Record<string, unknown>, token = botToken) =>
    h.app.inject({ method: 'POST', url: '/v1/bot/send', headers: asBot(token), payload });

  const sendPoll = async (
    to: TestUser,
    poll: Record<string, unknown> = { question: 'Which day?', options: ['Mon', 'Tue', 'Wed'] },
  ) => {
    const sent = await send({ to: to.accountId, poll });
    assert.equal(sent.statusCode, 200, sent.body);
    return sent.json() as { messageId: number; pollId: number };
  };

  const vote = (messageId: number, options: number[], as: TestUser) =>
    h.app.inject({
      method: 'PUT',
      url: `/v1/bots/${botId}/messages/${messageId}/vote`,
      headers: bearer(as),
      payload: { options },
    });

  const conversation = async (as: TestUser) => {
    const out = await h.app.inject({
      method: 'GET',
      url: `/v1/bots/${botId}/messages`,
      headers: bearer(as),
    });
    assert.equal(out.statusCode, 200, out.body);
    return out.json().messages as Array<{
      id: number;
      text: string;
      poll: null | {
        id: number;
        question: string;
        options: string[];
        maxChoices: number;
        showResults: boolean;
        closed: boolean;
        myVotes: number[];
        counts: number[] | null;
        voters: number | null;
      };
    }>;
  };

  describe('sending one', () => {
    it('is a message that carries a poll, with no copy of the question in its text', async () => {
      const { messageId, pollId } = await sendPoll(alice);
      assert.ok(pollId > 0);

      const line = (await conversation(alice)).find((m) => m.id === messageId)!;
      assert.equal(line.text, '');
      assert.equal(line.poll?.question, 'Which day?');
      assert.deepEqual(line.poll?.options, ['Mon', 'Tue', 'Wed']);
      assert.equal(line.poll?.maxChoices, 1);
      assert.equal(line.poll?.showResults, false);
      assert.deepEqual(line.poll?.myVotes, []);
    });

    it('refuses a poll the person could not answer sensibly', async () => {
      const cases: Array<[Record<string, unknown>, number]> = [
        [{ question: 'One?', options: ['only'] }, 400],
        [{ question: 'Same?', options: ['a', 'a'] }, 400],
        [{ question: 'Many?', options: ['a', 'b'], maxChoices: 3 }, 400],
        [{ question: 'Eleven?', options: Array.from({ length: 11 }, (_, i) => `o${i}`) }, 400],
        [{ question: 'Late?', options: ['a', 'b'], closesAt: new Date(Date.now() - 1000).toISOString() }, 400],
      ];
      for (const [poll, status] of cases) {
        const out = await send({ to: alice.accountId, poll });
        assert.equal(out.statusCode, status, `${JSON.stringify(poll)}: ${out.body}`);
      }
    });

    it('carries nothing else to answer: no buttons beside it', async () => {
      const out = await send({
        to: alice.accountId,
        poll: { question: 'Yes?', options: ['y', 'n'] },
        buttons: [{ id: 'x', label: 'Also this' }],
      });
      assert.equal(out.statusCode, 400);
      assert.equal(out.json().error, 'poll_alone');
    });

    it('a message without text and without a poll is still refused', async () => {
      const out = await send({ to: alice.accountId });
      assert.equal(out.statusCode, 400);
      assert.equal(out.json().error, 'text_required');
    });

    it('is still only a reply: a bot cannot open a conversation with a poll', async () => {
      const out = await send({
        to: stranger.accountId,
        poll: { question: 'Hi?', options: ['a', 'b'] },
      });
      assert.equal(out.statusCode, 403);
      assert.equal(out.json().error, 'not_contacted');
    });

    it('another bot cannot reuse this bot s poll, and cannot tell it exists', async () => {
      const { pollId } = await sendPoll(alice);
      const borrowed = await send({ to: alice.accountId, pollId }, otherBotToken);
      assert.equal(borrowed.statusCode, 404, borrowed.body);
      assert.equal(borrowed.json().error, 'poll_not_found');
      const peek = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/polls/${pollId}`,
        headers: asBot(otherBotToken),
      });
      assert.equal(peek.statusCode, 404);
      assert.equal(peek.json().error, 'poll_not_found');
    });
  });

  describe('answering', () => {
    it('reaches the bot once, in order, with the whole answer', async () => {
      await take();
      const { messageId, pollId } = await sendPoll(alice);

      const first = await vote(messageId, [1], alice);
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.json().changed, true);
      assert.deepEqual(first.json().myVotes, [1]);

      // The same answer again: a double tap is not a second vote.
      const again = await vote(messageId, [1], alice);
      assert.equal(again.statusCode, 200);
      assert.equal(again.json().changed, false);

      // Changing it is a new answer, and the bot is told the whole of it.
      const changed = await vote(messageId, [2], alice);
      assert.equal(changed.json().changed, true);

      const updates = await take();
      const votes = updates.filter((u) => u.vote !== null);
      assert.equal(votes.length, 2, JSON.stringify(updates));
      assert.deepEqual(votes[0]!.vote, { pollId, options: [1] });
      assert.deepEqual(votes[1]!.vote, { pollId, options: [2] });
      assert.equal(votes[0]!.chat.accountId, alice.accountId);
      // A vote is not something anybody typed.
      assert.equal(votes[0]!.text, '');
      assert.equal(votes[0]!.command, null);
      assert.equal(votes[0]!.button, null);
    });

    it('an empty answer takes the vote back, and the bot hears that too', async () => {
      await take();
      const { messageId, pollId } = await sendPoll(alice);
      await vote(messageId, [0], alice);
      const back = await vote(messageId, [], alice);
      assert.equal(back.json().changed, true);
      assert.deepEqual(back.json().myVotes, []);

      const votes = (await take()).filter((u) => u.vote !== null);
      assert.deepEqual(votes.at(-1)!.vote, { pollId, options: [] });
    });

    it('refuses an answer the poll does not offer', async () => {
      const { messageId } = await sendPoll(alice);
      const outOfRange = await vote(messageId, [3], alice);
      assert.equal(outOfRange.statusCode, 400);
      assert.equal(outOfRange.json().error, 'no_such_option');

      const twoOnSingle = await vote(messageId, [0, 1], alice);
      assert.equal(twoOnSingle.statusCode, 400);
      assert.equal(twoOnSingle.json().error, 'too_many_options');

      const twice = await vote(messageId, [0, 0], alice);
      assert.equal(twice.statusCode, 400);
      assert.equal(twice.json().error, 'duplicate_option');
    });

    it('takes several answers when the poll allows several', async () => {
      const { messageId } = await sendPoll(alice, {
        question: 'Which ones?',
        options: ['a', 'b', 'c'],
        maxChoices: 2,
      });
      const two = await vote(messageId, [2, 0], alice);
      assert.equal(two.statusCode, 200, two.body);
      // Stored and answered in order, whichever order they were sent in.
      assert.deepEqual(two.json().myVotes, [0, 2]);
      const three = await vote(messageId, [0, 1, 2], alice);
      assert.equal(three.json().error, 'too_many_options');
    });

    it('only the person it was addressed to may answer', async () => {
      const { messageId } = await sendPoll(alice);
      // Bruno has started the bot too, so this is not the not-started refusal.
      const notHis = await vote(messageId, [0], bruno);
      assert.equal(notHis.statusCode, 403);
      assert.equal(notHis.json().error, 'not_yours');

      const nobody = await vote(messageId, [0], stranger);
      assert.equal(nobody.statusCode, 403);
    });

    it('a message without a poll cannot be voted on', async () => {
      const plain = await send({ to: alice.accountId, text: 'just words' });
      const out = await vote(plain.json().messageId as number, [0], alice);
      assert.equal(out.statusCode, 400);
      assert.equal(out.json().error, 'no_poll');
    });

    it('a person s own line cannot be voted on, and another bot s id is a 404', async () => {
      const mine = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(alice),
        payload: { text: 'hello' },
      });
      assert.equal(mine.statusCode, 201, mine.body);
      const out = await vote(mine.json().messageId as number, [0], alice);
      assert.equal(out.statusCode, 404);
      assert.equal(out.json().error, 'message_not_found');
    });

    it('stopping the bot stops the answers too', async () => {
      const { messageId } = await sendPoll(bruno);
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/stop`, headers: bearer(bruno) });
      const out = await vote(messageId, [0], bruno);
      assert.equal(out.statusCode, 403);
      assert.equal(out.json().error, 'not_contacted');
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/start`, headers: bearer(bruno) });
    });
  });

  describe('one poll, several people', () => {
    it('the bot reads one tally across everybody it was sent to', async () => {
      const toAlice = await sendPoll(alice, { question: 'Lunch?', options: ['pizza', 'soup'] });
      const toBruno = await send({ to: bruno.accountId, pollId: toAlice.pollId });
      assert.equal(toBruno.statusCode, 200, toBruno.body);
      assert.equal(toBruno.json().pollId, toAlice.pollId);

      await vote(toAlice.messageId, [0], alice);
      await vote(toBruno.json().messageId as number, [0], bruno);

      const tally = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/polls/${toAlice.pollId}`,
        headers: asBot(),
      });
      assert.equal(tally.statusCode, 200, tally.body);
      assert.deepEqual(tally.json().counts, [2, 0]);
      assert.equal(tally.json().voters, 2);
      assert.equal(tally.json().closed, false);
    });

    it('somebody sent the same poll twice has one answer, shown under both', async () => {
      const first = await sendPoll(alice, { question: 'Again?', options: ['y', 'n'] });
      const second = await send({ to: alice.accountId, pollId: first.pollId });
      await vote(second.json().messageId as number, [1], alice);

      const lines = await conversation(alice);
      const both = lines.filter((m) => m.poll?.id === first.pollId);
      assert.equal(both.length, 2);
      for (const line of both) assert.deepEqual(line.poll?.myVotes, [1]);

      const tally = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/polls/${first.pollId}`,
        headers: asBot(),
      });
      assert.equal(tally.json().voters, 1);
    });
  });

  describe('what the people answering see', () => {
    it('no tally unless the bot asked for one', async () => {
      const { messageId } = await sendPoll(alice);
      const answered = await vote(messageId, [0], alice);
      assert.equal(answered.json().counts, null);
      const line = (await conversation(alice)).find((m) => m.id === messageId)!;
      assert.equal(line.poll?.counts, null);
      assert.equal(line.poll?.voters, null);
    });

    it('with showResults, the tally after answering and not before', async () => {
      const made = await sendPoll(alice, {
        question: 'Open?',
        options: ['yes', 'no'],
        showResults: true,
      });
      const toBruno = await send({ to: bruno.accountId, pollId: made.pollId });
      await vote(toBruno.json().messageId as number, [1], bruno);

      // Alice has not answered: Bruno's choice is not hers to see yet.
      const before = (await conversation(alice)).find((m) => m.id === made.messageId)!;
      assert.equal(before.poll?.counts, null);

      const answered = await vote(made.messageId, [0], alice);
      assert.deepEqual(answered.json().counts, [1, 1]);
      assert.equal(answered.json().voters, 2);
      const after = (await conversation(alice)).find((m) => m.id === made.messageId)!;
      assert.deepEqual(after.poll?.counts, [1, 1]);
    });
  });

  describe('closing', () => {
    it('the bot closes it; answers stop; closing again is harmless', async () => {
      const { messageId, pollId } = await sendPoll(alice);
      await vote(messageId, [0], alice);

      const closed = await h.app.inject({
        method: 'POST',
        url: `/v1/bot/polls/${pollId}/close`,
        headers: asBot(),
      });
      assert.equal(closed.statusCode, 200, closed.body);
      assert.equal(closed.json().closed, true);
      assert.equal(closed.json().alreadyClosed, false);
      assert.deepEqual(closed.json().counts, [1, 0, 0]);

      const late = await vote(messageId, [1], alice);
      assert.equal(late.statusCode, 409);
      assert.equal(late.json().error, 'poll_closed');

      const again = await h.app.inject({
        method: 'POST',
        url: `/v1/bot/polls/${pollId}/close`,
        headers: asBot(),
      });
      assert.equal(again.json().alreadyClosed, true);

      // And a closed poll is not sent to anybody else.
      const resend = await send({ to: bruno.accountId, pollId });
      assert.equal(resend.statusCode, 409);
      assert.equal(resend.json().error, 'poll_closed');
    });

    it('closes on its own at closesAt, without being stamped as closed by the bot', async () => {
      const { messageId, pollId } = await sendPoll(alice, {
        question: 'Quick?',
        options: ['a', 'b'],
        closesAt: new Date(Date.now() + 60_000).toISOString(),
      });
      await pool.query(
        "UPDATE bot_polls SET closes_at = now() - interval '1 second' WHERE id = $1",
        [pollId],
      );
      const late = await vote(messageId, [0], alice);
      assert.equal(late.json().error, 'poll_closed');

      const closed = await h.app.inject({
        method: 'POST',
        url: `/v1/bot/polls/${pollId}/close`,
        headers: asBot(),
      });
      assert.equal(closed.json().closed, true);
      const { rows } = await pool.query<{ closed_at: Date | null }>(
        'SELECT closed_at FROM bot_polls WHERE id = $1',
        [pollId],
      );
      assert.equal(rows[0]!.closed_at, null);
    });
  });

  describe('when an account goes', () => {
    it('its answers and its bot conversation go with it', async () => {
      const leaver = await registerUser(h.app, 'pollleaver');
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/start`, headers: bearer(leaver) });
      const { messageId, pollId } = await sendPoll(leaver);
      await vote(messageId, [0], leaver);

      const gone = await h.app.inject({
        method: 'DELETE',
        url: '/v1/accounts/me',
        headers: bearer(leaver),
        payload: { currentPassword: 'correct-horse-battery' },
      });
      assert.ok(gone.statusCode < 300, gone.body);

      for (const [table, sql] of [
        ['bot_poll_votes', 'SELECT count(*)::int AS n FROM bot_poll_votes WHERE account_id = $1'],
        ['bot_messages', 'SELECT count(*)::int AS n FROM bot_messages WHERE account_id = $1'],
        ['bot_contacts', 'SELECT count(*)::int AS n FROM bot_contacts WHERE account_id = $1'],
      ] as const) {
        const { rows } = await pool.query<{ n: number }>(sql, [leaver.accountId]);
        assert.equal(rows[0]!.n, 0, `${table} outlived the account`);
      }
      // The poll itself is the bot's and stays, without the leaver's vote.
      const tally = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/polls/${pollId}`,
        headers: asBot(),
      });
      assert.equal(tally.json().voters, 0);
    });

    it('a deleted bot takes its polls and every answer to them along', async () => {
      const { messageId, pollId } = await sendPoll(alice);
      await vote(messageId, [0], alice);
      const deleted = await h.app.inject({
        method: 'DELETE',
        url: `/v1/bots/${botId}`,
        headers: bearer(owner),
      });
      assert.equal(deleted.statusCode, 200, deleted.body);
      const { rows } = await pool.query<{ polls: number; votes: number }>(
        `SELECT (SELECT count(*)::int FROM bot_polls WHERE bot_id = $1) AS polls,
                (SELECT count(*)::int FROM bot_poll_votes WHERE poll_id = $2) AS votes`,
        [botId, pollId],
      );
      assert.deepEqual(rows[0], { polls: 0, votes: 0 });
    });
  });
});
