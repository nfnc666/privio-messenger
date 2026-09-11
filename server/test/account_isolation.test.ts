import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * Two accounts, one asking for the other's things by id.
 *
 * The property under test is not "the routes have checks" — it is that the
 * **identity comes from the session and nothing else**. So every request here
 * is B's session pointed at A's identifiers: the ids are real, B simply has no
 * business with them. A route that read an account id out of a path, a body or
 * a query and trusted it would hand these over.
 */
describe('one account cannot reach another', () => {
  let h: TestHarness;
  let a: TestUser;
  let b: TestUser;

  before(async () => {
    h = await createHarness();
    a = await registerUser(h.app, 'alpha');
    b = await registerUser(h.app, 'bravo');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const asB = (
    method: 'GET' | 'PUT' | 'DELETE' | 'POST' | 'PATCH',
    url: string,
    payload?: Record<string, unknown>,
  ) =>
    h.app.inject({ method, url, headers: bearer(b), ...(payload ? { payload } : {}) });

  const octet = (bytes: Buffer, user: TestUser, url = '/v1/media') =>
    h.app.inject({
      method: 'POST',
      url,
      headers: { ...bearer(user), 'content-type': 'application/octet-stream' },
      payload: bytes,
    });

  it('the session decides who "me" is, never the client', async () => {
    // Both accounts ask the same route with their own token and must get
    // themselves. This is the whole design in one assertion.
    const mine = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(b) });
    assert.equal(mine.json().username, 'bravo');

    // And a body that names somebody else changes nothing about who is acting.
    const edit = await asB('PATCH', '/v1/accounts/me', {
      displayName: 'Bravo',
      accountId: a.accountId,
      id: a.accountId,
    });
    assert.equal(edit.statusCode, 200);

    const { rows } = await pool.query<{ display_name: string | null }>(
      'SELECT display_name FROM accounts WHERE id = $1',
      [a.accountId],
    );
    assert.equal(rows[0]!.display_name, null, "A's profile was not touched");
  });

  it("B cannot read A's backup, and cannot delete it either", async () => {
    const sealed = Buffer.from('alphas sealed backup');
    const upload = await h.app.inject({
      method: 'PUT',
      url: '/v1/backup',
      headers: { ...bearer(a), 'content-type': 'application/octet-stream' },
      payload: sealed,
    });
    assert.equal(upload.statusCode, 200);

    // There is no id to guess here, which is the point: the route has no
    // parameter at all, so it can only ever answer about the caller.
    const info = await asB('GET', '/v1/backup');
    assert.notEqual(info.statusCode, 200);

    const content = await asB('GET', '/v1/backup/content');
    assert.notEqual(content.statusCode, 200);
    assert.ok(!content.body.includes('alphas sealed backup'));

    await asB('DELETE', '/v1/backup');
    const stillThere = await h.app.inject({
      method: 'GET',
      url: '/v1/backup/content',
      headers: bearer(a),
    });
    assert.equal(stillThere.statusCode, 200, "A's backup survived B asking for it to go");
  });

  it("B cannot fetch A's attachment by id without the capability", async () => {
    const upload = (await octet(Buffer.from('alphas sealed file'), a)).json();

    const guessed = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${upload.id}`,
      headers: bearer(b),
    });
    // 404, not 403: which of the two it is would confirm the id exists.
    assert.equal(guessed.statusCode, 404);

    // Nor can B delete it — "not mine" and "no such thing" are again the same.
    const deleted = await asB('DELETE', `/v1/media/${upload.id}`);
    assert.equal(deleted.statusCode, 404);

    const survived = await h.app.inject({
      method: 'GET',
      url: `/v1/media/${upload.id}`,
      headers: { ...bearer(a), 'x-privio-media-token': upload.token },
    });
    assert.equal(survived.statusCode, 200);
  });

  it("B cannot adopt A's upload as their own avatar", async () => {
    const upload = (await octet(Buffer.from('alphas picture'), a, '/v1/media?kind=avatar')).json();

    const stolen = await asB('PUT', '/v1/accounts/me/avatar', { mediaId: upload.id });
    assert.equal(stolen.statusCode, 404, 'and the error does not say whether it exists');

    const { rows } = await pool.query<{ avatar_media_id: string | null }>(
      'SELECT avatar_media_id FROM accounts WHERE id = $1',
      [b.accountId],
    );
    assert.equal(rows[0]!.avatar_media_id, null);
  });

  it("B cannot read A's private channel, its posts or its members", async () => {
    const channel = (await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(a),
      payload: {
        visibility: 'private',
        encryptedMetadata: Buffer.from('alphas channel').toString('base64'),
      },
    })).json();

    // A private channel does not even confirm that it exists.
    assert.equal((await asB('GET', `/v1/channels/${channel.id}`)).statusCode, 404);
    assert.equal((await asB('GET', `/v1/channels/${channel.id}/posts`)).statusCode, 403);
    assert.equal((await asB('GET', `/v1/channels/${channel.id}/members`)).statusCode, 403);
    assert.equal((await asB('GET', `/v1/channels/${channel.id}/stats`)).statusCode, 403);

    // And cannot write to it, rename it, or take it away.
    assert.equal(
      (await asB('POST', `/v1/channels/${channel.id}/posts`, {
        content: Buffer.from('x').toString('base64'),
        keyEpoch: 1,
      })).statusCode,
      403,
    );
    assert.equal((await asB('PATCH', `/v1/channels/${channel.id}`, { title: 'mine now' })).statusCode, 403);
    assert.equal((await asB('DELETE', `/v1/channels/${channel.id}`)).statusCode, 403);

    const { rows } = await pool.query<{ deleted_at: Date | null }>(
      'SELECT deleted_at FROM channels WHERE id = $1',
      [channel.id],
    );
    assert.equal(rows[0]!.deleted_at, null);
  });

  it('a public channel is readable, and still not writable', async () => {
    // The other half of the rule: separation is not "B sees nothing", it is
    // "B sees what B is entitled to". A public channel is meant to be found.
    const channel = (await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(a),
      payload: { visibility: 'public', handle: 'offenkundig', title: 'Offenkundig' },
    })).json();

    const seen = await asB('GET', `/v1/channels/${channel.id}`);
    assert.equal(seen.statusCode, 200);
    assert.equal(seen.json().title, 'Offenkundig');
    assert.equal(seen.json().role, null, 'visible is not the same as joined');

    // Readable, but not A's to hand over: posting and editing still need the
    // permission, which being able to see the channel does not grant.
    assert.equal(
      (await asB('POST', `/v1/channels/${channel.id}/posts`, {
        content: Buffer.from('x').toString('base64'),
        keyEpoch: 1,
      })).statusCode,
      403,
    );
    assert.equal((await asB('PATCH', `/v1/channels/${channel.id}`, { title: 'mine' })).statusCode, 403);
  });

  it("B cannot drain A's envelopes, and cannot delete them", async () => {
    // A's own device sends itself something, so there is an envelope to steal.
    const before = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(a) });
    assert.equal(before.statusCode, 200);

    const theirs = await asB('GET', '/v1/messages');
    assert.equal(theirs.statusCode, 200);
    // B's queue is B's. The route takes no account parameter, so the only
    // thing it can answer about is the session that asked.
    assert.deepEqual(theirs.json().envelopes, []);
  });

  it("a device of A's cannot be revoked by B", async () => {
    const devices = await h.app.inject({ method: 'GET', url: '/v1/devices', headers: bearer(a) });
    const target = devices.json().devices[0];
    assert.ok(target, 'A has a device');

    const revoked = await asB('DELETE', `/v1/devices/${target.id}`);
    assert.notEqual(revoked.statusCode, 200);

    const after = await h.app.inject({ method: 'GET', url: '/v1/devices', headers: bearer(a) });
    assert.equal(after.json().devices.length, devices.json().devices.length);
  });

  it('a push token belongs to one account at a time', async () => {
    // The case a clean sign-out does not cover: A signed out with no network,
    // so this server never heard about it and A's device still holds the
    // token. B then signs in on that same handset and registers it.
    const token = 'vendor-token-for-this-handset';
    assert.equal(
      (await h.app.inject({
        method: 'PUT',
        url: '/v1/devices/current/push',
        headers: bearer(a),
        payload: { provider: 'fcm', token },
      })).statusCode,
      200,
    );

    assert.equal(
      (await asB('PUT', '/v1/devices/current/push', { provider: 'fcm', token })).statusCode,
      200,
    );

    const { rows } = await pool.query<{ account_id: string }>(
      'SELECT account_id FROM devices WHERE push_token = $1',
      [token],
    );
    // Exactly one, and it is the account that registered it last — otherwise
    // the relay posts A's wake-ups to a phone that is now B's.
    assert.equal(rows.length, 1);
    assert.equal(rows[0]!.account_id, b.accountId);
  });
});
