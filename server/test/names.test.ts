import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { cleanDisplayName, visibleLength } from '../src/services/display_name.js';
import {
  bearer,
  closePool,
  createHarness,
  deviceBody,
  deviceFixture,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * Two names, and the difference between them.
 *
 * A username is an address: it is how somebody is found, it is what an invite
 * link carries, and it is the one thing on a profile row that cannot be chosen
 * to look like somebody else's. So it is fixed, and these tests are mostly
 * about the ways it could stop being fixed.
 *
 * A display name is the opposite — it is what a person calls themselves, it
 * may be anything, it may collide with anybody, and it may change as often as
 * they like. Nothing is keyed on it.
 */
let h: TestHarness;
before(async () => {
  h = await createHarness();
});
after(async () => {
  await h?.close();
  await closePool();
});

describe('a username is permanent', () => {

  it('is free until it is taken, and then it is taken', async () => {
    const free = await h.app.inject({ method: 'GET', url: '/v1/usernames/quiet.badger' });
    assert.equal(free.statusCode, 200);
    assert.deepEqual(free.json(), { username: 'quiet.badger', available: true, reason: null });

    const user = await registerUser(h.app, 'quiet.badger');
    assert.ok(user.accountId);

    const taken = await h.app.inject({ method: 'GET', url: '/v1/usernames/quiet.badger' });
    assert.deepEqual(taken.json(), { username: 'quiet.badger', available: false, reason: 'taken' });

    // And the second registration is refused, rather than quietly making a
    // second account that answers to the same name.
    const again = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username: 'quiet.badger', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(again.statusCode, 409);
    assert.equal(again.json().error, 'username_taken');
  });

  it('answers a malformed name with the rule rather than a validation blob', async () => {
    const shouted = await h.app.inject({ method: 'GET', url: '/v1/usernames/No' });
    assert.deepEqual(shouted.json(), { username: 'no', available: false, reason: 'format' });
  });

  it('cannot be had twice by changing the case of it', async () => {
    // The column only accepts lowercase and the API lowercases on the way in,
    // so `Lighthouse` and `lighthouse` are one name rather than two accounts
    // whose display is indistinguishable in a chat list.
    await registerUser(h.app, 'lighthouse');
    const shouted = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username: 'LIGHTHOUSE', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(shouted.statusCode, 409);

    const check = await h.app.inject({ method: 'GET', url: '/v1/usernames/LightHouse' });
    assert.deepEqual(check.json(), { username: 'lighthouse', available: false, reason: 'taken' });
  });

  it('is taken exactly once when two registrations race for it', async () => {
    // Both requests pass the "is it free" check before either insert lands.
    // What separates them is the UNIQUE constraint, not the lookup — which is
    // why the lookup is not the thing being tested here.
    const attempt = () =>
      h.app.inject({
        method: 'POST',
        url: '/v1/accounts',
        payload: { username: 'racecondition', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
      });

    const [first, second] = await Promise.all([attempt(), attempt()]);
    const codes = [first.statusCode, second.statusCode].sort();
    assert.deepEqual(codes, [201, 409], `expected one winner and one conflict, got ${codes}`);

    const { rows } = await pool.query('SELECT count(*)::int AS n FROM accounts WHERE username = $1', [
      'racecondition',
    ]);
    assert.equal(rows[0].n, 1);
  });

  it('is refused by the API, out loud, rather than silently ignored', async () => {
    const user = await registerUser(h.app, 'fixedname');

    const patched = await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(user),
      payload: { username: 'newname', displayName: 'Fixed Name' },
    });
    assert.equal(patched.statusCode, 403);
    assert.equal(patched.json().error, 'username_immutable');

    // Nothing in the request was applied — not the rename, and not the name
    // change that rode along with it.
    const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
    assert.equal(me.json().username, 'fixedname');
    assert.equal(me.json().displayName, null);

    // And there is no other door: no route renames an account.
    const put = await h.app.inject({
      method: 'PUT',
      url: '/v1/accounts/me/username',
      headers: bearer(user),
      payload: { username: 'newname' },
    });
    assert.equal(put.statusCode, 404);
  });

  it('is refused by the database, which is where the guarantee actually lives', async () => {
    // The route above is a courtesy. This is the rule: a direct UPDATE — a
    // future handler, a migration script, somebody at a psql prompt — cannot
    // rename a live account either. See migration 035.
    const user = await registerUser(h.app, 'databaserule');
    await assert.rejects(
      () => pool.query('UPDATE accounts SET username = $2 WHERE id = $1', [user.accountId, 'renamed']),
      /username is permanent/,
    );

    const { rows } = await pool.query('SELECT username FROM accounts WHERE id = $1', [user.accountId]);
    assert.equal(rows[0].username, 'databaserule');
  });

  it('still lets a deleted account release the name it held', async () => {
    // The one exception, and the reason the rule is a trigger rather than a
    // revoked column privilege: deletion renames the row to a tombstone so the
    // name can be used again. A lock that broke deletion would be a worse bug
    // than the one it prevents.
    const user = await registerUser(h.app, 'leaving.soon');
    const deleted = await h.app.inject({
      method: 'DELETE',
      url: '/v1/accounts/me',
      headers: bearer(user),
      payload: { currentPassword: user.password },
    });
    assert.equal(deleted.statusCode, 200);

    const { rows } = await pool.query('SELECT username, deleted_at FROM accounts WHERE id = $1', [
      user.accountId,
    ]);
    assert.match(rows[0].username, /^deleted\./);
    assert.ok(rows[0].deleted_at);

    // And the name is free for somebody else.
    const free = await h.app.inject({ method: 'GET', url: '/v1/usernames/leaving.soon' });
    assert.equal(free.json().available, true);

    // A tombstone cannot be renamed again, so the exception is exactly one
    // transition wide rather than a permanent hole.
    await assert.rejects(
      () => pool.query('UPDATE accounts SET username = $2 WHERE id = $1', [user.accountId, 'back.again']),
      /username is permanent/,
    );
  });
});

describe('a display name is whatever somebody wants it to be', () => {
  const patch = (user: TestUser, payload: Record<string, unknown>) =>
    h.app.inject({ method: 'PATCH', url: '/v1/accounts/me', headers: bearer(user), payload });

  it('keeps spaces, accents and emoji, and survives a reload', async () => {
    const user = await registerUser(h.app, 'namechanger');
    const saved = await patch(user, { displayName: '  Jörg 🌲 Müller  ' });
    assert.equal(saved.statusCode, 200);
    assert.equal(saved.json().displayName, 'Jörg 🌲 Müller');

    const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
    assert.equal(me.json().displayName, 'Jörg 🌲 Müller');
  });

  it('can be cleared, and clearing is not the same as leaving it alone', async () => {
    const user = await registerUser(h.app, 'clearer');
    await patch(user, { displayName: 'Temporary' });

    // A key that is not sent changes nothing.
    const untouched = await patch(user, { privacy: { readReceipts: false } });
    assert.equal(untouched.json().displayName, 'Temporary');

    // An empty one clears it, and the account is its @username again.
    const cleared = await patch(user, { displayName: '   ' });
    assert.equal(cleared.json().displayName, null);
    assert.equal(cleared.json().username, 'clearer');

    // So does an explicit null.
    await patch(user, { displayName: 'Back again' });
    assert.equal((await patch(user, { displayName: null })).json().displayName, null);
  });

  it('refuses one longer than fifty visible characters, counted as a person counts', async () => {
    const user = await registerUser(h.app, 'longwinded');
    // Fifty family emoji are fifty characters to a reader and several hundred
    // to `String.length`. The limit is the first number.
    const fifty = '👨‍👩‍👧'.repeat(50);
    assert.equal(visibleLength(fifty), 50);
    assert.equal((await patch(user, { displayName: fifty })).statusCode, 200);
    assert.equal((await patch(user, { displayName: `${fifty}!` })).statusCode, 400);
  });

  it('drops the characters that are there to deceive rather than to be read', async () => {
    const user = await registerUser(h.app, 'invisible');
    // A right-to-left override can reverse the text drawn after it, including
    // the @username beside the name — so it goes, along with zero-width
    // padding that would otherwise buy a longer name than the limit allows.
    const saved = await patch(user, { displayName: 'Ada‮​\u0007 Lovelace' });
    assert.equal(saved.json().displayName, 'Ada Lovelace');

    // The joiners that make an emoji one glyph, and the marks that decide
    // whether a character is drawn as text or emoji, are kept: removing those
    // would misspell the name rather than clean it.
    assert.equal(cleanDisplayName('👩‍🚀'), '👩‍🚀');
    assert.equal(cleanDisplayName('❤️'), '❤️');
  });

  it('may be the same for two accounts, which stay entirely separate', async () => {
    const first = await registerUser(h.app, 'twin.one');
    const second = await registerUser(h.app, 'twin.two');
    await patch(first, { displayName: 'Alex Taylor' });
    await patch(second, { displayName: 'Alex Taylor' });

    const firstMe = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(first) });
    const secondMe = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(second) });
    assert.equal(firstMe.json().displayName, secondMe.json().displayName);
    assert.notEqual(firstMe.json().id, secondMe.json().id);
    assert.notEqual(firstMe.json().username, secondMe.json().username);

    // Looking one of them up by name gets that one, by id, and not the other.
    const looked = await h.app.inject({
      method: 'GET',
      url: '/v1/users/twin.two',
      headers: bearer(first),
    });
    assert.equal(looked.json().id, secondMe.json().id);
  });

  it('is nobody else’s to edit', async () => {
    const owner = await registerUser(h.app, 'owner.only');
    const stranger = await registerUser(h.app, 'stranger.here');
    await patch(owner, { displayName: 'Owner' });

    // There is no route that takes somebody else's id: the only name a PATCH
    // can reach is the one belonging to the token it was sent with.
    const attempt = await patch(stranger, { displayName: 'Impostor' });
    assert.equal(attempt.statusCode, 200);

    const ownerMe = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(owner) });
    assert.equal(ownerMe.json().displayName, 'Owner');
  });
});
