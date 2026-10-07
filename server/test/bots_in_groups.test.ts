import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * A bot in a group.
 *
 * The rights are the feature, so most of this is about them being separate:
 * adding a bot grants nothing, each right is its own decision, and every one
 * is checked on the call that uses it rather than remembered from when it was
 * granted.
 *
 * The test that matters most is the last one. A group's messages are Signal
 * ciphertext addressed to member devices; adding a bot must not change that,
 * and nothing here may put a group message where this server can read it.
 */
describe('a bot in a group', () => {
  let h: TestHarness;
  let admin: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let groupId: string;
  let botId: string;
  let botToken: string;

  before(async () => {
    h = await createHarness();
    admin = await registerUser(h.app, 'bgadmin');
    member = await registerUser(h.app, 'bgmember');
    outsider = await registerUser(h.app, 'bgoutsider');

    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(admin),
      payload: {
        memberIds: [member.accountId],
        encryptedMetadata: Buffer.from('sealed').toString('base64'),
      },
    });
    groupId = created.json().id as string;

    const bot = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(admin),
      payload: { name: 'Helper', username: 'bghelper' },
    });
    assert.equal(bot.statusCode, 201, bot.body);
    botId = bot.json().id as string;

    const token = await h.app.inject({
      method: 'POST',
      url: `/v1/bots/${botId}/token`,
      headers: bearer(admin),
    });
    botToken = token.json().token as string;
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = () => ({ authorization: `Bearer ${botToken}` });

  const rightsNow = async () => {
    const listed = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(member),
    });
    assert.equal(listed.statusCode, 200, listed.body);
    const bots = listed.json().bots as Array<Record<string, unknown>>;
    assert.ok(bots[0], 'the group should have a bot in it by now');
    return bots[0];
  };

  it('an admin adds it, and it arrives with no rights at all', async () => {
    const added = await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(admin),
      payload: { botId },
    });
    assert.equal(added.statusCode, 201, added.body);

    const bot = await rightsNow();
    assert.equal(bot.maySend, false);
    assert.equal(bot.mayModerate, false);
    assert.equal(bot.mayRestrictMembers, false);
    assert.equal(bot.mayManageInvites, false);
    assert.equal(
      bot.readsAllMessages,
      false,
      'a bot that could read everything on being added would make the disclosure a formality',
    );
  });

  it('a member may not add one', async () => {
    const added = await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(member),
      payload: { botId },
    });
    assert.equal(added.statusCode, 403);
  });

  it('and somebody outside the group may not even look', async () => {
    const listed = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(outsider),
    });
    assert.equal(listed.statusCode, 403);
  });

  it('rights are granted one at a time, and the others stay off', async () => {
    const granted = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: bearer(admin),
      payload: { maySend: true },
    });
    assert.equal(granted.statusCode, 200, granted.body);

    const bot = await rightsNow();
    assert.equal(bot.maySend, true);
    assert.equal(bot.mayModerate, false, 'one right must not imply another');
    assert.equal(bot.mayRestrictMembers, false);
    assert.equal(bot.mayManageInvites, false);
  });

  it('a member may not change them', async () => {
    const granted = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: bearer(member),
      payload: { mayModerate: true },
    });
    assert.equal(granted.statusCode, 403);
    assert.equal((await rightsNow()).mayModerate, false);
  });

  it('the bot itself may not grant its own', async () => {
    // Its token authenticates the bot, not its owner — even though the owner
    // is an admin of this group.
    const granted = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: asBot(),
      payload: { mayModerate: true },
    });
    assert.ok(granted.statusCode === 401 || granted.statusCode === 403, granted.body);
    assert.equal((await rightsNow()).mayModerate, false);
  });

  it('with the right, and after being written to, it can answer in the group',
    async () => {
      // Being in a group with a bot is not the same as having opened a
      // conversation with it, so the member writes first.
      const wrote = await h.app.inject({
        method: 'POST',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(member),
        payload: { text: '/help', groupId },
      });
      assert.equal(wrote.statusCode, 201, wrote.body);

      const sent = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: member.accountId, text: 'Here is the help.', groupId },
      });
      assert.equal(sent.statusCode, 200, sent.body);
    });

  it('and without it, the same call is refused', async () => {
    await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: bearer(admin),
      payload: { maySend: false },
    });

    const sent = await h.app.inject({
      method: 'POST',
      url: '/v1/bot/send',
      headers: asBot(),
      payload: { to: member.accountId, text: 'still here', groupId },
    });
    assert.equal(sent.statusCode, 403);
    assert.equal(sent.json().error, 'missing_right');
  });

  it('a bot in no group at all cannot send to one', async () => {
    const other = await h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(admin),
      payload: { memberIds: [], encryptedMetadata: Buffer.from('x').toString('base64') },
    });
    const otherId = other.json().id as string;

    const sent = await h.app.inject({
      method: 'POST',
      url: '/v1/bot/send',
      headers: asBot(),
      payload: { to: member.accountId, text: 'hello', groupId: otherId },
    });
    assert.equal(sent.statusCode, 403);
    assert.equal(sent.json().error, 'not_in_group');
  });

  it('removing it stops the next call, without touching what it already had',
    async () => {
      await h.app.inject({
        method: 'PATCH',
        url: `/v1/groups/${groupId}/bots/${botId}`,
        headers: bearer(admin),
        payload: { maySend: true },
      });

      const removed = await h.app.inject({
        method: 'DELETE',
        url: `/v1/groups/${groupId}/bots/${botId}`,
        headers: bearer(admin),
      });
      assert.equal(removed.statusCode, 200);
      assert.deepEqual(removed.json().bots, []);

      const sent = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: member.accountId, text: 'back again', groupId },
      });
      assert.equal(sent.statusCode, 403);
      assert.equal(sent.json().error, 'not_in_group');

      // What it received while it was in the group is still in its history.
      // Removing a bot is not a way to delete what somebody already sent it,
      // and pretending otherwise would be the lie this project keeps refusing.
      const { rows } = await pool.query<{ n: string }>(
        `SELECT count(*) AS n FROM bot_messages
          WHERE bot_id = $1 AND scope = 'group' AND scope_id = $2`,
        [botId, groupId],
      );
      assert.ok(Number(rows[0]!.n) > 0);
    });

  it('a member may not remove one either', async () => {
    await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(admin),
      payload: { botId },
    });
    const removed = await h.app.inject({
      method: 'DELETE',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: bearer(member),
    });
    assert.equal(removed.statusCode, 403);
  });

  it('none of this puts a group message where the server can read it', async () => {
    // The guarantee the whole design rests on. A bot in a group must not turn
    // `envelopes` into something openable, and the only rows this feature
    // writes are ones a member's device handed over deliberately.
    const { rows } = await pool.query<{ n: string }>(
      `SELECT count(*) AS n FROM bot_messages
        WHERE scope = 'group' AND scope_id = $1 AND author = 'user'`,
      [groupId],
    );
    assert.ok(Number(rows[0]!.n) > 0, 'the member did write to the bot');

    // And every one of them was written through the user-facing route, which
    // requires a session. There is no path from an envelope to this table.
    const { rows: envelopes } = await pool.query<{ n: string }>(
      'SELECT count(*) AS n FROM envelopes WHERE group_id = $1',
      [groupId],
    );
    assert.equal(
      Number(envelopes[0]!.n),
      0,
      'this test sent no group messages, so any envelope here came from the bot path',
    );
  });
});
