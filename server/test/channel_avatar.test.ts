import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { runRetentionSweep } from '../src/services/cleanup.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * A channel's picture.
 *
 * Two storage paths, chosen by what the channel already is, and most of what
 * is worth pinning down here is the seam between them: a **public** channel's
 * picture is unsealed, because it is drawn on a web page and inside a
 * messenger's link preview where nobody holds a key; a **private** channel's
 * is sealed with the channel key like its name and its posts.
 *
 * The test that matters most is the one that says a private channel cannot
 * point at the unsealed kind. Everything else here is plumbing; that one is
 * the difference between a picture somebody believes is sealed and a picture
 * anybody can fetch.
 */
describe('a channel picture', () => {
  let h: TestHarness;
  let owner: TestUser;
  let stranger: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'picowner');
    stranger = await registerUser(h.app, 'picstranger');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  /** A real PNG header, because the public route serves by magic number. */
  const png = (tail: string) =>
    Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), Buffer.from(tail)]);

  const upload = async (bytes: Buffer, user: TestUser, kind: string) => {
    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/media?kind=${kind}`,
      headers: { ...bearer(user), 'content-type': 'application/octet-stream' },
      payload: bytes,
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; token?: string };
  };

  const createChannel = async (payload: Record<string, unknown>, user: TestUser = owner) => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(user),
      payload,
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json();
  };

  const setAvatar = (channelId: string, mediaId: string, user: TestUser = owner) =>
    h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channelId}/avatar`,
      headers: bearer(user),
      payload: { mediaId },
    });

  let publicChannel: { id: string; handle: string };
  let publicAvatar: { id: string };

  it('a public channel takes an unsealed picture and reports it', async () => {
    publicChannel = await createChannel({
      visibility: 'public',
      handle: 'mitbild',
      title: 'Mit Bild',
      description: 'Hat ein Profilbild',
    });
    publicAvatar = await upload(png('public-channel-picture'), owner, 'channel_avatar');

    const set = await setAvatar(publicChannel.id, publicAvatar.id);
    assert.equal(set.statusCode, 200, set.body);
    assert.equal(set.json().avatarMediaId, publicAvatar.id);

    const view = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${publicChannel.id}`,
      headers: bearer(owner),
    });
    assert.equal(view.json().avatarMediaId, publicAvatar.id);
    assert.ok(view.json().avatarUpdatedAt, 'so a cache knows the picture moved');
  });

  it('and somebody who is not in it can still see that picture', async () => {
    // This is the whole point of the unsealed kind: a public channel in a list
    // of search results is being looked at by people who are not members, and
    // a channel with no picture there is a channel nobody recognises.
    const fetched = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${publicAvatar.id}`,
      headers: bearer(stranger),
    });
    assert.equal(fetched.statusCode, 200);
    assert.deepEqual(fetched.rawPayload, png('public-channel-picture'));
  });

  it('the web page draws it, and hands it to a link preview', async () => {
    const page = await h.app.inject({ method: 'GET', url: '/mitbild' });
    assert.equal(page.statusCode, 200);
    assert.ok(page.body.includes('/assets/channel/mitbild'), 'in the card');
    assert.match(page.body, /og:image" content="http[^"]*\/assets\/channel\/mitbild"/);

    const image = await h.app.inject({ method: 'GET', url: '/assets/channel/mitbild' });
    assert.equal(image.statusCode, 200, 'and served without any credential');
    assert.equal(image.headers['content-type'], 'image/png');
    assert.equal(image.headers['x-content-type-options'], 'nosniff');
    assert.deepEqual(image.rawPayload, png('public-channel-picture'));
  });

  it('bytes that are not an image are not served as one', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'keinbild',
      title: 'Kein Bild',
    });
    // An upload is opaque `application/octet-stream`; the server does not know
    // what it was handed. Serving it back under a content type taken on trust
    // is how a "picture" becomes an HTML page on this origin.
    const notAnImage = await upload(
      Buffer.from('<html><script>alert(1)</script></html>'),
      owner,
      'channel_avatar',
    );
    assert.equal((await setAvatar(channel.id, notAnImage.id)).statusCode, 200);

    const served = await h.app.inject({ method: 'GET', url: '/assets/channel/keinbild' });
    assert.equal(served.statusCode, 404);

    // And the page falls back to the mark rather than to a broken image.
    const page = await h.app.inject({ method: 'GET', url: '/keinbild' });
    assert.equal(page.statusCode, 200);
    assert.ok(page.body.includes('privio-mark.png'));
  });

  it('a private channel takes the unsealed kind too, and keeps it to its members',
    async () => {
    const channel = await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('sealed name').toString('base64'),
    });
    const media = await upload(png('private-channel-picture'), owner, 'channel_avatar');
    assert.equal((await setAvatar(channel.id, media.id)).statusCode, 200);

    // Not sealed — the owner gets the bytes straight back.
    const mine = await h.app.inject({
      method: 'GET', url: `/v1/media/${media.id}`, headers: bearer(owner),
    });
    assert.equal(mine.statusCode, 200);
    assert.deepEqual(mine.rawPayload, png('private-channel-picture'));

    // But a stranger does not. This is the whole of what replaced the
    // encryption: the picture is withheld rather than unreadable, and that is
    // a weaker promise stated plainly rather than a stronger one implied.
    const theirs = await h.app.inject({
      method: 'GET', url: `/v1/media/${media.id}`, headers: bearer(stranger),
    });
    assert.equal(theirs.statusCode, 404);

    // A member does.
    await h.app.inject({
      method: 'POST', url: `/v1/channels/${channel.id}/join`, headers: bearer(stranger),
      payload: { inviteCode: channel.inviteCode },
    });
    const asMember = await h.app.inject({
      method: 'GET', url: `/v1/media/${media.id}`, headers: bearer(stranger),
    });
    assert.equal(asMember.statusCode, 200);
  });

  it('a picture no channel points at is nobody\'s', async () => {
    // Uploaded and never attached: the uploader may still have it, and an id
    // on its own must not be a download for anybody else.
    const orphan = await upload(png('never-attached'), owner, 'channel_avatar');
    const peek = await h.app.inject({
      method: 'GET', url: `/v1/media/${orphan.id}`, headers: bearer(stranger),
    });
    assert.equal(peek.statusCode, 404);
  });

  it('every channel refuses a sealed upload as its picture', async () => {
    for (const payload of [
      { visibility: 'public', handle: 'falschherum', title: 'Falsch herum' },
      { visibility: 'private', encryptedMetadata: Buffer.from('x').toString('base64') },
    ]) {
      const channel = await createChannel(payload);
      const sealed = await upload(png('sealed'), owner, 'attachment');
      const refused = await setAvatar(channel.id, sealed.id);
      // One kind for every channel, so the wrong one is an answer about the
      // upload rather than about the channel.
      assert.equal(refused.statusCode, 400, `${payload.visibility}`);
      assert.equal(refused.json().error, 'wrong_media_kind');
    }
  });

  it('only somebody who may edit the channel may change it', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'nurmods',
      title: 'Nur Mods',
    });
    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(stranger),
    });
    const theirs = await upload(png('subscriber'), stranger, 'channel_avatar');

    const refused = await setAvatar(channel.id, theirs.id, stranger);
    assert.equal(refused.statusCode, 403);
    assert.equal(refused.json().error, 'insufficient_permission');

    const removal = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/avatar`,
      headers: bearer(stranger),
    });
    assert.equal(removal.statusCode, 403, 'and taking one away is the same permission');
  });

  it('and it has to be their own upload', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'fremdesbild',
      title: 'Fremdes Bild',
    });
    const theirs = await upload(png('not-yours'), stranger, 'channel_avatar');

    const stolen = await setAvatar(channel.id, theirs.id);
    // 404 rather than 403: which of the two it is would confirm that an id
    // exists, which is a thing an id should not be able to confirm.
    assert.equal(stolen.statusCode, 404);
    assert.equal(stolen.json().error, 'media_not_found');
  });

  it('the picture is not swept away with the attachments', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'bleibt',
      title: 'Bleibt',
    });
    const media = await upload(png('keeps-existing'), owner, 'channel_avatar');
    await setAvatar(channel.id, media.id);

    const { rows } = await pool.query<{ expires_at: Date }>(
      'SELECT expires_at FROM media_objects WHERE id = $1',
      [media.id],
    );
    assert.ok(
      rows[0]!.expires_at.getTime() > Date.now() + 365 * 86_400_000,
      'becoming a picture lifts the attachment window',
    );

    // And should anything push it back anyway, the sweep skips it.
    await pool.query("UPDATE media_objects SET expires_at = now() - interval '1 day' WHERE id = $1", [
      media.id,
    ]);
    await runRetentionSweep(h.storage);
    const after = await pool.query('SELECT id FROM media_objects WHERE id = $1', [media.id]);
    assert.equal(after.rowCount, 1);
  });

  it('replacing one lets the old picture go', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'ersetzt',
      title: 'Ersetzt',
    });
    const first = await upload(png('one'), owner, 'channel_avatar');
    const second = await upload(png('two'), owner, 'channel_avatar');
    await setAvatar(channel.id, first.id);
    await setAvatar(channel.id, second.id);
    await runRetentionSweep(h.storage);

    const old = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${first.id}`,
      headers: bearer(owner),
    });
    assert.equal(old.statusCode, 404, "the replaced picture is nobody's");
    const current = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${second.id}`,
      headers: bearer(owner),
    });
    assert.equal(current.statusCode, 200);
  });

  it('removing one lets it go too', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'entferntbild',
      title: 'Entfernt',
    });
    const media = await upload(png('removed'), owner, 'channel_avatar');
    await setAvatar(channel.id, media.id);

    const removed = await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}/avatar`,
      headers: bearer(owner),
    });
    assert.equal(removed.statusCode, 200);
    assert.equal(removed.json().avatarMediaId, null);

    await runRetentionSweep(h.storage);
    const gone = await pool.query('SELECT id FROM media_objects WHERE id = $1', [media.id]);
    assert.equal(gone.rowCount, 0);

    const page = await h.app.inject({ method: 'GET', url: '/assets/channel/entferntbild' });
    assert.equal(page.statusCode, 404);
  });

  it('deleting the channel lets its picture go', async () => {
    const channel = await createChannel({
      visibility: 'public',
      handle: 'geloescht',
      title: 'Geloescht',
    });
    const media = await upload(png('goes-with-it'), owner, 'channel_avatar');
    await setAvatar(channel.id, media.id);

    await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(owner),
    });

    // A soft delete keeps the channel row forever, so without this the picture
    // would sit in storage for a hundred years held by a reference from
    // something nobody can ever open again.
    await runRetentionSweep(h.storage);
    const gone = await pool.query('SELECT id FROM media_objects WHERE id = $1', [media.id]);
    assert.equal(gone.rowCount, 0);
  });

  it('the public picture route answers for nothing but a live public channel', async () => {
    // Never for a private one — its picture is sealed and reached with the
    // token from its own sealed metadata, never from a route that asks for no
    // credential at all.
    const priv = await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    });
    const sealed = await upload(png('sealed'), owner, 'attachment');
    await setAvatar(priv.id, sealed.id);

    // A private channel has no handle, so there is no path to ask for — which
    // is the point, and this says so rather than leaving it to inspection.
    const { rows } = await pool.query('SELECT handle FROM channels WHERE id = $1', [priv.id]);
    assert.equal(rows[0].handle, null);

    assert.equal((await h.app.inject({ method: 'GET', url: '/assets/channel/nichtda' })).statusCode, 404);
  });
});
