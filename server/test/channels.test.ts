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

  it('only owners and admins publish', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'lesen',
      title: 'Lesen',
    })).json();
    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(reader),
      payload: {},
    });

    const asSubscriber = await post(reader, channel.id, 'darf-ich-nicht');
    assert.equal(asSubscriber.statusCode, 403);

    const promoted = await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/members/${reader.accountId}/role`,
      headers: bearer(owner),
      payload: { role: 'admin' },
    });
    assert.equal(promoted.statusCode, 200);
    assert.equal((await post(reader, channel.id, 'jetzt-schon')).statusCode, 201);
  });

  it('only the owner changes roles, so a channel cannot be taken over', async () => {
    const channel = (await createChannel(owner, {
      visibility: 'public',
      handle: 'uebernahme',
      title: 'Uebernahme',
    })).json();
    for (const user of [reader, stranger]) {
      await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(user),
        payload: {},
      });
    }
    await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/members/${reader.accountId}/role`,
      headers: bearer(owner),
      payload: { role: 'admin' },
    });

    const adminPromotingAdmin = await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/members/${stranger.accountId}/role`,
      headers: bearer(reader),
      payload: { role: 'admin' },
    });
    assert.equal(adminPromotingAdmin.statusCode, 403);
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
});
