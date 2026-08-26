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
});
