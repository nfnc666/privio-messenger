import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import {
  bearer,
  closePool,
  createHarness,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * What the channel profile screen asks the server for.
 *
 * The four templates it was built from show a profile, an edit screen, an admin
 * list and a subscriber list — and every one of them is a permission question
 * before it is a layout question. These are those questions.
 */
describe('a channel profile', () => {
  let h: TestHarness;
  let owner: TestUser;
  let admin: TestUser;
  let subscriber: TestUser;
  let outsider: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'profowner');
    admin = await registerUser(h.app, 'profadmin');
    subscriber = await registerUser(h.app, 'profsub');
    outsider = await registerUser(h.app, 'profout');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const make = async (handle: string, visibility = 'public') => {
    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(owner),
      // A private channel has no handle — it is not searchable by name, which is
      // what a handle is for. Sending one is refused, and a failed create here
      // would show up much later as an unrelated 400 on some other route.
      payload:
        visibility === 'public'
          ? { visibility, handle, title: handle }
          // A private channel has no plaintext title either: its name is sealed
          // with the channel key, and the server is handed the ciphertext.
          : {
              visibility,
              encryptedMetadata: Buffer.from(`sealed:${handle}`).toString('base64'),
            },
    });
    assert.equal(created.statusCode, 201, created.body);
    const channel = created.json();
    for (const user of [admin, subscriber]) {
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(user),
        payload: visibility === 'public' ? {} : { inviteCode: channel.inviteCode },
      });
    }
    await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/members/${admin.accountId}/role`,
      headers: bearer(owner),
      payload: {
        role: 'admin',
        permissions: { canPost: true, canEditChannel: true, canManageMembers: true },
      },
    });
    return channel;
  };

  describe('the subscriber list', () => {
    it('is withheld from a subscriber and shown to an admin who may manage members', async () => {
      const channel = await make('sichtbarkeit');

      const asSubscriber = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(subscriber),
      });
      assert.equal(asSubscriber.statusCode, 200);
      assert.equal(asSubscriber.json().complete, false, 'the screen must say so, not imply a full list');
      const shown = asSubscriber.json().members.map((m: { username: string }) => m.username);
      assert.ok(!shown.includes('profsub') || shown.length <= 3, 'admins and themselves only');
      assert.ok(!shown.some((u: string) => u === 'profout'));

      const asAdmin = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(admin),
      });
      assert.equal(asAdmin.json().complete, true);
      assert.ok(asAdmin.json().members.length >= 3);
    });

    it('is not readable at all by somebody outside the channel', async () => {
      const channel = await make('draussen');
      const refused = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(outsider),
      });
      assert.equal(refused.statusCode, 403);
    });

    it('pages rather than truncating, and the cursor carries both sort keys', async () => {
      const channel = await make('seiten');
      const first = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members?limit=1`,
        headers: bearer(owner),
      });
      assert.equal(first.json().members.length, 1);
      assert.equal(first.json().more, true);
      const cursor = first.json().nextCursor as string;
      assert.ok(cursor.includes('|'), 'timestamp and id, or a tie drops somebody');

      const second = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members?limit=5&cursor=${encodeURIComponent(cursor)}`,
        headers: bearer(owner),
      });
      const ids = second.json().members.map((m: { id: string }) => m.id);
      assert.ok(!ids.includes(first.json().members[0].id), 'the page after is after');
    });

    it('searches server-side, so a large channel is not downloaded to be filtered', async () => {
      const channel = await make('suche');
      const found = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members?q=profsub`,
        headers: bearer(owner),
      });
      assert.deepEqual(
        found.json().members.map((m: { username: string }) => m.username),
        ['profsub'],
      );
    });

    it('shows who is an admin to every member, because that is not a secret from them', async () => {
      const channel = await make('werleitet');
      const asSubscriber = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members?role=admins`,
        headers: bearer(subscriber),
      });
      const roles = asSubscriber.json().members.map((m: { role: string }) => m.role);
      assert.ok(roles.includes('owner') && roles.includes('admin'));
      assert.ok(!roles.includes('subscriber'), 'only the people running it');
    });

    it("obeys the member's own last-seen setting, not the admin's rank", async () => {
      const channel = await make('gesehen');
      await h.app.inject({
        method: 'PATCH',
        url: '/v1/accounts/me',
        headers: bearer(subscriber),
        payload: { privacy: { lastSeen: 'nobody' } },
      });

      const asOwner = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members?q=profsub`,
        headers: bearer(owner),
      });
      assert.equal(
        asOwner.json().members[0].lastSeenAt,
        null,
        'running a channel is not a reason to see more',
      );
    });
  });

  describe('adding subscribers directly', () => {
    it('adds only people whose own setting allows it, and names the rest for an invite', async () => {
      const channel = await make('hinzufuegen');
      const open = await registerUser(h.app, 'profopen');
      const closed = await registerUser(h.app, 'profclosed');
      await h.app.inject({
        method: 'PATCH',
        url: '/v1/accounts/me',
        headers: bearer(open),
        payload: { privacy: { whoCanAddMeToGroups: 'everyone' } },
      });
      await h.app.inject({
        method: 'PATCH',
        url: '/v1/accounts/me',
        headers: bearer(closed),
        payload: { privacy: { whoCanAddMeToGroups: 'contacts' } },
      });

      const result = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(owner),
        payload: { accountIds: [open.accountId, closed.accountId] },
      });
      assert.equal(result.statusCode, 200);
      assert.deepEqual(result.json().added, [open.accountId]);
      assert.deepEqual(result.json().invite, [closed.accountId], 'send them a link instead');
    });

    it('never adds somebody who blocked the person adding them', async () => {
      const channel = await make('geblockt');
      const hostile = await registerUser(h.app, 'profhostile');
      await h.app.inject({
        method: 'PATCH',
        url: '/v1/accounts/me',
        headers: bearer(hostile),
        payload: { privacy: { whoCanAddMeToGroups: 'everyone' } },
      });
      await h.app.inject({
        method: 'POST',
        url: '/v1/blocks',
        headers: bearer(hostile),
        payload: { accountId: owner.accountId },
      });

      const result = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(owner),
        payload: { accountIds: [hostile.accountId] },
      });
      assert.deepEqual(result.json().added, [], 'a block outranks an open setting');
    });

    it('is refused to somebody who cannot manage members', async () => {
      const channel = await make('unbefugt');
      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(subscriber),
        payload: { accountIds: [outsider.accountId] },
      });
      assert.equal(refused.statusCode, 403);
    });
  });

  describe('muting', () => {
    it('is per account, survives, and is reported back on the channel', async () => {
      const channel = await make('stumm');
      const muted = await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/mute`,
        headers: bearer(subscriber),
        payload: {},
      });
      assert.equal(muted.statusCode, 200);
      assert.equal(muted.json().until, null, 'no end means no end');

      const listed = await h.app.inject({
        method: 'GET',
        url: '/v1/channels',
        headers: bearer(subscriber),
      });
      const mine = listed.json().channels.find((c: { id: string }) => c.id === channel.id);
      assert.equal(mine.muted, true);

      // And it is this account's alone.
      const others = await h.app.inject({ method: 'GET', url: '/v1/channels', headers: bearer(owner) });
      assert.equal(others.json().channels.find((c: { id: string }) => c.id === channel.id).muted, false);

      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/mute`,
        headers: bearer(subscriber),
      });
      const after = await h.app.inject({ method: 'GET', url: '/v1/channels', headers: bearer(subscriber) });
      assert.equal(after.json().channels.find((c: { id: string }) => c.id === channel.id).muted, false);
    });

    it('stops counting once the time is up, without a read having to write', async () => {
      const channel = await make('stummbis');
      await pool.query(
        `INSERT INTO channel_mutes (account_id, channel_id, until)
         VALUES ($1, $2, now() - interval '1 minute')`,
        [subscriber.accountId, channel.id],
      );
      const listed = await h.app.inject({ method: 'GET', url: '/v1/channels', headers: bearer(subscriber) });
      const mine = listed.json().channels.find((c: { id: string }) => c.id === channel.id);
      assert.equal(mine.muted, false, 'an expired mute is not a mute');
    });

    it('is refused to somebody who is not in the channel', async () => {
      const channel = await make('stummfremd');
      const refused = await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/mute`,
        headers: bearer(outsider),
        payload: {},
      });
      assert.equal(refused.statusCode, 403, 'muting is not a way to probe what exists');
    });
  });

  describe('livestreams', () => {
    it('report themselves unavailable rather than handing out a room nobody can join', async () => {
      // No SFU is configured in the test environment, which is also the default
      // for a fresh deployment — so this is the path most people meet.
      const channel = await make('livestatus');
      const status = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/live`,
        headers: bearer(subscriber),
      });
      assert.equal(status.statusCode, 200);
      assert.equal(status.json().available, false);
      assert.equal(status.json().live, null);
      assert.equal(status.json().access, null);
    });

    it('refuse to start with a reason, instead of failing silently', async () => {
      const channel = await make('livestart');
      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/live`,
        headers: bearer(owner),
      });
      assert.equal(refused.statusCode, 503);
      assert.equal(refused.json().error, 'livestream_unconfigured');
    });

    it('are not startable by somebody without the permission', async () => {
      const channel = await make('liverechte');
      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/live`,
        headers: bearer(subscriber),
      });
      assert.equal(refused.statusCode, 403, 'checked before the configuration is');
    });
  });

  describe("the channel's inbox", () => {
    it('is closed until an admin opens it', async () => {
      const channel = await make('posteingang');
      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/inbox`,
        headers: bearer(subscriber),
        payload: { content: Buffer.from('hallo').toString('base64') },
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'inbox_closed');
    });

    it('takes sealed bytes and shows them only to an admin', async () => {
      const channel = await make('posteingangoffen');
      await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { directMessagesEnabled: true },
      });

      const sent = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/inbox`,
        headers: bearer(subscriber),
        payload: { content: Buffer.from('sealed-bytes').toString('base64') },
      });
      assert.equal(sent.statusCode, 201);

      const asSubscriber = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/inbox`,
        headers: bearer(subscriber),
      });
      assert.equal(asSubscriber.statusCode, 403, 'writing to it is not reading it');

      const asAdmin = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/inbox`,
        headers: bearer(admin),
      });
      assert.equal(asAdmin.statusCode, 200);
      assert.equal(asAdmin.json().messages.length, 1);
      assert.equal(asAdmin.json().messages[0].senderUsername, 'profsub');
    });

    it('is closed to somebody silenced in the channel', async () => {
      const channel = await make('posteingangstumm');
      await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { directMessagesEnabled: true },
      });
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/bans/${subscriber.accountId}`,
        headers: bearer(owner),
      });

      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/inbox`,
        headers: bearer(subscriber),
        payload: { content: Buffer.from('trotzdem').toString('base64') },
      });
      assert.equal(refused.statusCode, 403, 'or the inbox is the way around being silenced');
      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/bans/${subscriber.accountId}`,
        headers: bearer(owner),
      });
    });
  });

  describe('the settings behind the edit screen', () => {
    it('stores the ones that are the channel own, and reports them back', async () => {
      const channel = await make('einstellungen');
      const saved = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: {
          showSenderName: true,
          welcomeEnabled: true,
          welcomeMessage: 'Willkommen',
          accent: 'green',
          background: 'midnight',
          directMessagesEnabled: true,
        },
      });
      assert.equal(saved.statusCode, 200);
      const view = saved.json();
      assert.equal(view.showSenderName, true);
      assert.equal(view.welcome.enabled, true);
      assert.equal(view.welcome.message, 'Willkommen');
      assert.deepEqual(view.appearance, { accent: 'green', background: 'midnight' });
      assert.equal(view.directMessagesEnabled, true);
    });

    it('clears a colour when it is sent as null, rather than keeping the old one', async () => {
      const channel = await make('farbeweg');
      await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { accent: 'teal' },
      });
      const cleared = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { accent: null },
      });
      assert.equal(cleared.json().appearance.accent, null, 'null is a value here, not "unchanged"');
    });

    it("refuses to store a private channel's welcome text in the clear", async () => {
      const channel = await make('privatwillkommen', 'private');
      const refused = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { welcomeMessage: 'Geheim' },
      });
      assert.equal(refused.statusCode, 400);
      assert.equal(refused.json().error, 'welcome_must_be_sealed');
    });

    it('only links a discussion group the caller actually administers', async () => {
      const channel = await make('diskussion');
      const someoneElses = (
        await h.app.inject({
          method: 'POST',
          url: '/v1/groups',
          headers: bearer(subscriber),
          payload: {},
        })
      ).json();

      const refused = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { discussionGroupId: someoneElses.groupId ?? someoneElses.id },
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'not_a_group_admin');
    });

    it('is refused to somebody who cannot edit the channel', async () => {
      const channel = await make('nichtbearbeiten');
      const refused = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(subscriber),
        payload: { showSenderName: true },
      });
      assert.equal(refused.statusCode, 403);
    });
  });

  describe('moderating a discussion', () => {
    it('is its own permission, not a side effect of deleting posts', async () => {
      const channel = await make('moderieren');
      await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { commentsEnabled: true },
      });
      const published = (
        await h.app.inject({
          method: 'POST',
          url: `/v1/channels/${channel.id}/posts`,
          headers: bearer(owner),
          payload: { content: Buffer.from('beitrag').toString('base64') },
        })
      ).json();
      const comment = (
        await h.app.inject({
          method: 'POST',
          url: `/v1/channels/${channel.id}/posts/${published.id}/comments`,
          headers: bearer(subscriber),
          payload: { content: Buffer.from('kommentar').toString('base64') },
        })
      ).json();

      // An admin who may delete posts but was not given the discussion.
      const moderator = await registerUser(h.app, 'profmod');
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(moderator),
        payload: {},
      });
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/members/${moderator.accountId}/role`,
        headers: bearer(owner),
        payload: { role: 'admin', permissions: { canPost: true, canDeletePosts: true } },
      });

      const refused = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/posts/${published.id}/comments/${comment.id}`,
        headers: bearer(moderator),
      });
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'insufficient_permission');

      // The owner holds everything, and can.
      const removed = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/posts/${published.id}/comments/${comment.id}`,
        headers: bearer(owner),
      });
      assert.equal(removed.statusCode, 200);
    });
  });
});
