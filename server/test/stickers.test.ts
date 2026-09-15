import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { checkSticker, readImageHeader, STICKER_LIMITS } from '../src/services/image_header.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Sticker and custom-emoji packs.
 *
 * The property under test throughout is **privacy by default**: a pack belongs
 * to its owner, a share is a code that can be taken back, and no request shape
 * reaches somebody else's pack without one.
 */

/** A real PNG, built here rather than fetched, so the bytes are known. */
function png(width: number, height: number): Buffer {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf: Buffer) => {
    let c = 0xffffffff;
    for (const byte of buf) c = crcTable[(c ^ byte) & 0xff]! ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, data: Buffer) => {
    const head = Buffer.alloc(4);
    head.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const tail = Buffer.alloc(4);
    tail.writeUInt32BE(crc(body));
    return Buffer.concat([head, body, tail]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA, so transparency is carried
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', Buffer.from([0x78, 0x9c, 0x63, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

describe('what the server accepts as a sticker', () => {
  it('reads a PNG header out of the bytes', () => {
    const header = readImageHeader(png(256, 128));
    assert.equal(header?.format, 'png');
    assert.equal(header?.width, 256);
    assert.equal(header?.height, 128);
    assert.equal(header?.supportsAlpha, true);
  });

  it('refuses something that is not an image at all', () => {
    // The whole point of reading the bytes: a client can claim any content
    // type it likes, and this does not consult the claim.
    assert.equal(checkSticker(Buffer.from('<?php echo 1; ?>')).refusal, 'not_an_image');
    assert.equal(checkSticker(Buffer.alloc(4096)).refusal, 'not_an_image');
  });

  it('refuses an image that is too big in either sense', () => {
    assert.equal(checkSticker(png(1024, 512)).refusal, 'dimensions_too_large');
    assert.equal(checkSticker(png(16, 16)).refusal, 'dimensions_too_small');
    const oversized = Buffer.concat([png(256, 256), Buffer.alloc(STICKER_LIMITS.maxBytes)]);
    assert.equal(checkSticker(oversized).refusal, 'too_large');
  });

  it('accepts one that fits', () => {
    const checked = checkSticker(png(512, 512));
    assert.equal(checked.refusal, undefined);
    assert.equal(checked.header?.width, 512);
  });
});

describe('sticker packs', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
    bob = await registerUser(h.app, 'bob');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  /** Uploads a sticker image and returns its media id. */
  const upload = async (user: TestUser, bytes = png(128, 128)) => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/media?kind=sticker',
      headers: { ...bearer(user), 'content-type': 'application/octet-stream' },
      payload: bytes,
    });
    assert.equal(response.statusCode, 201, response.body);
    return (response.json() as { id: string }).id;
  };

  const createPack = async (user: TestUser, title = 'Cats') => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/sticker-packs',
      headers: bearer(user),
      payload: { title, kind: 'sticker' },
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; shareCode: string | null };
  };

  const addItem = async (user: TestUser, packId: string, emoji = '😺') => {
    const mediaId = await upload(user);
    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/sticker-packs/${packId}/items`,
      headers: bearer(user),
      payload: { mediaId, emoji },
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; mediaId: string; position: number };
  };

  /** How many days from now a media object is set to live. */
  const lifetimeOf = async (mediaId: string) => {
    const { rows } = await pool.query<{ days: string }>(
      "SELECT extract(epoch FROM expires_at - now()) / 86400 AS days FROM media_objects WHERE id = $1",
      [mediaId],
    );
    assert.equal(rows.length, 1, 'no such media object');
    return Number(rows[0]!.days);
  };

  it('refuses an upload whose bytes are not an image', async () => {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/media?kind=sticker',
      headers: { ...bearer(alice), 'content-type': 'application/octet-stream' },
      payload: Buffer.from('not an image, whatever the header says'),
    });
    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error, 'not_an_image');
  });

  it('creates, renames and deletes a pack', async () => {
    const pack = await createPack(alice, 'Cats');

    const renamed = await h.app.inject({
      method: 'PATCH',
      url: `/v1/sticker-packs/${pack.id}`,
      headers: bearer(alice),
      payload: { title: 'Better cats' },
    });
    assert.equal(renamed.json().title, 'Better cats');

    const deleted = await h.app.inject({
      method: 'DELETE',
      url: `/v1/sticker-packs/${pack.id}`,
      headers: bearer(alice),
    });
    assert.equal(deleted.statusCode, 200);

    const gone = await h.app.inject({
      method: 'GET',
      url: `/v1/sticker-packs/${pack.id}`,
      headers: bearer(alice),
    });
    assert.equal(gone.statusCode, 404);
  });

  it('adds, re-emojis, reorders and removes items', async () => {
    const pack = await createPack(alice, 'Ordered');
    const first = await addItem(alice, pack.id, '1️⃣');
    const second = await addItem(alice, pack.id, '2️⃣');
    const third = await addItem(alice, pack.id, '3️⃣');

    const reordered = await h.app.inject({
      method: 'PUT',
      url: `/v1/sticker-packs/${pack.id}/order`,
      headers: bearer(alice),
      payload: { itemIds: [third.id, first.id, second.id] },
    });
    assert.equal(reordered.statusCode, 200);
    assert.deepEqual(
      (reordered.json().items as { id: string }[]).map((item) => item.id),
      [third.id, first.id, second.id],
    );

    const changed = await h.app.inject({
      method: 'PATCH',
      url: `/v1/sticker-packs/${pack.id}/items/${first.id}`,
      headers: bearer(alice),
      payload: { emoji: '🐈' },
    });
    assert.equal(changed.json().emoji, '🐈');

    await h.app.inject({
      method: 'DELETE',
      url: `/v1/sticker-packs/${pack.id}/items/${second.id}`,
      headers: bearer(alice),
    });
    const after = await h.app.inject({
      method: 'GET',
      url: `/v1/sticker-packs/${pack.id}`,
      headers: bearer(alice),
    });
    assert.equal((after.json().items as unknown[]).length, 2);
  });

  it('will not put somebody else’s upload in your pack', async () => {
    const pack = await createPack(alice, 'Mine');
    const bobsUpload = await upload(bob);

    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/sticker-packs/${pack.id}/items`,
      headers: bearer(alice),
      payload: { mediaId: bobsUpload, emoji: '😀' },
    });
    assert.equal(response.statusCode, 404);
  });

  describe('a pack is private until it is shared', () => {
    it('is invisible to anybody else, and says only "no such pack"', async () => {
      const pack = await createPack(alice, 'Secret');
      await addItem(alice, pack.id);

      const seen = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/${pack.id}`,
        headers: bearer(bob),
      });
      assert.equal(seen.statusCode, 404);

      // And guessing at a code does not help.
      const guessed = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/${pack.id}?code=aaaaaaaaaaaa`,
        headers: bearer(bob),
      });
      assert.equal(guessed.statusCode, 404);
    });

    it('opens to a live code, and the viewer is not handed the code itself',
      async () => {
        const pack = await createPack(alice, 'Shared');
        await addItem(alice, pack.id);

        const shared = await h.app.inject({
          method: 'POST',
          url: `/v1/sticker-packs/${pack.id}/share`,
          headers: bearer(alice),
        });
        const code = shared.json().shareCode as string;
        assert.ok(code && code.length >= 8);

        const preview = await h.app.inject({
          method: 'GET',
          url: `/v1/sticker-packs/by-code/${code}`,
          headers: bearer(bob),
        });
        assert.equal(preview.statusCode, 200);
        assert.equal(preview.json().title, 'Shared');
        // Bob can use the link he was sent; he cannot read the code back out
        // and hand on a capability Alice thinks only he has.
        assert.equal(preview.json().shareCode, null);
      });

    it('installs through the code, and stays installed after it is revoked', async () => {
      const pack = await createPack(alice, 'Revocable');
      await addItem(alice, pack.id);
      const shared = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });
      const code = shared.json().shareCode as string;

      const installed = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/install`,
        headers: bearer(bob),
        payload: { code },
      });
      assert.equal(installed.statusCode, 200);
      assert.equal(installed.json().installed, true);

      await h.app.inject({
        method: 'DELETE',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });

      // Revoking stops new people joining. It does not reach into Bob's
      // account and take away what he already has — that is a different act,
      // and this endpoint is not it.
      const stillThere = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/${pack.id}`,
        headers: bearer(bob),
      });
      assert.equal(stillThere.statusCode, 200);

      // But the old link is dead for everybody who had not used it.
      const carol = await registerUser(h.app, 'carol');
      const stale = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/by-code/${code}`,
        headers: bearer(carol),
      });
      assert.equal(stale.statusCode, 404);
    });

    it('issues a fresh code each time, so a regretted link can be replaced', async () => {
      const pack = await createPack(alice, 'Rotating');
      const first = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });
      const second = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });
      assert.notEqual(first.json().shareCode, second.json().shareCode);

      const dave = await registerUser(h.app, 'dave');
      const old = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/by-code/${first.json().shareCode}`,
        headers: bearer(dave),
      });
      assert.equal(old.statusCode, 404, 'the replaced link must be dead');
    });
  });

  describe('only the owner may change a pack', () => {
    it('refuses every write from somebody else', async () => {
      const pack = await createPack(alice, 'Alice’s');
      const item = await addItem(alice, pack.id);
      const shared = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });
      const code = shared.json().shareCode as string;
      // Bob installs it, so he can *read* it. That must not become a write.
      await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/install`,
        headers: bearer(bob),
        payload: { code },
      });

      const attempts = [
        { method: 'PATCH' as const, url: `/v1/sticker-packs/${pack.id}`, payload: { title: 'Bob’s now' } },
        { method: 'DELETE' as const, url: `/v1/sticker-packs/${pack.id}` },
        { method: 'POST' as const, url: `/v1/sticker-packs/${pack.id}/share` },
        { method: 'DELETE' as const, url: `/v1/sticker-packs/${pack.id}/share` },
        { method: 'PUT' as const, url: `/v1/sticker-packs/${pack.id}/order`, payload: { itemIds: [] } },
        { method: 'PATCH' as const, url: `/v1/sticker-packs/${pack.id}/items/${item.id}`, payload: { emoji: '💀' } },
        { method: 'DELETE' as const, url: `/v1/sticker-packs/${pack.id}/items/${item.id}` },
      ];
      for (const attempt of attempts) {
        const response = await h.app.inject({ ...attempt, headers: bearer(bob) });
        assert.equal(response.statusCode, 404, `${attempt.method} ${attempt.url}`);
      }

      // And it is unchanged.
      const after = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/${pack.id}`,
        headers: bearer(alice),
      });
      assert.equal(after.json().title, 'Alice’s');
      assert.equal((after.json().items as unknown[]).length, 1);
    });
  });

  describe('the images follow the pack', () => {
    it('are downloadable by somebody who installed it, and by nobody else', async () => {
      const pack = await createPack(alice, 'Pictures');
      const item = await addItem(alice, pack.id);

      const asOwner = await h.app.inject({
        method: 'GET',
        url: `/v1/media/${item.mediaId}`,
        headers: bearer(alice),
      });
      assert.equal(asOwner.statusCode, 200);

      // Anybody signed in who can name the id, because a sticker is sent to
      // people and almost none of them have installed the pack. The id is the
      // capability and it travels only inside sealed envelopes — see the note
      // on `mayDownload` in routes/media.ts.
      const asStranger = await h.app.inject({
        method: 'GET',
        url: `/v1/media/${item.mediaId}`,
        headers: bearer(bob),
      });
      assert.equal(asStranger.statusCode, 200);

      // But the *pack* is not opened by it: a private pack is still invisible
      // to somebody who was merely sent one of its stickers.
      const asPack = await h.app.inject({
        method: 'GET',
        url: `/v1/sticker-packs/${pack.id}`,
        headers: bearer(bob),
      });
      assert.equal(asPack.statusCode, 404);

      const shared = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/share`,
        headers: bearer(alice),
      });
      await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/install`,
        headers: bearer(bob),
        payload: { code: shared.json().shareCode },
      });

      const asInstaller = await h.app.inject({
        method: 'GET',
        url: `/v1/media/${item.mediaId}`,
        headers: bearer(bob),
      });
      assert.equal(asInstaller.statusCode, 200);
    });
    it('an upload in no pack is still its uploader s alone', async () => {
      // The other half of "the id is the capability": it becomes one when a
      // pack points at the object, not when the object exists. Otherwise an id
      // would be a download before anybody had decided to publish it.
      const loose = await upload(alice);

      const asStranger = await h.app.inject({
        method: 'GET',
        url: `/v1/media/${loose}`,
        headers: bearer(bob),
      });
      assert.equal(asStranger.statusCode, 404);

      const asOwner = await h.app.inject({
        method: 'GET',
        url: `/v1/media/${loose}`,
        headers: bearer(alice),
      });
      assert.equal(asOwner.statusCode, 200);
    });

    it('outlive the attachment window only once a pack points at them', async () => {
      // Where a sticker's long life is granted, and the reason it is granted
      // there: an upload is on the ordinary attachment clock until something
      // adopts it, exactly like an avatar. Doing it at upload instead would
      // keep an image nobody ever put in a pack for a hundred years.
      const mediaId = await upload(alice);
      const ttlDays = Number(process.env.MEDIA_TTL_DAYS ?? 30);
      const asUploaded = await lifetimeOf(mediaId);
      assert.ok(
        asUploaded < ttlDays + 1,
        `a bare upload keeps the ordinary window, got ${asUploaded} days`,
      );

      const pack = await createPack(alice, 'Kept');
      const added = await h.app.inject({
        method: 'POST',
        url: `/v1/sticker-packs/${pack.id}/items`,
        headers: bearer(alice),
        payload: { mediaId, emoji: '🐈' },
      });
      assert.equal(added.statusCode, 201, added.body);
      assert.ok(
        (await lifetimeOf(mediaId)) > 365,
        'adopting it is what extends it',
      );

      // And letting go of it puts it back, so a removed sticker is swept.
      const removed = await h.app.inject({
        method: 'DELETE',
        url: `/v1/sticker-packs/${pack.id}/items/${added.json().id}`,
        headers: bearer(alice),
      });
      assert.equal(removed.statusCode, 200);
      assert.ok((await lifetimeOf(mediaId)) <= 0, 'removing it lets it expire');
    });
  });

  describe('favourites and recents belong to the account', () => {
    it('come back after signing in again', async () => {
      const pack = await createPack(alice, 'Used');
      const item = await addItem(alice, pack.id);

      await h.app.inject({
        method: 'POST',
        url: '/v1/sticker-uses',
        headers: bearer(alice),
        payload: { itemIds: [item.id] },
      });
      await h.app.inject({
        method: 'PUT',
        url: `/v1/sticker-uses/${item.id}/favourite`,
        headers: bearer(alice),
        payload: { favourite: true },
      });

      const { deviceBody, deviceFixture } = await import('./helpers.js');
      const again = await h.app.inject({
        method: 'POST',
        url: '/v1/sessions',
        payload: {
          username: alice.username,
          password: alice.password,
          device: deviceBody(deviceFixture()),
        },
      });
      const second = again.json() as TestUser;

      const uses = await h.app.inject({
        method: 'GET',
        url: '/v1/sticker-uses',
        headers: bearer({ ...alice, token: second.token }),
      });
      const rows = uses.json().uses as { itemId: string; favourite: boolean }[];
      const found = rows.find((row) => row.itemId === item.id);
      assert.ok(found, 'the use survives a new session');
      assert.equal(found.favourite, true);
    });

    it('cannot be set on a sticker the account cannot reach', async () => {
      const pack = await createPack(alice, 'Private');
      const item = await addItem(alice, pack.id);

      const response = await h.app.inject({
        method: 'PUT',
        url: `/v1/sticker-uses/${item.id}/favourite`,
        headers: bearer(bob),
        payload: { favourite: true },
      });
      assert.equal(response.statusCode, 404);
    });

    it('does not list another account’s uses', async () => {
      const uses = await h.app.inject({
        method: 'GET',
        url: '/v1/sticker-uses',
        headers: bearer(bob),
      });
      const rows = uses.json().uses as unknown[];
      // Bob has used nothing of his own; Alice's rows are hers.
      assert.equal(rows.length, 0);
    });
  });
});
