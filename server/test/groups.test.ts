import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('groups', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;
  let carol: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
    bob = await registerUser(h.app, 'bob');
    carol = await registerUser(h.app, 'carol');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const createGroup = (owner: TestUser, memberIds: string[]) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(owner),
      payload: {
        memberIds,
        encryptedMetadata: Buffer.from('sealed-group-name').toString('base64'),
      },
    });

  it('creates a group whose name is opaque to the server', async () => {
    const response = await createGroup(alice, [bob.accountId, carol.accountId]);
    assert.equal(response.statusCode, 201);
    const group = response.json();
    assert.equal(group.members.length, 3);
    assert.equal(group.members.find((m: { id: string }) => m.id === alice.accountId).role, 'admin');

    const listed = await h.app.inject({ method: 'GET', url: '/v1/groups', headers: bearer(bob) });
    const seen = listed.json().groups[0];
    assert.equal(
      Buffer.from(seen.encryptedMetadata, 'base64').toString(),
      'sealed-group-name',
      'the server stores and returns the sealed blob without reading it',
    );
  });

  it('fans a message out to every member device but not back to the sender', async () => {
    const group = (await createGroup(alice, [bob.accountId, carol.accountId])).json();
    const devices = (
      await h.app.inject({ method: 'GET', url: `/v1/groups/${group.id}/devices`, headers: bearer(alice) })
    ).json().devices;
    assert.equal(devices.length, 2, 'the sender’s own device is excluded from the fan-out list');

    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/messages/group/${group.id}`,
      headers: bearer(alice),
      payload: {
        messages: devices.map((d: { deviceId: string }) => ({
          deviceId: d.deviceId,
          registrationId: 4242,
          type: 'ciphertext',
          content: Buffer.from('group-ciphertext').toString('base64'),
        })),
      },
    });
    assert.equal(response.statusCode, 202);
    assert.equal(response.json().deliveredTo, 2);

    const bobInbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
    assert.equal(bobInbox.json().envelopes[0].groupId, group.id);
    const aliceInbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(alice) });
    assert.equal(aliceInbox.json().envelopes.length, 0);
  });

  it('refuses posts and reads from non-members', async () => {
    const group = (await createGroup(alice, [bob.accountId])).json();
    const mallory = await registerUser(h.app, 'mallory');

    const read = await h.app.inject({ method: 'GET', url: `/v1/groups/${group.id}`, headers: bearer(mallory) });
    assert.equal(read.statusCode, 403);

    const post = await h.app.inject({
      method: 'POST',
      url: `/v1/messages/group/${group.id}`,
      headers: bearer(mallory),
      payload: {
        messages: [
          {
            deviceId: bob.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.from('x').toString('base64'),
          },
        ],
      },
    });
    assert.equal(post.statusCode, 403);
  });

  it('only lets admins change the group', async () => {
    const group = (await createGroup(alice, [bob.accountId])).json();
    const asMember = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${group.id}`,
      headers: bearer(bob),
      payload: { encryptedMetadata: Buffer.from('renamed').toString('base64') },
    });
    assert.equal(asMember.statusCode, 403);

    const asAdmin = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${group.id}`,
      headers: bearer(alice),
      payload: { encryptedMetadata: Buffer.from('renamed').toString('base64') },
    });
    assert.equal(asAdmin.statusCode, 200);
  });

  it('lets a member leave and never leaves a group without an admin', async () => {
    const group = (await createGroup(alice, [bob.accountId])).json();
    const left = await h.app.inject({
      method: 'DELETE',
      url: `/v1/groups/${group.id}/members/${alice.accountId}`,
      headers: bearer(alice),
    });
    assert.equal(left.statusCode, 200);

    const remaining = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${group.id}`,
      headers: bearer(bob),
    });
    assert.equal(remaining.json().role, 'admin', 'the longest-standing member is promoted');
  });

  it('honours a member’s "only contacts can add me" setting', async () => {
    const dave = await registerUser(h.app, 'dave');
    await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(dave),
      payload: { privacy: { whoCanAddMeToGroups: 'contacts' } },
    });

    const rejected = (await createGroup(alice, [dave.accountId])).json();
    assert.ok(
      !rejected.members.some((m: { id: string }) => m.id === dave.accountId),
      'a stranger cannot pull them into a group',
    );

    await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(dave),
      payload: { username: 'alice' },
    });
    const accepted = (await createGroup(alice, [dave.accountId])).json();
    assert.ok(accepted.members.some((m: { id: string }) => m.id === dave.accountId));
  });
  it('hands out a join link and lets a stranger in with it', async () => {
    const group = (await createGroup(alice, [bob.accountId])).json();
    assert.ok(group.inviteCode, 'a group is created with a code to share');

    // The code alone identifies the group, and tells the holder nothing more
    // than that: the name comes back sealed.
    const looked = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/invite/${group.inviteCode}`,
      headers: bearer(carol),
    });
    assert.equal(looked.statusCode, 200);
    assert.equal(looked.json().id, group.id);
    assert.equal(
      Buffer.from(looked.json().encryptedMetadata, 'base64').toString(),
      'sealed-group-name',
    );

    const joined = await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${group.id}/join`,
      headers: bearer(carol),
      payload: { inviteCode: group.inviteCode },
    });
    assert.equal(joined.statusCode, 200);
    assert.equal(joined.json().joined, true);
    assert.ok(joined.json().members.some((m: { id: string }) => m.id === carol.accountId));

    // And joining queues carol's device for the key to that sealed name.
    const pending = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${group.id}/key-requests`,
      headers: bearer(alice),
    });
    assert.equal(pending.json().requests.length, 1);
    assert.equal(pending.json().requests[0].accountId, carol.accountId);
  });

  it('answers a wrong invite code the same way as a group that does not exist', async () => {
    const group = (await createGroup(alice, [])).json();
    const wrong = await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${group.id}/join`,
      headers: bearer(carol),
      payload: { inviteCode: 'not-the-code' },
    });
    assert.equal(wrong.statusCode, 404);

    const missing = await h.app.inject({
      method: 'GET',
      url: '/v1/groups/invite/not-the-code',
      headers: bearer(carol),
    });
    assert.equal(missing.statusCode, 404);
    assert.equal(wrong.json().error, missing.json().error);
  });

  it('drops a key request when the member is removed', async () => {
    const group = (await createGroup(alice, [])).json();
    await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${group.id}/join`,
      headers: bearer(carol),
      payload: { inviteCode: group.inviteCode },
    });
    await h.app.inject({
      method: 'DELETE',
      url: `/v1/groups/${group.id}/members/${carol.accountId}`,
      headers: bearer(alice),
    });

    const pending = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${group.id}/key-requests`,
      headers: bearer(alice),
    });
    assert.equal(pending.json().requests.length, 0);
  });

  it('wakes the members who could answer a key request', async () => {
    const group = (await createGroup(alice, [bob.accountId])).json();

    const woken: string[] = [];
    const kinds: string[] = [];
    const unsubscribe = h.bus.subscribe((wake) => {
      if (wake.kind !== 'key-request') return;
      woken.push(wake.deviceId);
      kinds.push(wake.kind);
    });

    await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${group.id}/key-requests`,
      headers: bearer(bob),
    });
    unsubscribe();

    // Alice holds the key and is told at once. Without this the request waits
    // for her client's own poll, which is two minutes.
    assert.ok(woken.includes(alice.deviceId), 'the key holder is woken');
    assert.ok(
      !woken.includes(bob.deviceId),
      'the device that asked cannot answer itself',
    );
    assert.deepEqual([...new Set(kinds)], ['key-request']);
  });

  it('wakes nobody outside the group', async () => {
    const group = (await createGroup(alice, [])).json();

    const woken: string[] = [];
    const unsubscribe = h.bus.subscribe((wake) => {
      if (wake.kind === 'key-request') woken.push(wake.deviceId);
    });
    await h.app.inject({
      method: 'POST',
      url: `/v1/groups/${group.id}/key-requests`,
      headers: bearer(alice),
    });
    unsubscribe();

    assert.deepEqual(
      woken.filter((id) => id === carol.deviceId),
      [],
      'somebody who is not in the group learns nothing about it',
    );
  });
});
