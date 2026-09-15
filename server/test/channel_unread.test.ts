import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { ChannelNotifier } from '../src/services/channel_notifications.js';
import {
  bearer,
  closePool,
  createHarness,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * Unread markers, and channel posts finally waking anybody.
 *
 * Until this existed a published post raised no push at all — which is also why
 * muting a channel suppressed nothing: there was nothing to suppress. These
 * tests are as much about who is *skipped* as about who is told.
 */
describe('unread channels and their notifications', () => {
  let h: TestHarness;
  let owner: TestUser;
  let reader: TestUser;
  let other: TestUser;
  let channelId: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'unreadowner');
    reader = await registerUser(h.app, 'unreadreader');
    other = await registerUser(h.app, 'unreadother');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  /** A push token, or a device is invisible to the notifier. */
  const withPush = (user: TestUser) =>
    h.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(user),
      payload: { provider: 'apns', token: `token-${user.deviceId}` },
    });

  const post = (user: TestUser, text: string, publishAt?: string) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/posts`,
      headers: bearer(user),
      payload: {
        content: Buffer.from(text).toString('base64'),
        ...(publishAt ? { publishAt } : {}),
      },
    });

  const listing = async (user: TestUser) => {
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/channels',
      headers: bearer(user),
    });
    return response.json().channels.find((c: { id: string }) => c.id === channelId);
  };

  beforeEach(async () => {
    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(owner),
      payload: {
        visibility: 'public',
        handle: `unread${Date.now()}${Math.floor(Math.random() * 1000)}`,
        title: 'Unread',
      },
    });
    channelId = created.json().id;
    for (const user of [reader, other]) {
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/join`,
        headers: bearer(user),
        payload: {},
      });
    }
    await withPush(reader);
    await withPush(other);
    h.push.sent.length = 0;
  });

  describe('the unread count', () => {
    it('counts what arrived after the last read, and nothing else', async () => {
      assert.equal((await listing(reader)).unreadCount, 0, 'a fresh channel is not unread');

      await post(owner, 'eins');
      await post(owner, 'zwei');
      assert.equal((await listing(reader)).unreadCount, 2);

      const second = (await post(owner, 'drei')).json();
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/read`,
        headers: bearer(reader),
        payload: { postId: second.id },
      });
      assert.equal((await listing(reader)).unreadCount, 0);

      await post(owner, 'vier');
      assert.equal((await listing(reader)).unreadCount, 1);
    });

    it('does not count your own posts as unread to you', async () => {
      await post(owner, 'von mir');
      assert.equal((await listing(owner)).unreadCount, 0);
      assert.equal((await listing(reader)).unreadCount, 1, 'but it is unread to everybody else');
    });

    it('does not count a post that is not visible yet', async () => {
      const later = new Date(Date.now() + 3_600_000).toISOString();
      await post(owner, 'spaeter', later);
      assert.equal(
        (await listing(reader)).unreadCount,
        0,
        'a scheduled post is not unread before it exists to the reader',
      );
    });

    it('is one number per account, shared by their devices', async () => {
      await post(owner, 'eins');
      const marked = (await post(owner, 'zwei')).json();
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/read`,
        headers: bearer(reader),
        payload: { postId: marked.id },
      });

      // Somebody else in the same channel is unaffected — it is per account,
      // not per channel.
      assert.equal((await listing(reader)).unreadCount, 0);
      assert.equal((await listing(other)).unreadCount, 2);
    });

    it('never moves backwards, however stale the device is', async () => {
      const first = (await post(owner, 'eins')).json();
      const second = (await post(owner, 'zwei')).json();

      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/read`,
        headers: bearer(reader),
        payload: { postId: second.id },
      });
      // A device that was offline still thinks the reader got as far as the
      // first post. Honouring that would mark something read as unread again.
      const stale = await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/read`,
        headers: bearer(reader),
        payload: { postId: first.id },
      });
      assert.equal(stale.json().lastReadPostId, Number(second.id));
      assert.equal((await listing(reader)).unreadCount, 0);
    });

    it('is refused to somebody outside the channel', async () => {
      const stranger = await registerUser(h.app, `unreadstranger${Date.now()}`);
      const refused = await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/read`,
        headers: bearer(stranger),
        payload: { postId: 1 },
      });
      assert.equal(refused.statusCode, 403);
    });
  });

  describe('the notification', () => {
    it('wakes every member except the author', async () => {
      await post(owner, 'hallo');
      // The publish detaches the wake-up so a bad endpoint cannot fail a
      // publish; give it the tick it needs.
      await new Promise((resolve) => setTimeout(resolve, 50));

      const woken = h.push.sent.map((t) => t.deviceId).sort();
      assert.deepEqual(woken, [reader.deviceId, other.deviceId].sort());
      assert.ok(!woken.includes(owner.deviceId), 'publishing is not news to you');
    });

    it('says nothing about the post, because the server cannot', async () => {
      await post(owner, 'geheim');
      await new Promise((resolve) => setTimeout(resolve, 50));

      assert.ok(h.push.sent.length > 0);
      // The same allowlist the 1:1 path is held to: anything new on a push
      // target has to be argued for before it reaches a vendor.
      assert.deepEqual(
        Object.keys(h.push.sent[0]!).sort(),
        ['deviceId', 'provider', 'token', 'urgency'].sort(),
      );
      assert.ok(!JSON.stringify(h.push.sent).includes('geheim'));
    });

    it('skips somebody who muted the channel', async () => {
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/mute`,
        headers: bearer(reader),
        payload: {},
      });
      h.push.sent.length = 0;

      await post(owner, 'still');
      await new Promise((resolve) => setTimeout(resolve, 50));

      const woken = h.push.sent.map((t) => t.deviceId);
      assert.deepEqual(woken, [other.deviceId], 'this is what the mute finally does');
    });

    it('does not skip somebody whose mute has run out', async () => {
      await pool.query(
        `INSERT INTO channel_mutes (account_id, channel_id, until)
         VALUES ($1, $2, now() - interval '1 minute')
         ON CONFLICT (account_id, channel_id) DO UPDATE SET until = EXCLUDED.until`,
        [reader.accountId, channelId],
      );
      h.push.sent.length = 0;

      await post(owner, 'wieder da');
      await new Promise((resolve) => setTimeout(resolve, 50));

      assert.ok(h.push.sent.some((t) => t.deviceId === reader.deviceId));
    });

    it('skips somebody the channel has silenced', async () => {
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/bans/${reader.accountId}`,
        headers: bearer(owner),
      });
      h.push.sent.length = 0;

      await post(owner, 'ohne dich');
      await new Promise((resolve) => setTimeout(resolve, 50));

      assert.ok(
        !h.push.sent.some((t) => t.deviceId === reader.deviceId),
        'a channel that stopped them speaking does not also buzz their phone',
      );
      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/bans/${reader.accountId}`,
        headers: bearer(owner),
      });
    });

    it('never sends twice for the same post', async () => {
      const published = (await post(owner, 'einmal')).json();
      await new Promise((resolve) => setTimeout(resolve, 50));
      const first = h.push.sent.length;
      assert.ok(first > 0);

      // A retry, a restart, or the sweeper passing over the same row.
      const notifier = new ChannelNotifier(h.push);
      assert.equal(await notifier.notifyPost(Number(published.id)), 0);
      assert.equal(h.push.sent.length, first);
    });

    it('does not send for a post nobody can see yet', async () => {
      const later = new Date(Date.now() + 3_600_000).toISOString();
      await post(owner, 'spaeter', later);
      await new Promise((resolve) => setTimeout(resolve, 50));

      assert.equal(h.push.sent.length, 0, 'a notification is for a moment, and this is not it');
    });

    it('sends for a scheduled post once its time has come', async () => {
      // Scheduled for later, so the publish route deliberately leaves it alone
      // — a notification is for a moment and that was not it. Then time passes,
      // which here is a clock the test controls rather than a minute it waits.
      const later = new Date(Date.now() + 3_600_000).toISOString();
      const scheduled = (await post(owner, 'jetzt faellig', later)).json();
      await new Promise((resolve) => setTimeout(resolve, 50));
      assert.equal(h.push.sent.length, 0, 'nothing yet, by design');

      await pool.query(
        "UPDATE channel_posts SET publish_at = now() - interval '1 second' WHERE id = $1",
        [scheduled.id],
      );
      h.push.sent.length = 0;

      const notifier = new ChannelNotifier(h.push);
      const woken = await notifier.sweep();

      assert.ok(woken > 0, 'the sweeper is what makes a scheduled post notify at all');
      assert.ok(h.push.sent.some((t) => t.deviceId === reader.deviceId));

      // And not again on the next pass.
      h.push.sent.length = 0;
      await notifier.sweep();
      assert.equal(h.push.sent.length, 0);
    });

    it('does not fail a publish when a wake-up does', async () => {
      // The property that matters: the post is already stored, and a vendor
      // refusing a stale token must not turn a successful publish into an
      // error the author sees and retries.
      await pool.query('UPDATE devices SET push_token = $1 WHERE id = $2', [
        'nonsense',
        reader.deviceId,
      ]);
      const published = await post(owner, 'trotzdem');
      assert.equal(published.statusCode, 201);
    });
  });
});
