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
});
