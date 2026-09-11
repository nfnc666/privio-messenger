import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('channels', () => {
  let h: TestHarness;
  let owner: TestUser;
  let reader: TestUser;
  let stranger: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'owner');
    reader = await registerUser(h.app, 'reader');
    stranger = await registerUser(h.app, 'stranger');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const createChannel = (user: TestUser, payload: Record<string, unknown>) =>
    h.app.inject({ method: 'POST', url: '/v1/channels', headers: bearer(user), payload });

  const post = (user: TestUser, channelId: string, text: string) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/posts`,
      headers: bearer(user),
      // Sealed with the channel key before it ever gets here.
      payload: { content: Buffer.from(text).toString('base64') },
    });

  it('creates a public channel that is discoverable by name', async () => {
    const created = await createChannel(owner, {
      visibility: 'public',
      handle: 'wanderungen',
      title: 'Wanderungen im Harz',
      description: 'Touren jedes Wochenende',
      category: 'outdoors',
    });
    assert.equal(created.statusCode, 201);
    assert.equal(created.json().memberCount, 1);
    assert.ok(created.json().inviteCode, 'the creator gets a code to share');

    const found = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/discover?q=harz',
      headers: bearer(stranger),
    });
    assert.equal(found.json().channels.length, 1);
    assert.equal(found.json().channels[0].handle, 'wanderungen');
  });

  it('a public channel’s posts are ciphertext to the server', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'kochen',
      title: 'Kochen',
    })).json();

    const published = await post(owner, channel.id, 'sealed-with-the-channel-key');
    assert.equal(published.statusCode, 201);

    const { rows } = await pool.query('SELECT content FROM channel_posts WHERE id = $1', [
      published.json().id,
    ]);
    assert.equal(
      rows[0].content.toString(),
      'sealed-with-the-channel-key',
      'the server stores exactly the bytes it was given and holds no key for them',
    );
  });

  it('a private channel is not discoverable, and does not admit it exists', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'private',
      encryptedMetadata: Buffer.from('sealed-title').toString('base64'),
    })).json();

    const search = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/discover',
      headers: bearer(stranger),
    });
    assert.ok(
      !search.json().channels.some((c: { id: string }) => c.id === channel.id),
      'private channels are never listed',
    );

    const direct = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(stranger),
    });
    assert.equal(direct.statusCode, 404, 'and a stranger gets the same answer as for nothing');
  });

  it('a private channel is reachable with its invite code', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'private',
      encryptedMetadata: Buffer.from('sealed-title').toString('base64'),
    })).json();

    const byCode = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/invite/${channel.inviteCode}`,
      headers: bearer(reader),
    });
    assert.equal(byCode.statusCode, 200);
    assert.equal(byCode.json().visibility, 'private');
    assert.equal(
      byCode.json().title,
      null,
      'even with the code, the server cannot say what it is called',
    );

    const joined = await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(reader),
      payload: { inviteCode: channel.inviteCode },
    });
    assert.equal(joined.statusCode, 200);
    assert.equal(joined.json().role, 'subscriber');
  });

  it('joining a private channel without the code fails like a wrong address', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'private',
      encryptedMetadata: Buffer.from('sealed').toString('base64'),
    })).json();

    const attempt = await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(stranger),
      payload: {},
    });
    assert.equal(attempt.statusCode, 404);
  });

  it('anyone may join a public channel, and then read the feed', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'nachrichten',
      title: 'Nachrichten',
    })).json();
    await post(owner, channel.id, 'erster-beitrag');

    const before = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(reader),
    });
    assert.equal(before.statusCode, 403, 'a public channel is still members-only to read');

    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(reader),
      payload: {},
    });
    const feed = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(reader),
    });
    assert.equal(feed.statusCode, 200);
    assert.equal(
      Buffer.from(feed.json().posts[0].content, 'base64').toString(),
      'erster-beitrag',
    );
  });

  const join = (user: TestUser, channelId: string, inviteCode?: string) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/join`,
      headers: bearer(user),
      payload: inviteCode ? { inviteCode } : {},
    });

  const setRole = (
    actor: TestUser,
    channelId: string,
    target: TestUser,
    payload: Record<string, unknown>,
  ) =>
    h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channelId}/members/${target.accountId}/role`,
      headers: bearer(actor),
      payload,
    });

  it('a subscriber cannot publish until they are given the permission', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'lesen',
      title: 'Lesen',
    })).json();
    await join(reader, channel.id);

    assert.equal((await post(reader, channel.id, 'darf-ich-nicht')).statusCode, 403);

    const promoted = await setRole(owner, channel.id, reader, { role: 'admin' });
    assert.equal(promoted.statusCode, 200);
    assert.equal(promoted.json().permissions.canPost, true);
    assert.equal(
      promoted.json().permissions.canManageMembers,
      false,
      'a new admin does not get to hand out permissions by default',
    );
    assert.equal((await post(reader, channel.id, 'jetzt-schon')).statusCode, 201);
  });

  it('an admin who may manage members can appoint another admin', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'ernennen',
      title: 'Ernennen',
    })).json();
    await join(reader, channel.id);
    await join(stranger, channel.id);

    await setRole(owner, channel.id, reader, {
      role: 'admin',
      permissions: { canPost: true, canManageMembers: true },
    });

    const appointed = await setRole(reader, channel.id, stranger, {
      role: 'admin',
      permissions: { canPost: true },
    });
    assert.equal(appointed.statusCode, 200, 'this is what the owner delegated');
    assert.equal((await post(stranger, channel.id, 'ich-auch')).statusCode, 201);
  });

  it('an admin cannot grant a permission they do not hold themselves', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'grenzen',
      title: 'Grenzen',
    })).json();
    await join(reader, channel.id);
    await join(stranger, channel.id);

    // Can appoint admins, but cannot delete the channel.
    await setRole(owner, channel.id, reader, {
      role: 'admin',
      permissions: { canPost: true, canManageMembers: true },
    });

    const overreach = await setRole(reader, channel.id, stranger, {
      role: 'admin',
      permissions: { canDeleteChannel: true },
    });
    assert.equal(overreach.statusCode, 403);
    assert.equal(overreach.json().error, 'cannot_grant_what_you_lack');
  });

  it('an admin cannot demote someone who outranks them', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'rangordnung',
      title: 'Rangordnung',
    })).json();
    await join(reader, channel.id);
    await join(stranger, channel.id);

    await setRole(owner, channel.id, reader, {
      role: 'admin',
      permissions: { canManageMembers: true },
    });
    await setRole(owner, channel.id, stranger, {
      role: 'admin',
      permissions: { canManageMembers: true, canDeleteChannel: true },
    });

    const attempt = await setRole(reader, channel.id, stranger, { role: 'subscriber' });
    assert.equal(attempt.statusCode, 403);
    assert.equal(attempt.json().error, 'target_outranks_you');
  });

  it('nobody may change the owner, and nobody may change themselves', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'eigentuemer',
      title: 'Eigentuemer',
    })).json();
    await join(reader, channel.id);
    await setRole(owner, channel.id, reader, {
      role: 'admin',
      permissions: { canManageMembers: true },
    });

    const againstOwner = await setRole(reader, channel.id, owner, { role: 'subscriber' });
    assert.equal(againstOwner.statusCode, 403);

    const selfPromotion = await setRole(reader, channel.id, reader, {
      role: 'admin',
      permissions: { canDeleteChannel: true },
    });
    assert.equal(selfPromotion.statusCode, 400);
  });

  it('an admin with the permission can remove a member', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'entfernen',
      title: 'Entfernen',
    })).json();
    await join(reader, channel.id);
    await join(stranger, channel.id);
    await setRole(owner, channel.id, reader, {
      role: 'admin',
      permissions: { canManageMembers: true },
    });

    const removed = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/members/${stranger.accountId}`,
      headers: bearer(reader),
    });
    assert.equal(removed.statusCode, 200);

    const feed = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(stranger),
    });
    assert.equal(feed.statusCode, 403, 'and they can no longer read new posts');
  });

  it('the owner can delete the channel, and so can an admin who was trusted with it', async () => {
    const ownersChannel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'weg',
      title: 'Weg',
    })).json();

    const byOwner = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${ownersChannel.id}`,
      headers: bearer(owner),
    });
    assert.equal(byOwner.statusCode, 200);

    const gone = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${ownersChannel.id}`,
      headers: bearer(owner),
    });
    assert.equal(gone.statusCode, 404);

    const delegated = (await createChannel(owner, {
      visibility: 'public',
      handle: 'auchweg',
      title: 'Auch weg',
    })).json();
    await join(reader, delegated.id);
    await setRole(owner, delegated.id, reader, {
      role: 'admin',
      permissions: { canDeleteChannel: true },
    });

    const byAdmin = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${delegated.id}`,
      headers: bearer(reader),
    });
    assert.equal(byAdmin.statusCode, 200);
  });

  it('an admin without that permission cannot delete the channel', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'bleibt',
      title: 'Bleibt',
    })).json();
    await join(reader, channel.id);
    await setRole(owner, channel.id, reader, { role: 'admin' });

    const attempt = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(reader),
    });
    assert.equal(attempt.statusCode, 403);
    assert.equal(attempt.json().error, 'insufficient_permission');

    const still = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(owner),
    });
    assert.equal(still.statusCode, 200);
  });

  it('a deleted channel disappears from discovery', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'unsichtbar',
      title: 'Unsichtbar Kanal',
    })).json();
    await h.app.inject({ method: 'DELETE', url: `/v1/channels/${channel.id}`, headers: bearer(owner) });

    const search = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/discover?q=Unsichtbar',
      headers: bearer(stranger),
    });
    assert.equal(search.json().channels.length, 0);
  });

  it('pins and unpins a post', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'angeheftet',
      title: 'Angeheftet',
    })).json();
    const published = (await post(owner, channel.id, 'wichtig')).json();

    const pinned = await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/posts/${published.id}/pin`,
      headers: bearer(owner),
      payload: { pinned: true },
    });
    assert.equal(pinned.statusCode, 200);

    const feed = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(owner),
    });
    assert.equal(feed.json().posts[0].pinned, true);
  });

  it('deleting a post overwrites its ciphertext rather than tombstoning it', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'loeschen',
      title: 'Loeschen',
    })).json();
    const published = (await post(owner, channel.id, 'bitte-vergessen')).json();

    await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/posts/${published.id}`,
      headers: bearer(owner),
    });

    const { rows } = await pool.query('SELECT content FROM channel_posts WHERE id = $1', [
      published.id,
    ]);
    assert.equal(
      rows[0].content.length,
      0,
      'a deleted post should not sit on disk waiting for a key to turn up',
    );

    const feed = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(owner),
    });
    assert.equal(feed.json().posts.length, 0);
  });

  describe('comments and silencing', () => {
    const sealed = (text: string) => Buffer.from(text).toString('base64');

    const enableComments = (channelId: string, on = true) =>
      h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channelId}`,
        headers: bearer(owner),
        payload: { commentsEnabled: on },
      });

    const join = (user: TestUser, channelId: string) =>
      h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/join`,
        headers: bearer(user),
        payload: {},
      });

    const comment = (user: TestUser, channelId: string, postId: number, text: string) =>
      h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/posts/${postId}/comments`,
        headers: bearer(user),
        payload: { content: sealed(text) },
      });

    const thread = (user: TestUser, channelId: string, postId: number) =>
      h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts/${postId}/comments`,
        headers: bearer(user),
      });

    const silence = (user: TestUser, channelId: string, who: string) =>
      h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/bans/${who}`,
        headers: bearer(user),
      });

    /** A channel with comments on, a post in it, and [reader] subscribed. */
    async function threaded(handle: string) {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle,
        title: handle,
      })).json();
      await enableComments(channel.id);
      const published = (await post(owner, channel.id, 'worueber geredet wird')).json();
      await join(reader, channel.id);
      return { channel, published };
    }

    it('are off until the owner turns them on', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'stumm',
        title: 'Stumm',
      })).json();
      assert.equal(channel.commentsEnabled, false, 'a channel is a broadcast by default');
      const published = (await post(owner, channel.id, 'etwas')).json();
      await join(reader, channel.id);

      const refused = await comment(reader, channel.id, published.id, 'darf ich?');
      assert.equal(refused.statusCode, 409);
      assert.equal(refused.json().error, 'comments_disabled');

      assert.equal((await enableComments(channel.id)).json().commentsEnabled, true);
      assert.equal((await comment(reader, channel.id, published.id, 'jetzt')).statusCode, 201);
    });

    it('a subscriber who cannot publish can comment, and the thread reads forwards', async () => {
      const { channel, published } = await threaded('unterhaltung');

      await comment(reader, channel.id, published.id, 'erstens');
      await comment(owner, channel.id, published.id, 'zweitens');
      await comment(reader, channel.id, published.id, 'drittens');

      const shown = (await thread(reader, channel.id, published.id)).json().comments;
      assert.deepEqual(
        shown.map((c: { content: string }) => Buffer.from(c.content, 'base64').toString()),
        ['erstens', 'zweitens', 'drittens'],
        'a conversation reads forwards, unlike a feed',
      );
      assert.deepEqual(
        shown.map((c: { authorUsername: string }) => c.authorUsername),
        ['reader', 'owner', 'reader'],
      );
    });

    it('the feed says how many without fetching any of them', async () => {
      const { channel, published } = await threaded('wieviele');
      await comment(reader, channel.id, published.id, 'eins');
      await comment(reader, channel.id, published.id, 'zwei');

      const feed = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(reader),
      });
      assert.equal(feed.json().posts[0].commentCount, 2);
    });

    it('an author can remove their own, and an admin anyone’s', async () => {
      const { channel, published } = await threaded('kommentarentfernen');
      const mine = (await comment(reader, channel.id, published.id, 'meins')).json();
      const theirs = (await comment(owner, channel.id, published.id, 'ihrs')).json();

      const removeTheirs = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/posts/${published.id}/comments/${theirs.id}`,
        headers: bearer(reader),
      });
      assert.equal(removeTheirs.statusCode, 403, 'a subscriber does not moderate');

      assert.equal(
        (await h.app.inject({
          method: 'DELETE',
          url: `/v1/channels/${channel.id}/posts/${published.id}/comments/${mine.id}`,
          headers: bearer(reader),
        })).statusCode,
        200,
        'but they can take back their own',
      );
      assert.equal(
        (await h.app.inject({
          method: 'DELETE',
          url: `/v1/channels/${channel.id}/posts/${published.id}/comments/${theirs.id}`,
          headers: bearer(owner),
        })).statusCode,
        200,
      );

      assert.deepEqual((await thread(reader, channel.id, published.id)).json().comments, []);

      // Overwritten, not tombstoned: a removed comment must not sit on disk
      // waiting for a key to turn up.
      const { rows } = await pool.query(
        'SELECT content FROM channel_post_comments WHERE id = $1',
        [mine.id],
      );
      assert.equal(rows[0].content.length, 0);
    });

    it('silencing stops the comments and the reactions, and leaves the reading', async () => {
      const { channel, published } = await threaded('schweigen');
      await comment(reader, channel.id, published.id, 'noch erlaubt');

      const silenced = await silence(owner, channel.id, reader.accountId);
      assert.equal(silenced.statusCode, 200);

      const refused = await comment(reader, channel.id, published.id, 'nicht mehr');
      assert.equal(refused.statusCode, 403);
      assert.equal(refused.json().error, 'banned');

      // A reaction is a way of speaking too.
      const stamped = await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/posts/${published.id}/reactions`,
        headers: bearer(reader),
        payload: { emoji: '👍' },
      });
      assert.equal(stamped.statusCode, 403);

      // But they are still a member and can still read. Silencing is not
      // removal — removal rotates the key and cuts them off from everything.
      const feed = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(reader),
      });
      assert.equal(feed.statusCode, 200);
      assert.equal(feed.json().posts.length, 1);
      assert.equal((await thread(reader, channel.id, published.id)).statusCode, 200);
    });

    it('and can be undone', async () => {
      const { channel, published } = await threaded('wiederreden');
      await silence(owner, channel.id, reader.accountId);

      const lifted = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/bans/${reader.accountId}`,
        headers: bearer(owner),
      });
      assert.equal(lifted.statusCode, 200);
      assert.equal((await comment(reader, channel.id, published.id, 'wieder da')).statusCode, 201);
    });

    it('the owner cannot be silenced, and a subscriber cannot silence anybody', async () => {
      const { channel } = await threaded('nichtdenchef');

      assert.equal((await silence(reader, channel.id, owner.accountId)).statusCode, 403);

      // Even by themselves, through the right permission: there would be no
      // way back.
      const ownerBan = await silence(owner, channel.id, owner.accountId);
      assert.equal(ownerBan.statusCode, 403);
      assert.equal(ownerBan.json().error, 'cannot_ban_owner');
    });

    it('the ban list is a moderation record, not a roster', async () => {
      const { channel } = await threaded('sperrliste');
      await silence(owner, channel.id, reader.accountId);

      const asSubscriber = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/bans`,
        headers: bearer(reader),
      });
      assert.equal(asSubscriber.statusCode, 403, 'it would name who else reads the channel');

      const asOwner = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/bans`,
        headers: bearer(owner),
      });
      assert.equal(asOwner.json().banned.length, 1);
      assert.equal(asOwner.json().banned[0].username, 'reader');
    });

    it('a comment under a superseded key is refused, like a post is', async () => {
      const { channel, published } = await threaded('alterschluesselkommentar');
      await pool.query('UPDATE channels SET key_epoch = 2 WHERE id = $1', [channel.id]);

      const stale = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts/${published.id}/comments`,
        headers: bearer(reader),
        payload: { content: sealed('unter epoche eins'), keyEpoch: 1 },
      });
      assert.equal(stale.statusCode, 409);
      assert.equal(stale.json().error, 'stale_key_epoch');
    });

    it('a scheduled post has no thread to find', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'nochnichtda',
        title: 'Noch nicht da',
      })).json();
      await enableComments(channel.id);
      await join(reader, channel.id);
      const queued = (await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: {
          content: sealed('spaeter'),
          publishAt: new Date(Date.now() + 3_600_000).toISOString(),
        },
      })).json();

      // Commenting on it would be a way for a subscriber to learn it exists.
      const early = await comment(reader, channel.id, queued.id, 'ich sehe was');
      assert.equal(early.statusCode, 404);
    });

    it('deleting a post takes its thread with it', async () => {
      const { channel, published } = await threaded('mitsamtthread');
      await comment(reader, channel.id, published.id, 'etwas');

      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/posts/${published.id}`,
        headers: bearer(owner),
      });

      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM channel_post_comments WHERE post_id = $1',
        [published.id],
      );
      assert.equal(rows[0].n, 0, 'a thread must not outlive the post it hangs under');
    });
  });

  describe('editing and scheduling', () => {
    const feed = (user: TestUser, channelId: string, scheduled = false) =>
      h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts${scheduled ? '?scheduled=true' : ''}`,
        headers: bearer(user),
      });

    const edit = (
      user: TestUser,
      channelId: string,
      postId: number,
      payload: Record<string, unknown>,
    ) =>
      h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channelId}/posts/${postId}`,
        headers: bearer(user),
        payload,
      });

    const sealed = (text: string) => Buffer.from(text).toString('base64');

    it('an author can change their own post, and it says so', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'bearbeiten',
        title: 'Bearbeiten',
      })).json();
      const published = (await post(owner, channel.id, 'erste fassung')).json();

      const changed = await edit(owner, channel.id, published.id, {
        content: sealed('zweite fassung'),
      });
      assert.equal(changed.statusCode, 200);
      assert.ok(changed.json().editedAt, 'a post people have read carries the mark');

      const shown = (await feed(owner, channel.id)).json().posts[0];
      assert.equal(
        Buffer.from(shown.content, 'base64').toString(),
        'zweite fassung',
        'the ciphertext the server stores is the new one',
      );
      assert.ok(shown.editedAt);
    });

    it('an admin who can delete a post still cannot rewrite it', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'fremdeworte',
        title: 'Fremde Worte',
      })).json();
      const published = (await post(owner, channel.id, 'meine worte')).json();

      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(reader),
        payload: {},
      });
      // Everything an admin gets, including deleting other people's posts.
      await h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channel.id}/members/${reader.accountId}/role`,
        headers: bearer(owner),
        payload: {
          role: 'admin',
          permissions: { canPost: true, canDeletePosts: true, canEditChannel: true },
        },
      });

      const attempt = await edit(reader, channel.id, published.id, {
        content: sealed('worte die ich nie sagte'),
      });
      // Every post carries its author's name. Editing somebody else's is
      // putting words in their mouth under their own byline; deleting is the
      // moderation tool, and it is honest about what it is.
      assert.equal(attempt.statusCode, 403);
      assert.equal(attempt.json().error, 'not_the_author');
    });

    it('a scheduled post is invisible until it is due', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'spaeter',
        title: 'Spaeter',
      })).json();

      const later = new Date(Date.now() + 3_600_000).toISOString();
      const queued = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: { content: sealed('noch nicht'), publishAt: later },
      });
      assert.equal(queued.statusCode, 201);
      assert.ok(queued.json().publishAt);

      assert.deepEqual(
        (await feed(owner, channel.id)).json().posts,
        [],
        'not even to the author: the feed is what everybody sees',
      );

      const waiting = (await feed(owner, channel.id, true)).json().posts;
      assert.equal(waiting.length, 1);
      assert.equal(waiting[0].id, queued.json().id);
    });

    it('and appears once its time has passed, with no job having run', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'faellig',
        title: 'Faellig',
      })).json();
      const queued = (await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: { content: sealed('jetzt'), publishAt: new Date(Date.now() + 60_000).toISOString() },
      })).json();

      assert.equal((await feed(owner, channel.id)).json().posts.length, 0);

      // Move its time into the past, which is all that "becoming due" is here.
      // No sweeper, no queue, nothing to fall over at three in the morning.
      await pool.query('UPDATE channel_posts SET publish_at = now() - interval \'1 second\' WHERE id = $1', [
        queued.id,
      ]);

      const shown = (await feed(owner, channel.id)).json().posts;
      assert.equal(shown.length, 1);
      assert.equal(shown[0].id, queued.id);
      assert.equal(shown[0].editedAt, null, 'appearing on time is not an edit');
    });

    it('a subscriber cannot look into the waiting room', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'wartezimmer',
        title: 'Wartezimmer',
      })).json();
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(reader),
        payload: {},
      });
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: { content: sealed('geheim'), publishAt: new Date(Date.now() + 3_600_000).toISOString() },
      });

      const peeked = await feed(reader, channel.id, true);
      assert.equal(peeked.statusCode, 403);
    });

    it('editing something still scheduled leaves no mark', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'ohnemarke',
        title: 'Ohne Marke',
      })).json();
      const queued = (await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: { content: sealed('entwurf'), publishAt: new Date(Date.now() + 3_600_000).toISOString() },
      })).json();

      const changed = await edit(owner, channel.id, queued.id, { content: sealed('besserer entwurf') });
      assert.equal(changed.statusCode, 200);
      // Nobody read the earlier version, so there is nothing to disclose.
      assert.equal(changed.json().editedAt, null);

      // And publishing it now is a reschedule, not an edit.
      const published = await edit(owner, channel.id, queued.id, {
        content: sealed('besserer entwurf'),
        publishAt: null,
      });
      assert.equal(published.json().publishAt, null);
      assert.equal(published.json().editedAt, null);
      assert.equal((await feed(owner, channel.id)).json().posts.length, 1);
    });

    it('a time in the past is now, not a way to jump the queue', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'rueckdatiert',
        title: 'Rueckdatiert',
      })).json();

      const backdated = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/posts`,
        headers: bearer(owner),
        payload: {
          content: sealed('von gestern'),
          publishAt: new Date(Date.now() - 86_400_000).toISOString(),
        },
      });
      assert.equal(backdated.statusCode, 201);
      assert.equal(backdated.json().publishAt, null, 'published, not back-dated');
      assert.equal((await feed(owner, channel.id)).json().posts.length, 1);
    });

    it('an edit is refused under a superseded key, like a post is', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'altschluessel',
        title: 'Alter Schluessel',
      })).json();
      const published = (await post(owner, channel.id, 'unter epoche eins')).json();

      // The channel moves on without this author's edit knowing.
      await pool.query('UPDATE channels SET key_epoch = 2 WHERE id = $1', [channel.id]);

      const stale = await edit(owner, channel.id, published.id, {
        content: sealed('immer noch epoche eins'),
        keyEpoch: 1,
      });
      assert.equal(stale.statusCode, 409);
      assert.equal(stale.json().error, 'stale_key_epoch');
    });
  });

  describe('reactions', () => {
    const react = (user: TestUser, channelId: string, postId: number, emoji: string) =>
      h.app.inject({
        method: 'PUT',
        url: `/v1/channels/${channelId}/posts/${postId}/reactions`,
        headers: bearer(user),
        payload: { emoji },
      });

    const unreact = (user: TestUser, channelId: string, postId: number, emoji: string) =>
      h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/posts/${postId}/reactions?emoji=${encodeURIComponent(emoji)}`,
        headers: bearer(user),
      });

    const join = (user: TestUser, channelId: string) =>
      h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/join`,
        headers: bearer(user),
        payload: {},
      });

    const feed = (user: TestUser, channelId: string) =>
      h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts`,
        headers: bearer(user),
      });

    it('a subscriber who cannot publish can still react', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'reagieren',
        title: 'Reagieren',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();
      await join(reader, channel.id);

      // The point of an audience having a voice at all: posting is the
      // admins', reacting is everybody's.
      const cannotPost = await post(reader, channel.id, 'nicht erlaubt');
      assert.equal(cannotPost.statusCode, 403);

      const reacted = await react(reader, channel.id, published.id, '👍');
      assert.equal(reacted.statusCode, 200);
      assert.deepEqual(reacted.json().reactions, { '👍': 1 });
      assert.deepEqual(reacted.json().myReactions, ['👍']);
    });

    it('counts come with the feed, and say which are the reader’s own', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'zaehlenreaktionen',
        title: 'Zaehlen',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();
      await join(reader, channel.id);

      await react(owner, channel.id, published.id, '👍');
      await react(reader, channel.id, published.id, '👍');
      await react(reader, channel.id, published.id, '🔥');

      const mine = (await feed(reader, channel.id)).json().posts[0];
      assert.deepEqual(mine.reactions, { '👍': 2, '🔥': 1 });
      assert.deepEqual(mine.myReactions.sort(), ['🔥', '👍'].sort());

      const theirs = (await feed(owner, channel.id)).json().posts[0];
      assert.deepEqual(theirs.reactions, { '👍': 2, '🔥': 1 }, 'the totals are the same');
      assert.deepEqual(theirs.myReactions, ['👍'], 'but only their own are named');
    });

    it('the same reaction twice is still one', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'doppelt',
        title: 'Doppelt',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();

      await react(owner, channel.id, published.id, '👍');
      const again = await react(owner, channel.id, published.id, '👍');

      // A double tap on a slow connection is one reaction, not an error the
      // screen has to explain.
      assert.equal(again.statusCode, 200);
      assert.deepEqual(again.json().reactions, { '👍': 1 });
    });

    it('a reaction can be taken back, and only your own', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'zurueck',
        title: 'Zurueck',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();
      await join(reader, channel.id);
      await react(owner, channel.id, published.id, '👍');
      await react(reader, channel.id, published.id, '👍');

      const removed = await unreact(reader, channel.id, published.id, '👍');
      assert.equal(removed.statusCode, 200);
      assert.deepEqual(removed.json().reactions, { '👍': 1 }, 'the owner’s is untouched');
      assert.deepEqual(removed.json().myReactions, []);

      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM channel_post_reactions WHERE post_id = $1',
        [published.id],
      );
      assert.equal(rows[0].n, 1, 'there is no route that removes somebody else’s');
    });

    it('only the emojis the channel offers', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'auswahl',
        title: 'Auswahl',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();

      const notOffered = await react(owner, channel.id, published.id, '🦆');
      assert.equal(notOffered.statusCode, 400);
      assert.equal(notOffered.json().error, 'emoji_not_offered');

      // An admin changes the menu, and then it is allowed.
      const changed = await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { reactionEmojis: ['🦆', '👍'] },
      });
      assert.equal(changed.statusCode, 200);
      assert.deepEqual(changed.json().reactionEmojis, ['🦆', '👍']);
      assert.equal((await react(owner, channel.id, published.id, '🦆')).statusCode, 200);
    });

    it('the reaction bar cannot be turned into a row of captions', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'keintext',
        title: 'Kein Text',
      })).json();

      for (const attempt of ['SALE', 'call 0800', 'a', '  ']) {
        const refused = await h.app.inject({
          method: 'PATCH',
          url: `/v1/channels/${channel.id}`,
          headers: bearer(owner),
          payload: { reactionEmojis: [attempt] },
        });
        assert.equal(refused.statusCode, 400, `"${attempt}" is text, not a symbol`);
      }
    });

    it('a stranger cannot react, and neither can a member of another channel', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'fremde',
        title: 'Fremde',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();

      assert.equal((await react(stranger, channel.id, published.id, '👍')).statusCode, 403);

      // Post ids are a global sequence, so being in *a* channel must not be
      // enough to reach a post in another one by guessing a number.
      const elsewhere = (await createChannel(stranger, {
        visibility: 'public',
        handle: 'anderswo',
        title: 'Anderswo',
      })).json();
      const crossed = await react(stranger, elsewhere.id, published.id, '👍');
      assert.equal(crossed.statusCode, 404);
    });

    it('changing the menu does not discard what is already on a post', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'menue',
        title: 'Menue',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();
      await react(owner, channel.id, published.id, '👍');

      await h.app.inject({
        method: 'PATCH',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
        payload: { reactionEmojis: ['🔥'] },
      });

      const shown = (await feed(owner, channel.id)).json().posts[0];
      assert.deepEqual(
        shown.reactions,
        { '👍': 1 },
        'taking an emoji off the menu is not a reason to delete what people said with it',
      );
    });

    it('deleting a post takes its reactions with it', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'mitloeschen',
        title: 'Mitloeschen',
      })).json();
      const published = (await post(owner, channel.id, 'etwas')).json();
      await react(owner, channel.id, published.id, '👍');

      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/posts/${published.id}`,
        headers: bearer(owner),
      });

      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM channel_post_reactions WHERE post_id = $1',
        [published.id],
      );
      assert.equal(rows[0].n, 0);
    });
  });

  it('the owner cannot simply walk out of their own channel', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'verlassen',
      title: 'Verlassen',
    })).json();

    const left = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/members/me`,
      headers: bearer(owner),
    });
    assert.equal(left.statusCode, 409);
  });

  it('leaving decrements the count that discovery ranks by', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'zaehlen',
      title: 'Zaehlen',
    })).json();
    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(reader),
      payload: {},
    });

    const afterJoin = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(owner),
    });
    assert.equal(afterJoin.json().memberCount, 2);

    await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/members/me`,
      headers: bearer(reader),
    });
    const afterLeave = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(owner),
    });
    assert.equal(afterLeave.json().memberCount, 1);
  });

  it('refuses a public channel with no handle, and a private one with no sealed title', async () => {
    assert.equal((await createChannel(owner, { visibility: 'public', title: 'Ohne Handle' })).statusCode, 400);
    assert.equal((await createChannel(owner, { visibility: 'private' })).statusCode, 400);
  });

  it('refuses a handle that is already taken', async () => {
    await createChannel(owner, { visibility: 'public', handle: 'einmalig', title: 'Einmalig' });
    const again = await createChannel(reader, {
      visibility: 'public',
      handle: 'einmalig',
      title: 'Noch einmal',
    });
    assert.equal(again.statusCode, 409);
  });
  it('a joiner is queued for the key, and a member who holds it can see the request', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'schluessel',
      title: 'Schlüssel',
    })).json();

    await join(reader, channel.id);

    // The owner sees exactly one device waiting — the reader's.
    const pending = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/key-requests`,
      headers: bearer(owner),
    });
    assert.equal(pending.statusCode, 200);
    const requests = pending.json().requests;
    assert.equal(requests.length, 1);
    assert.equal(requests[0].accountId, reader.accountId);
    assert.equal(requests[0].deviceId, reader.deviceId);

    // Nothing in the request reveals a key: the server only routes the ask.
    assert.ok(!JSON.stringify(requests[0]).includes('key'));

    // Once the sealed key is on its way, the request is cleared.
    const cleared = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/key-requests/${reader.deviceId}`,
      headers: bearer(owner),
    });
    assert.equal(cleared.statusCode, 200);

    const after = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/key-requests`,
      headers: bearer(owner),
    });
    assert.equal(after.json().requests.length, 0);
  });

  it('does not offer its own device a key it is already waiting for', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'selbst',
      title: 'Selbst',
    })).json();
    await join(reader, channel.id);

    // The reader asking who is waiting must not be told about themselves.
    const pending = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/key-requests`,
      headers: bearer(reader),
    });
    assert.equal(pending.json().requests.length, 0);
  });

  it('drops a key request when the member leaves', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'weggegangen',
      title: 'Weggegangen',
    })).json();
    await join(reader, channel.id);
    await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/members/me`,
      headers: bearer(reader),
    });

    const pending = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/key-requests`,
      headers: bearer(owner),
    });
    assert.equal(pending.json().requests.length, 0);
  });

  it('refuses key requests from someone who is not a member', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'fremder',
      title: 'Fremder',
    })).json();
    const response = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/key-requests`,
      headers: bearer(reader),
    });
    assert.equal(response.statusCode, 403);
  });
  it('tells a member what they may do, not just what they are called', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'rechte',
      title: 'Rechte',
    })).json();
    await join(reader, channel.id);

    const mine = await h.app.inject({ method: 'GET', url: '/v1/channels', headers: bearer(owner) });
    const listed = mine.json().channels.find((c: { id: string }) => c.id === channel.id);
    // Without permissions on the listing a client cannot tell the owner of a
    // channel from someone who may only read it.
    assert.equal(listed.role, 'owner');
    assert.equal(listed.permissions.canPost, true);
    assert.equal(listed.permissions.canDeleteChannel, true);
    assert.ok(listed.inviteCode, 'the link is shareable by anyone in the channel');

    const theirs = await h.app.inject({ method: 'GET', url: '/v1/channels', headers: bearer(reader) });
    const asReader = theirs.json().channels.find((c: { id: string }) => c.id === channel.id);
    assert.equal(asReader.permissions.canPost, false);
    assert.equal(asReader.permissions.canManageMembers, false);
  });
  describe('the member list', () => {
    it('does not hand a subscriber the audience of a channel', async () => {
      // Anyone may join a public channel, so if joining came with the roster,
      // "join" would be the user-enumeration endpoint this API refuses to have.
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'publikum',
        title: 'Publikum',
      })).json();
      const alice = await registerUser(h.app, 'roster_alice');
      const bob = await registerUser(h.app, 'roster_bob');
      await join(alice, channel.id);
      await join(bob, channel.id);

      const seen = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(alice),
      });
      assert.equal(seen.statusCode, 200);
      assert.equal(seen.json().complete, false, 'a subscriber is told this is not everyone');

      const usernames = seen.json().members.map((m: { username: string }) => m.username);
      assert.deepEqual(
        usernames.sort(),
        ['owner', 'roster_alice'].sort(),
        'the people who run the channel, plus your own row — and nobody else',
      );
    });

    it('gives the whole list to a member who can act on it', async () => {
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'verwalten',
        title: 'Verwalten',
      })).json();
      const carol = await registerUser(h.app, 'roster_carol');
      await join(carol, channel.id);

      const seen = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(owner),
      });
      assert.equal(seen.json().complete, true);
      assert.deepEqual(
        seen.json().members.map((m: { username: string }) => m.username).sort(),
        ['owner', 'roster_carol'].sort(),
      );
    });

    it('an admin who cannot manage members still does not see the audience', async () => {
      // The permission that opens the list is the one that acts on it. Being
      // allowed to publish is not being allowed to read the subscriber base.
      const channel = (await createChannel(owner, {
        visibility: 'public',
        handle: 'schreiben',
        title: 'Schreiben',
      })).json();
      const dave = await registerUser(h.app, 'roster_dave');
      const erin = await registerUser(h.app, 'roster_erin');
      await join(dave, channel.id);
      await join(erin, channel.id);
      await setRole(owner, channel.id, dave, { role: 'admin', permissions: { canPost: true } });

      const seen = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}/members`,
        headers: bearer(dave),
      });
      assert.equal(seen.json().complete, false);
      const usernames = seen.json().members.map((m: { username: string }) => m.username);
      assert.ok(!usernames.includes('roster_erin'), 'a plain subscriber stays out of it');
      assert.ok(usernames.includes('roster_dave'), 'but they can see their own standing');
    });
  });

  describe('key rotation when somebody goes', () => {
    /*
     * The property under test is narrow and worth stating: a removed member
     * keeps what they had already read, and cannot read what is published
     * afterwards. Everything below is the server's half of that — the epoch
     * counter, the refusal of stale posts, and the arbitration between two
     * devices that both think they are generating the next key.
     *
     * The server never sees a channel key in any of it. That is checked too.
     */

    let channelId: string;
    let member: TestUser;
    let removed: TestUser;

    const currentEpoch = async (user: TestUser) =>
      (
        await h.app.inject({
          method: 'GET',
          url: `/v1/channels/${channelId}/key-epochs/current`,
          headers: bearer(user),
        })
      ).json();

    const claim = (user: TestUser, epoch: number, keyId: string) =>
      h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/key-epochs`,
        headers: bearer(user),
        payload: { epoch, keyId },
      });

    const publishAt = (user: TestUser, epoch: number, text: string) =>
      h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/posts`,
        headers: bearer(user),
        payload: { content: Buffer.from(text).toString('base64'), keyEpoch: epoch },
      });

    before(async () => {
      member = await registerUser(h.app, 'stays');
      removed = await registerUser(h.app, 'goes');
      const created = await createChannel(owner, {
        visibility: 'public',
        handle: 'rotation',
        title: 'Rotation',
      });
      channelId = created.json().id;
      for (const user of [member, removed]) {
        await h.app.inject({
          method: 'POST',
          url: `/v1/channels/${channelId}/join`,
          headers: bearer(user),
        });
      }
    });

    it('starts on epoch 1, with the migrated claim in place', async () => {
      const state = await currentEpoch(owner);
      assert.equal(state.epoch, 1);
      assert.equal(typeof state.keyId, 'string', 'a channel created now claims its own epoch 1');
    });

    it('a post carries the epoch that sealed it', async () => {
      const created = await publishAt(owner, 1, 'before anybody left');
      assert.equal(created.statusCode, 201, created.body);
      assert.equal(created.json().keyEpoch, 1);
    });

    it('removing a member advances the epoch', async () => {
      const before = (await currentEpoch(owner)).epoch;

      const response = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/members/${removed.accountId}`,
        headers: bearer(owner),
      });

      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.json().keyEpoch, before + 1);
      assert.equal((await currentEpoch(owner)).epoch, before + 1);
    });

    it('and leaves the new epoch unclaimed until a device generates a key', async () => {
      // A real state, not an error: the rotation has happened and nobody has
      // opened the app yet. The app has to be able to say so.
      assert.equal((await currentEpoch(owner)).keyId, null);
    });

    it('refuses a post under the old key once the rotation has happened', async () => {
      // The rule the whole milestone rests on. An author who was offline while
      // somebody was removed must not be able to publish under the key that
      // person still holds.
      const stale = await publishAt(owner, 1, 'this must not reach them');

      assert.equal(stale.statusCode, 409);
      assert.equal(stale.json().error, 'stale_key_epoch');
    });

    it('refuses a post claiming an epoch that does not exist yet', async () => {
      const ahead = await publishAt(owner, 99, 'from the future');
      assert.equal(ahead.statusCode, 409);
      assert.equal(ahead.json().error, 'unknown_key_epoch');
    });

    it('settles two devices claiming the same epoch: first writer wins', async () => {
      const epoch = (await currentEpoch(owner)).epoch;

      const mine = await claim(owner, epoch, 'key-id-from-owner');
      const theirs = await claim(owner, epoch, 'key-id-from-someone-else');

      assert.equal(mine.json().claimed, true);
      assert.equal(theirs.json().claimed, false, 'the loser is told it lost');
      assert.equal(
        theirs.json().keyId,
        'key-id-from-owner',
        'and is handed the winner, so it can ask for the right key',
      );
    });

    it('accepts a post under the epoch that was just claimed', async () => {
      const epoch = (await currentEpoch(owner)).epoch;
      const fresh = await publishAt(owner, epoch, 'after the rotation');
      assert.equal(fresh.statusCode, 201, fresh.body);
      assert.equal(fresh.json().keyEpoch, epoch);
    });

    it('a claim for a superseded epoch is refused, so a replay cannot reinstate a key', async () => {
      // The attack this closes: replaying yesterday's claim to put the channel
      // back on a key the removed member holds.
      const replay = await claim(owner, 1, 'key-id-from-owner');
      assert.equal(replay.statusCode, 409);
      assert.equal(replay.json().error, 'not_the_current_epoch');
    });

    it('the epoch cannot be walked backwards, even by the database', async () => {
      // Not a route — a constraint. A bug, a bad migration or a careless UPDATE
      // must not be able to undo a removal.
      await assert.rejects(
        pool.query('UPDATE channels SET key_epoch = 1 WHERE id = $1', [channelId]),
        /may not go backwards/,
      );
    });

    it('a member who is still in the channel reads both epochs', async () => {
      const feed = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts`,
        headers: bearer(member),
      });

      const epochs = feed.json().posts.map((p: { keyEpoch: number }) => p.keyEpoch);
      assert.ok(epochs.includes(1), 'the old posts are still there');
      assert.ok(epochs.some((e: number) => e > 1), 'and the new ones');
      // Which is the point of versioning rather than re-encrypting: nothing was
      // rewritten, so nobody lost access to anything they already had.
    });

    it('the removed member cannot fetch the feed at all', async () => {
      const feed = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts`,
        headers: bearer(removed),
      });
      assert.equal(feed.statusCode, 403);
    });

    it('a removed member handed the new ciphertext still cannot open it', async () => {
      // The honest version of the test the milestone asks for. The server can
      // demonstrate that the bytes differ under the two epochs; whether the old
      // key opens them is a question for the client suite, which drives real
      // AES-GCM. Here: the post exists, is sealed, and is marked as belonging
      // to an epoch the removed member was never given.
      const feed = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/posts`,
        headers: bearer(owner),
      });
      const after = feed
        .json()
        .posts.find((p: { keyEpoch: number }) => p.keyEpoch > 1);

      assert.ok(after, 'there is a post from after the removal');
      assert.notEqual(after.content, null);
      assert.ok(after.keyEpoch > 1, 'and it is answerable to an epoch they never held');
    });

    it('a pending request from a removed member is never listed', async () => {
      // Removal deletes their requests, but that is a delete racing an insert.
      // The row is put back by hand here, which is exactly what that race would
      // leave behind, and the answer must still be "nobody is waiting".
      await pool.query(
        `INSERT INTO key_requests (scope, scope_id, account_id, device_id)
         VALUES ('channel', $1, $2, $3) ON CONFLICT DO NOTHING`,
        [channelId, removed.accountId, removed.deviceId],
      );

      const waiting = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channelId}/key-requests`,
        headers: bearer(owner),
      });

      const accounts = waiting.json().requests.map((r: { accountId: string }) => r.accountId);
      assert.equal(
        accounts.includes(removed.accountId),
        false,
        'a request from someone who is no longer a member must not be answered',
      );
    });

    it('a subscriber cannot generate the channel key', async () => {
      // Otherwise anybody who can read the channel could decide who reads it
      // next, which is the permission being rotated away in the first place.
      const bump = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/members/me`,
        headers: bearer(member),
      });
      assert.equal(bump.statusCode, 200);

      const attempt = await claim(stranger, bump.json().keyEpoch, 'key-id-from-stranger');
      assert.ok(attempt.statusCode >= 400, attempt.body);
    });

    it('leaving rotates too — walking out is not a promise to stop reading', async () => {
      const walker = await registerUser(h.app, 'walks_out');
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/join`,
        headers: bearer(walker),
      });
      const before = (await currentEpoch(owner)).epoch;

      const left = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/members/me`,
        headers: bearer(walker),
      });

      assert.equal(left.statusCode, 200, left.body);
      assert.equal(left.json().keyEpoch, before + 1);
    });

    it('an epoch nobody holds can be stepped over, and the channel moves on', async () => {
      // The device that generated the current epoch is gone and took the key
      // with it. Nothing has been published under it — nothing can have been,
      // because publishing needs the key — so it is safe to leave behind.
      const before = (await currentEpoch(owner)).epoch;

      const abandoned = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/key-epochs/abandon`,
        headers: bearer(owner),
        payload: { epoch: before },
      });

      assert.equal(abandoned.statusCode, 200, abandoned.body);
      assert.equal(abandoned.json().keyEpoch, before + 1, 'forward, never back');
      const now = await currentEpoch(owner);
      assert.equal(now.epoch, before + 1);
      assert.equal(now.keyId, null, 'and the new one is there to be claimed');
    });

    it('the abandoned version cannot be claimed again with another key', async () => {
      // Reusing it would put two keys on one version and split the channel.
      const stale = await claim(owner, 1, 'key-id-after-the-fact');
      assert.equal(stale.statusCode, 409);
      assert.equal(stale.json().error, 'not_the_current_epoch');
    });

    it('an epoch with posts under it is refused, so nothing readable is stranded', async () => {
      const epoch = (await currentEpoch(owner)).epoch;
      await claim(owner, epoch, 'key-id-live');
      const published = await publishAt(owner, epoch, 'somebody does hold this key');
      assert.equal(published.statusCode, 201, published.body);

      const refused = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/key-epochs/abandon`,
        headers: bearer(owner),
        payload: { epoch },
      });

      assert.equal(refused.statusCode, 409);
      assert.equal(refused.json().error, 'epoch_has_posts');
      assert.equal((await currentEpoch(owner)).epoch, epoch, 'and nothing moved');
    });

    it('a subscriber cannot abandon an epoch', async () => {
      const epoch = (await currentEpoch(owner)).epoch;
      const attempt = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/key-epochs/abandon`,
        headers: bearer(stranger),
        payload: { epoch },
      });
      assert.ok(attempt.statusCode >= 400, attempt.body);
    });

    it('the same claim sent twice is answered the same way, not refused', async () => {
      // A device whose reply was lost sends the identical request again. It has
      // to be told it won, not that somebody else did.
      // A rotation of its own, so this starts from an epoch nobody has claimed.
      const passer = await registerUser(h.app, 'passes_through');
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channelId}/join`,
        headers: bearer(passer),
      });
      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/members/${passer.accountId}`,
        headers: bearer(owner),
      });

      const epoch = (await currentEpoch(owner)).epoch;
      const first = await claim(owner, epoch, 'key-id-idempotent');
      const again = await claim(owner, epoch, 'key-id-idempotent');

      assert.equal(first.json().claimed, true);
      assert.equal(again.json().claimed, true, 'the same key still wins its own epoch');
      assert.equal(again.json().keyId, 'key-id-idempotent');
    });

    it('the metadata epoch moves with the metadata, and only forwards', async () => {
      const patch = (epoch: number, metadata: string) =>
        h.app.inject({
          method: 'PATCH',
          url: `/v1/channels/${channelId}`,
          headers: bearer(owner),
          payload: {
            encryptedMetadata: Buffer.from(metadata).toString('base64'),
            metadataKeyEpoch: epoch,
          },
        });

      const forward = await patch(4, 'sealed under 4');
      assert.equal(forward.statusCode, 200, forward.body);
      assert.equal(forward.json().metadataKeyEpoch, 4);

      // A slow re-seal from an earlier rotation arriving late must not put the
      // name back under a key fewer members hold.
      const late = await patch(2, 'sealed under 2');
      assert.equal(late.json().metadataKeyEpoch, 4, 'the older re-seal does not win');
    });

    it('the server holds no channel key, before or after any of this', async () => {
      // The claim the whole design rests on, asserted rather than assumed.
      const { rows } = await pool.query(
        'SELECT key_id FROM channel_key_epochs WHERE channel_id = $1',
        [channelId],
      );
      assert.ok(rows.length > 0);
      for (const row of rows) {
        // 32 bytes of key would be 44 base64 characters. These are labels.
        assert.ok(row.key_id.length <= 64);
      }
      const columns = await pool.query(
        `SELECT column_name FROM information_schema.columns
         WHERE table_name IN ('channels', 'channel_key_epochs', 'channel_posts')`,
      );
      const names = columns.rows.map((r) => r.column_name as string);
      assert.equal(names.includes('key'), false);
      assert.equal(names.includes('channel_key'), false);
    });
  });
});
