import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * A group's picture and its description.
 *
 * The two are stored differently on purpose — the description is sealed with
 * the group key, the picture is not — so most of what is worth pinning here is
 * that seam: the server can never read the one, and hands the other only to
 * members.
 *
 * The test that matters most is the stranger who has the media id and still
 * gets a 404. A group has no public side; an id must not be a download.
 */
describe('a group picture and description', () => {
  let h: TestHarness;
  let admin: TestUser;
  let member: TestUser;
  let stranger: TestUser;
  let groupId: string;

  before(async () => {
    h = await createHarness();
    admin = await registerUser(h.app, 'gpadmin');
    member = await registerUser(h.app, 'gpmember');
    stranger = await registerUser(h.app, 'gpstranger');

    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/groups',
      headers: bearer(admin),
      payload: {
        memberIds: [member.accountId],
        encryptedMetadata: Buffer.from('sealed-group-name').toString('base64'),
      },
    });
    groupId = created.json().id as string;
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const upload = async (user: TestUser, kind: string) => {
    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/media?kind=${kind}`,
      headers: { ...bearer(user), 'content-type': 'application/octet-stream' },
      payload: Buffer.from('not-really-a-picture-but-opaque-either-way'),
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json().id as string;
  };

  it('an admin sets a picture, and every member can fetch it', async () => {
    const mediaId = await upload(admin, 'group_avatar');
    const set = await h.app.inject({
      method: 'PUT',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(admin),
      payload: { mediaId },
    });
    assert.equal(set.statusCode, 200, set.body);

    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(member),
    });
    assert.equal(detail.json().avatarMediaId, mediaId);
    assert.ok(detail.json().avatarUpdatedAt, 'a cache needs something to key off');

    const fetched = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${mediaId}`,
      headers: bearer(member),
    });
    assert.equal(fetched.statusCode, 200);
  });

  it('and a stranger holding the id gets nothing', async () => {
    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
    });
    const mediaId = detail.json().avatarMediaId as string;

    const fetched = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${mediaId}`,
      headers: bearer(stranger),
    });
    assert.equal(fetched.statusCode, 404, 'a group has no public side');
  });

  it('a member may not change it', async () => {
    const mediaId = await upload(member, 'group_avatar');
    const set = await h.app.inject({
      method: 'PUT',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(member),
      payload: { mediaId },
    });
    assert.equal(set.statusCode, 403);
  });

  it('and neither may somebody who is not in the group at all', async () => {
    const mediaId = await upload(stranger, 'group_avatar');
    const set = await h.app.inject({
      method: 'PUT',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(stranger),
      payload: { mediaId },
    });
    assert.equal(set.statusCode, 403);
  });

  it('an upload of the wrong kind is refused', async () => {
    // Otherwise an ordinary attachment could be attached and then fetched by
    // every member, whatever its own rules said.
    const mediaId = await upload(admin, 'attachment');
    const set = await h.app.inject({
      method: 'PUT',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(admin),
      payload: { mediaId },
    });
    assert.equal(set.statusCode, 400);
    assert.equal(set.json().error, 'wrong_media_kind');
  });

  it('and somebody else’s upload is not mine to attach', async () => {
    const mediaId = await upload(member, 'group_avatar');
    const set = await h.app.inject({
      method: 'PUT',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(admin),
      payload: { mediaId },
    });
    assert.equal(set.statusCode, 404);
  });

  it('removing it leaves the group without one', async () => {
    const cleared = await h.app.inject({
      method: 'DELETE',
      url: `/v1/groups/${groupId}/avatar`,
      headers: bearer(admin),
    });
    assert.equal(cleared.statusCode, 200);

    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
    });
    assert.equal(detail.json().avatarMediaId, null);
  });

  it('the description is stored as bytes the server cannot read', async () => {
    const sealed = Buffer.from('this-would-be-ciphertext');
    const saved = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
      payload: { encryptedDescription: sealed.toString('base64') },
    });
    assert.equal(saved.statusCode, 200, saved.body);

    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(member),
    });
    assert.equal(detail.json().encryptedDescription, sealed.toString('base64'));

    // What the database holds is the same bytes and nothing beside them: no
    // plaintext column got written on the way past.
    const { rows } = await pool.query<{ encrypted_description: Buffer | null }>(
      'SELECT encrypted_description FROM groups WHERE id = $1',
      [groupId],
    );
    assert.deepEqual(rows[0]!.encrypted_description, sealed);
  });

  it('changing only the name leaves the description alone', async () => {
    // The reason the route does not use COALESCE: omitting a field has to mean
    // "leave it", or a screen that renames a group would silently wipe its
    // description.
    const renamed = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
      payload: { encryptedMetadata: Buffer.from('a-new-sealed-name').toString('base64') },
    });
    assert.equal(renamed.statusCode, 200);

    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
    });
    assert.equal(
      detail.json().encryptedDescription,
      Buffer.from('this-would-be-ciphertext').toString('base64'),
    );
    assert.equal(
      detail.json().encryptedMetadata,
      Buffer.from('a-new-sealed-name').toString('base64'),
    );
  });

  it('and clearing it is a different request from not mentioning it', async () => {
    const cleared = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
      payload: { encryptedDescription: null },
    });
    assert.equal(cleared.statusCode, 200);

    const detail = await h.app.inject({
      method: 'GET',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
    });
    assert.equal(detail.json().encryptedDescription, null);
  });

  it('a member may not write the description either', async () => {
    const saved = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}`,
      headers: bearer(member),
      payload: { encryptedDescription: Buffer.from('mine-now').toString('base64') },
    });
    assert.equal(saved.statusCode, 403);
  });

  it('a PATCH that says nothing is refused rather than silently doing nothing', async () => {
    const empty = await h.app.inject({
      method: 'PATCH',
      url: `/v1/groups/${groupId}`,
      headers: bearer(admin),
      payload: {},
    });
    assert.equal(empty.statusCode, 400);
  });
});
