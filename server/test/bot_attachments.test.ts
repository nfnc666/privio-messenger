import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Pictures and files a bot sends.
 *
 * The thing worth testing is not the upload, it is **who can fetch it**. A bot
 * attachment is not encrypted and not token-authorised; what stands between it
 * and everybody else is one row saying the bot sent it to this account. So most
 * of this is about people who must not get the bytes.
 */
describe('a bot sending a file', () => {
  let h: TestHarness;
  let owner: TestUser;
  let person: TestUser;
  let stranger: TestUser;
  let botId: string;
  let botToken: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'fileowner');
    person = await registerUser(h.app, 'fileperson');
    stranger = await registerUser(h.app, 'filestranger');

    const bot = await h.app.inject({
      method: 'POST',
      url: '/v1/bots',
      headers: bearer(owner),
      payload: { name: 'Filer', username: 'filerbot' },
    });
    botId = bot.json().id as string;
    botToken = (
      await h.app.inject({ method: 'POST', url: `/v1/bots/${botId}/token`, headers: bearer(owner) })
    ).json().token as string;

    // A bot may only answer somebody who started it.
    await h.app.inject({
      method: 'POST',
      url: `/v1/bots/${botId}/start`,
      headers: bearer(person),
    });
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asBot = () => ({ authorization: `Bearer ${botToken}` });

  const upload = (bytes: Buffer, query = '?kind=file&name=notes.txt') =>
    h.app.inject({
      method: 'POST',
      url: `/v1/bot/media${query}`,
      headers: { ...asBot(), 'content-type': 'application/octet-stream' },
      payload: bytes,
    });

  const send = (mediaId: string, extra: Record<string, unknown> = {}) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/bot/send',
      headers: asBot(),
      payload: { to: person.accountId, text: 'here it is', mediaId, ...extra },
    });

  const fetchAs = (user: TestUser, mediaId: string) =>
    h.app.inject({ method: 'GET', url: `/v1/media/${mediaId}`, headers: bearer(user) });

  it('uploads bytes and answers with an id', async () => {
    const uploaded = await upload(Buffer.from('hello from a bot'));
    assert.equal(uploaded.statusCode, 201, uploaded.body);
    assert.ok(uploaded.json().mediaId);
    assert.equal(uploaded.json().byteSize, 16);
    // No download token: the row that names the recipient authorises this one,
    // so a token would be a second answer to the same question.
    assert.equal('token' in uploaded.json(), false);
  });

  it('an empty body is refused', async () => {
    const empty = await h.app.inject({
      method: 'POST',
      url: '/v1/bot/media?kind=file&name=x.txt',
      headers: { ...asBot(), 'content-type': 'application/octet-stream' },
      payload: Buffer.alloc(0),
    });
    assert.equal(empty.statusCode, 400);
  });

  it('a name that could be read as a path is refused, not cleaned up', async () => {
    for (const name of ['../etc/passwd', 'a/b.txt', 'a\\b.txt']) {
      const refused = await upload(
        Buffer.from('x'),
        `?kind=file&name=${encodeURIComponent(name)}`,
      );
      assert.equal(refused.statusCode, 400, name);
    }
  });

  it('a session cannot upload one, and a bot token cannot use the human route',
    async () => {
      const asOwner = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/media?kind=file&name=x.txt',
        headers: { ...bearer(owner), 'content-type': 'application/octet-stream' },
        payload: Buffer.from('x'),
      });
      assert.equal(asOwner.statusCode, 401);

      const asBotOnHuman = await h.app.inject({
        method: 'POST',
        url: '/v1/media?kind=attachment',
        headers: { ...asBot(), 'content-type': 'application/octet-stream' },
        payload: Buffer.from('x'),
      });
      assert.equal(asBotOnHuman.statusCode, 401);
    });

  describe('who can fetch it', () => {
    let mediaId: string;

    before(async () => {
      mediaId = (await upload(Buffer.from('the bytes'))).json().mediaId as string;
    });

    it('nobody, before a message points at it', async () => {
      // The id is not the capability. An upload nobody has been sent is the
      // bot's own, and that is what stops an id from being a download.
      assert.equal((await fetchAs(person, mediaId)).statusCode, 404);
      assert.equal((await fetchAs(stranger, mediaId)).statusCode, 404);
    });

    it('the person it was sent to, once it has been', async () => {
      const sent = await send(mediaId, { mediaKind: 'file', fileName: 'notes.txt' });
      assert.equal(sent.statusCode, 200, sent.body);

      const fetched = await fetchAs(person, mediaId);
      assert.equal(fetched.statusCode, 200);
      assert.equal(fetched.rawPayload.toString(), 'the bytes');
    });

    it('and nobody else, however much they know the id', async () => {
      assert.equal((await fetchAs(stranger, mediaId)).statusCode, 404);
      // Not even the bot's owner, who is a person like any other here.
      assert.equal((await fetchAs(owner, mediaId)).statusCode, 404);
    });

    it('and not without signing in at all', async () => {
      const anonymous = await h.app.inject({ method: 'GET', url: `/v1/media/${mediaId}` });
      assert.equal(anonymous.statusCode, 401);
    });
  });

  describe('sending it', () => {
    it('refuses an id that is not this bot s upload', async () => {
      // A person's own attachment, named by a bot. This is the shape of handing
      // a stranger's file to a third person.
      const human = await h.app.inject({
        method: 'POST',
        url: '/v1/media?kind=attachment',
        headers: { ...bearer(owner), 'content-type': 'application/octet-stream' },
        payload: Buffer.from('somebody else s file'),
      });
      assert.equal(human.statusCode, 201, human.body);

      const refused = await send(human.json().id as string);
      assert.equal(refused.statusCode, 404);
      assert.equal(refused.json().error, 'media_not_found');
    });

    it('refuses an id that does not exist', async () => {
      const refused = await send('00000000-0000-4000-8000-000000000000');
      assert.equal(refused.statusCode, 404);
    });

    it('the conversation carries the kind, the name and the size', async () => {
      const uploaded = await upload(Buffer.from('a picture, supposedly'), '?kind=image&name=cat.png');
      const mediaId = uploaded.json().mediaId as string;
      const sent = await send(mediaId, { mediaKind: 'image', fileName: 'cat.png' });
      const messageId = sent.json().messageId as number;

      const conversation = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(person),
      });
      const message = (conversation.json().messages as Array<Record<string, unknown>>).find(
        (m) => m.id === messageId,
      );
      assert.ok(message, conversation.body);
      assert.equal(message.mediaId, mediaId);
      assert.equal(message.mediaKind, 'image');
      assert.equal(message.fileName, 'cat.png');
      assert.equal(message.byteSize, 21);
    });

    it('a message with no file says so with nulls, not with absent keys', async () => {
      const plain = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: person.accountId, text: 'no file here' },
      });
      const messageId = plain.json().messageId as number;
      const conversation = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(person),
      });
      const message = (conversation.json().messages as Array<Record<string, unknown>>).find(
        (m) => m.id === messageId,
      );
      assert.equal(message!.mediaId, null);
      assert.equal(message!.mediaKind, null);
      assert.equal(message!.byteSize, null);
    });

    it('a kind without an object is refused by the schema, not stored', async () => {
      // The constraint in migration 040 wants both or neither; the route makes
      // the kind follow the object so the constraint is never reached.
      const sent = await h.app.inject({
        method: 'POST',
        url: '/v1/bot/send',
        headers: asBot(),
        payload: { to: person.accountId, text: 'frame around nothing', mediaKind: 'image' },
      });
      assert.equal(sent.statusCode, 200, sent.body);
      const { rows } = await pool.query<{ media_kind: string | null }>(
        'SELECT media_kind FROM bot_messages WHERE id = $1',
        [sent.json().messageId],
      );
      assert.equal(rows[0]!.media_kind, null);
    });
  });

  describe('when the blob is gone', () => {
    it('the message stays, with no file', async () => {
      const uploaded = await upload(Buffer.from('will expire'));
      const mediaId = uploaded.json().mediaId as string;
      const sent = await send(mediaId, { mediaKind: 'file', fileName: 'gone.txt' });
      const messageId = sent.json().messageId as number;

      // What the retention sweeper does.
      await pool.query('DELETE FROM media_objects WHERE id = $1', [mediaId]);

      const conversation = await h.app.inject({
        method: 'GET',
        url: `/v1/bots/${botId}/messages`,
        headers: bearer(person),
      });
      const message = (conversation.json().messages as Array<Record<string, unknown>>).find(
        (m) => m.id === messageId,
      );
      assert.ok(message, 'the message disappeared with its file');
      assert.equal(message.mediaId, null);
      assert.equal(message.fileName, 'gone.txt', 'the name is still worth showing');
    });
  });
});
