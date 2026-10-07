import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('contact profiles addressed by immutable ID', () => {
  let h: TestHarness;
  let owner: TestUser;
  let viewer: TestUser;
  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'profile_owner');
    viewer = await registerUser(h.app, 'profile_viewer');
  });
  after(async () => { await h?.close(); await closePool(); });
  const read = (as = viewer, id = owner.accountId) => h.app.inject({
    method: 'GET', url: `/v1/users/id/${id}`, headers: bearer(as),
  });

  it('requires authentication and returns only allowlisted fields', async () => {
    assert.equal((await h.app.inject({ method: 'GET', url: `/v1/users/id/${owner.accountId}` })).statusCode, 401);
    const response = await read();
    assert.equal(response.statusCode, 200);
    assert.equal(response.json().id, owner.accountId);
    assert.deepEqual(Object.keys(response.json()).sort(), [
      'id', 'username', 'displayName', 'avatarMediaId', 'avatarUpdatedAt', 'lastSeenAt', 'status', 'isContact', 'isBlocked',
      // Whether this account is operated by a program. Argued for rather than
      // waved through: every screen that draws a name has to draw the **BOT**
      // label beside it, and a label that needs a second request is a label
      // that is sometimes missing. It discloses nothing a bot is not meant to
      // announce.
      'isBot',
    ].sort());
    assert.equal(response.json().isBot, false, 'a person is not a bot');
  });

  it('checks the owner address book, not the viewer address book', async () => {
    await pool.query(`UPDATE accounts SET privacy = '{"lastSeen":"contacts","profileStatus":"contacts"}',
      status_text = 'Private status', last_seen_at = now() WHERE id = $1`, [owner.accountId]);
    const added = await h.app.inject({ method: 'POST', url: '/v1/contacts', headers: bearer(viewer), payload: { accountId: owner.accountId } });
    assert.equal(added.statusCode, 201);
    let profile = (await read()).json();
    assert.equal(profile.isContact, true);
    assert.equal(profile.status.text, null);
    assert.equal(profile.lastSeenAt, null);
    await h.app.inject({ method: 'POST', url: '/v1/contacts', headers: bearer(owner), payload: { accountId: viewer.accountId } });
    profile = (await read()).json();
    assert.equal(profile.status.text, 'Private status');
    assert.ok(profile.lastSeenAt);
    assert.equal((await read(owner)).json().status.text, 'Private status');
  });

  it('isolates relationships per viewer and does not expose reverse blocks', async () => {
    const stranger = await registerUser(h.app, 'profile_stranger');
    assert.equal((await read(stranger)).json().isContact, false);
    await h.app.inject({ method: 'POST', url: '/v1/blocks', headers: bearer(viewer), payload: { accountId: owner.accountId } });
    const blocked = (await read()).json();
    assert.equal(blocked.isBlocked, true);
    assert.equal(blocked.lastSeenAt, null);
    assert.equal(blocked.status.text, null);
    const reverse = (await read(owner, viewer.accountId)).json();
    assert.equal(reverse.isBlocked, false);
    await h.app.inject({ method: 'DELETE', url: `/v1/blocks/${owner.accountId}`, headers: bearer(viewer) });
    assert.equal((await read()).json().isBlocked, false);
  });

  it('removes only the current viewer contact relationship', async () => {
    assert.equal((await h.app.inject({ method: 'DELETE', url: `/v1/contacts/${owner.accountId}`, headers: bearer(viewer) })).statusCode, 200);
    assert.equal((await read()).json().isContact, false);
    assert.equal((await read(owner, viewer.accountId)).json().isContact, true);
  });

  it('returns not-found for deleted accounts', async () => {
    await pool.query('UPDATE accounts SET deleted_at = now() WHERE id = $1', [owner.accountId]);
    assert.equal((await read()).statusCode, 404);
  });
});
