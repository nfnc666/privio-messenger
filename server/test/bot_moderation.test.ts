import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * What a bot may do in a group once an admin has granted it.
 *
 * The rights were stored and enforced before this; what was missing was any
 * route that used them, so a granted right did nothing. These tests are about
 * the two that are now wired — and about the one that is refused outright,
 * because a permission an admin agreed to that quietly does nothing is worse
 * than no permission.
 */
describe('a bot moderating a group', () => {
  let h: TestHarness;
  let admin: TestUser;
  let member: TestUser;
  let second: TestUser;
  let botId: string;
  let botToken: string;
  let groupId: string;

  before(async () => {
    h = await createHarness();
    admin = await registerUser(h.app, 'modadmin');
    member = await registerUser(h.app, 'modmember');
    second = await registerUser(h.app, 'modsecond');

    const bot = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(admin),
      payload: { name: 'Warden', username: 'wardenbot' },
    });
    botId = bot.json().id as string;
    botToken = (
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/token`, headers: bearer(admin) })
    ).json().token as string;

    const group = await h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(admin),
      payload: {
        encryptedMetadata: Buffer.from('sealed name').toString('base64'),
        memberIds: [member.accountId, second.accountId],
      },
    });
    assert.equal(group.statusCode, 201, group.body);
    groupId = group.json().id as string;

    const added = await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${groupId}/bots`,
      headers: bearer(admin),
      payload: { botId },
    });
    assert.equal(added.statusCode, 201, added.body);
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = () => ({ authorization: `Bearer ${botToken}` });

  const grant = (right: string, value = true) =>
    h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}/bots/${botId}`,
      headers: bearer(admin),
      payload: { [right]: value },
    });

  const remove = (accountId: string) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/bot/group/members/remove',
      headers: asBot(),
      payload: { groupId, accountId },
    });

  const isMember = async (accountId: string) => {
    const { rowCount } = await pool.query(
      'SELECT 1 FROM group_members WHERE group_id = $1 AND account_id = $2',
      [groupId, accountId],
    );
    return rowCount === 1;
  };

  describe('without the right', () => {
    it('it cannot remove anybody, and cannot read the member list', async () => {
      const refused = await remove(member.accountId);
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'missing_right');
      assert.equal(await isMember(member.accountId), true);

      const list = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/group/members?groupId=${groupId}`,
        headers: asBot(),
      });
      assert.equal(list.statusCode, 403);
      assert.equal(
        list.json().error,
        'missing_right',
        'a bot could read who is in a group just for being in it',
      );
    });

    it('and cannot renew the invite link', async () => {
      const refused = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/group/invite/rotate',
        headers: asBot(),
        payload: { groupId },
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'missing_right');
    });
  });

  describe('with may_restrict_members', () => {
    before(async () => {
      assert.equal((await grant('mayRestrictMembers')).statusCode, 200);
    });

    it('it reads the members, and is told which it may remove', async () => {
      const list = await h.app.inject({
        method: 'GET',
        url: `/v1/bot/group/members?groupId=${groupId}`,
        headers: asBot(),
      });
      assert.equal(list.statusCode, 200, list.body);
      const members = list.json().members as Array<Record<string, unknown>>;
      const byName = Object.fromEntries(members.map((m) => [m.username, m]));
      assert.equal(byName.modadmin!.removable, false, 'an admin is not removable');
      assert.equal(byName.modmember!.removable, true);
      assert.equal(byName.wardenbot, undefined, 'a bot is not a group member row');
    });

    it('it removes an ordinary member', async () => {
      const removed = await remove(member.accountId);
      assert.equal(removed.statusCode, 200, removed.body);
      assert.deepEqual(removed.json(), { removed: true });
      assert.equal(await isMember(member.accountId), false);
    });

    it('and the removal clears their pending key request', async () => {
      // A request left behind is a request nobody should answer.
      const { rowCount } = await pool.query(
        `SELECT 1 FROM key_requests
          WHERE scope = 'group' AND scope_id = $1 AND account_id = $2`,
        [groupId, member.accountId],
      );
      assert.equal(rowCount, 0);
    });

    it('it cannot remove an admin', async () => {
      const refused = await remove(admin.accountId);
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'cannot_remove_admin');
      assert.equal(await isMember(admin.accountId), true);
    });

    it('it cannot remove itself', async () => {
      const refused = await remove(botId);
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'not_itself');
    });

    it('somebody who is not a member is a 404, not a silent success', async () => {
      const stranger = await registerUser(h.app, 'modstranger');
      const refused = await remove(stranger.accountId);
      assert.equal(refused.statusCode, 404);
      assert.equal(refused.json().error, 'member_not_found');
    });

    it('a bot in another group cannot reach into this one', async () => {
      const other = await h.app.inject({
        method: 'POST',
        url: '/v1/groups',
        headers: bearer(second),
        payload: { encryptedMetadata: Buffer.from('other').toString('base64'), memberIds: [] },
      });
      const otherGroup = other.json().id as string;

      const refused = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/group/members/remove',
        headers: asBot(),
        payload: { groupId: otherGroup, accountId: second.accountId },
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'not_in_group');
      assert.equal(
        (await pool.query('SELECT 1 FROM group_members WHERE group_id = $1', [otherGroup]))
          .rowCount,
        1,
        'the other group lost a member',
      );
    });

    it('withdrawing the right breaks the next call, not the one after', async () => {
      assert.equal((await grant('mayRestrictMembers', false)).statusCode, 200);
      const refused = await remove(second.accountId);
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'missing_right');
      assert.equal(await isMember(second.accountId), true);
    });
  });

  describe('with may_manage_invites', () => {
    it('it renews the link, and the old code stops working', async () => {
      const before = await h.app.inject({
        method: 'GET',
        url: `/v1/groups/${groupId}`,
        headers: bearer(admin),
      });
      const oldCode = before.json().inviteCode as string;
      assert.ok(oldCode);

      assert.equal((await grant('mayManageInvites')).statusCode, 200);
      const rotated = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/group/invite/rotate',
        headers: asBot(),
        payload: { groupId },
      });
      assert.equal(rotated.statusCode, 200, rotated.body);
      const newCode = rotated.json().inviteCode as string;
      assert.notEqual(newCode, oldCode);

      const stale = await h.app.inject({
        method: 'GET',
        url: `/v1/groups/invite/${oldCode}`,
        headers: bearer(second),
      });
      assert.equal(stale.statusCode, 404, 'the old link still opens the group');
    });

    it('and nobody already in the group is affected', async () => {
      assert.equal(await isMember(admin.accountId), true);
      assert.equal(await isMember(second.accountId), true);
    });

    it('an admin can renew it too, and a member cannot', async () => {
      // The human route this right mirrors. A group's code was permanent until
      // now, which made a link posted once a way in forever.
      const byAdmin = await h.app.inject({
        method: 'POST',
        url: `/v1/groups/${groupId}/invite/rotate`,
        headers: bearer(admin),
      });
      assert.equal(byAdmin.statusCode, 200, byAdmin.body);

      const byMember = await h.app.inject({
        method: 'POST',
        url: `/v1/groups/${groupId}/invite/rotate`,
        headers: bearer(second),
      });
      assert.equal(byMember.statusCode, 403);
    });
  });

  describe('deleting other people s messages', () => {
    it('is refused as a right, not stored and left inert', async () => {
      const refused = await grant('mayModerate');
      assert.equal(refused.statusCode, 400, refused.body);
      assert.equal(refused.json().error, 'right_not_available');

      const { rows } = await pool.query<{ may_moderate: boolean }>(
        'SELECT may_moderate FROM bot_group_members WHERE bot_id = $1 AND group_id = $2',
        [botId, groupId],
      );
      assert.equal(rows[0]!.may_moderate, false);
    });

    it('but withdrawing it stays allowed', async () => {
      // A group granted it before this check existed has to be able to tidy up.
      await pool.query(
        'UPDATE bot_group_members SET may_moderate = true WHERE bot_id = $1 AND group_id = $2',
        [botId, groupId],
      );
      const withdrawn = await grant('mayModerate', false);
      assert.equal(withdrawn.statusCode, 200, withdrawn.body);
      const { rows } = await pool.query<{ may_moderate: boolean }>(
        'SELECT may_moderate FROM bot_group_members WHERE bot_id = $1 AND group_id = $2',
        [botId, groupId],
      );
      assert.equal(rows[0]!.may_moderate, false);
    });
  });
});
