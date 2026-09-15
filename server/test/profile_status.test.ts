import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { runRetentionSweep } from '../src/services/cleanup.js';
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
 * The profile status, from the server's side.
 *
 * What is under test is mostly *absence*: that an expired status is gone, that
 * a status the viewer may not see is not merely hidden in the client, and that
 * there is no request shape at all that writes somebody else's line.
 */
describe('profile status', () => {
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

  const setStatus = (user: TestUser, payload: Record<string, unknown>) =>
    h.app.inject({ method: 'PUT', url: '/v1/accounts/me/status', headers: bearer(user), payload });

  const me = async (user: TestUser) =>
    (await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) })).json();

  const lookUp = async (viewer: TestUser, username: string) =>
    (await h.app.inject({ method: 'GET', url: `/v1/users/${username}`, headers: bearer(viewer) })).json();

  it('starts with no status at all', async () => {
    const profile = await me(alice);
    assert.deepEqual(profile.status, { text: null, emoji: null, expiresAt: null, updatedAt: null });
  });

  it('sets, changes and removes', async () => {
    const set = await setStatus(alice, { text: 'Writing tests', emoji: '💻' });
    assert.equal(set.statusCode, 200);
    assert.equal(set.json().status.text, 'Writing tests');
    assert.equal(set.json().status.emoji, '💻');
    assert.equal((await me(alice)).status.text, 'Writing tests');

    const changed = await setStatus(alice, { text: 'On a break', emoji: '☕' });
    assert.equal(changed.json().status.text, 'On a break');
    assert.equal((await me(alice)).status.emoji, '☕');

    const removed = await h.app.inject({
      method: 'DELETE',
      url: '/v1/accounts/me/status',
      headers: bearer(alice),
    });
    assert.equal(removed.statusCode, 200);
    assert.equal(removed.json().status.text, null);
    assert.equal((await me(alice)).status.text, null);
  });

  it('treats an empty save as a removal', async () => {
    await setStatus(alice, { text: 'Here' });
    const cleared = await setStatus(alice, { text: '   ', emoji: null });
    assert.equal(cleared.json().status.text, null);
    assert.equal((await me(alice)).status.text, null);
  });

  it('keeps an emoji-only status', async () => {
    await setStatus(alice, { text: null, emoji: '🎉' });
    const profile = await me(alice);
    assert.equal(profile.status.emoji, '🎉');
    assert.equal(profile.status.text, null);
    await h.app.inject({ method: 'DELETE', url: '/v1/accounts/me/status', headers: bearer(alice) });
  });

  it('survives a new session — it is on the account, not the login', async () => {
    await setStatus(alice, { text: 'Still here' });
    const again = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: alice.username,
        password: alice.password,
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(again.statusCode, 200);
    const second = again.json() as TestUser;
    const profile = await me({ ...alice, token: second.token });
    assert.equal(profile.status.text, 'Still here');
    await h.app.inject({ method: 'DELETE', url: '/v1/accounts/me/status', headers: bearer(alice) });
  });

  describe('expiry', () => {
    // Started from nothing rather than from whatever ran last. A test that
    // depends on its predecessor's cleanup reports that predecessor's failures
    // as its own — which is exactly what the first draft of this file did.
    before(async () => {
      await h.app.inject({ method: 'DELETE', url: '/v1/accounts/me/status', headers: bearer(alice) });
    });

    it('refuses a moment that has already passed', async () => {
      const past = new Date(Date.now() - 60_000).toISOString();
      const refused = await setStatus(alice, { text: 'Too late', expiresAt: past });
      assert.equal(refused.statusCode, 400);
      assert.equal(refused.json().error, 'expiry_in_past');
      // And nothing was written on the way to refusing.
      assert.equal((await me(alice)).status.text, null);
    });

    it('stops showing the moment it is due, with no sweep involved', async () => {
      const soon = new Date(Date.now() + 60_000).toISOString();
      await setStatus(alice, { text: 'Back at five', expiresAt: soon });
      assert.equal((await me(alice)).status.text, 'Back at five');

      // Move the deadline into the past directly, which is what the clock does
      // on its own a minute later. No sweeper has run.
      await pool.query(
        `UPDATE accounts SET status_expires_at = now() - interval '1 second' WHERE id = $1`,
        [alice.accountId],
      );

      // Gone for the owner and gone for a viewer — and the row is still there,
      // which is the point: correctness is on the read path.
      assert.equal((await me(alice)).status.text, null);
      assert.equal((await lookUp(bob, 'alice')).status.text, null);
      const { rows } = await pool.query<{ status_text: string | null }>(
        'SELECT status_text FROM accounts WHERE id = $1',
        [alice.accountId],
      );
      assert.equal(rows[0]!.status_text, 'Back at five');
    });

    it('never comes back once expired, and the sweep clears the text', async () => {
      await runRetentionSweep(h.storage);
      const { rows } = await pool.query<{ status_text: string | null }>(
        'SELECT status_text FROM accounts WHERE id = $1',
        [alice.accountId],
      );
      assert.equal(rows[0]!.status_text, null);
      assert.equal((await me(alice)).status.text, null);
    });
  });

  describe('visibility', () => {
    before(async () => {
      await setStatus(alice, { text: 'Only for some', emoji: '🤫' });
      await pool.query(`UPDATE accounts SET privacy = '{}'::jsonb WHERE id = $1`, [alice.accountId]);
    });

    const setPrivacy = (user: TestUser, privacy: Record<string, unknown>) =>
      h.app.inject({
        method: 'PATCH',
        url: '/v1/accounts/me',
        headers: bearer(user),
        payload: { privacy },
      });

    it('is visible to anyone by default', async () => {
      assert.equal((await lookUp(bob, 'alice')).status.text, 'Only for some');
    });

    it('is withheld from a non-contact when set to contacts', async () => {
      await setPrivacy(alice, { profileStatus: 'contacts' });
      // Alice does not have Bob in her address book, so Bob is not a contact
      // *of hers* — which is the direction that decides this.
      assert.equal((await lookUp(bob, 'alice')).status.text, null);

      await h.app.inject({
        method: 'POST',
        url: '/v1/contacts',
        headers: bearer(alice),
        payload: { username: 'bob' },
      });
      assert.equal((await lookUp(bob, 'alice')).status.text, 'Only for some');
    });

    it('is withheld from everyone when set to nobody', async () => {
      await setPrivacy(alice, { profileStatus: 'nobody' });
      assert.equal((await lookUp(bob, 'alice')).status.text, null);
      // Still her own, on her own screen.
      assert.equal((await me(alice)).status.text, 'Only for some');
    });

    it('does not ride on the last-seen setting', async () => {
      // The one that must not happen: hiding when you were online should not
      // take away the line you wrote, and vice versa.
      await setPrivacy(alice, { lastSeen: 'nobody', profileStatus: 'everyone' });
      const seen = await lookUp(bob, 'alice');
      assert.equal(seen.lastSeenAt, null);
      assert.equal(seen.status.text, 'Only for some');

      await setPrivacy(alice, { lastSeen: 'everyone', profileStatus: 'nobody' });
      const other = await lookUp(bob, 'alice');
      assert.ok(other.lastSeenAt !== null);
      assert.equal(other.status.text, null);
    });

    it('applies the same rule in the contacts list', async () => {
      await setPrivacy(alice, { profileStatus: 'nobody' });
      // Bob adds Alice, so she is in *his* list; her setting still decides.
      await h.app.inject({
        method: 'POST',
        url: '/v1/contacts',
        headers: bearer(bob),
        payload: { username: 'alice' },
      });
      const list = await h.app.inject({ method: 'GET', url: '/v1/contacts', headers: bearer(bob) });
      const row = (list.json().contacts as { username: string; status: { text: string | null } }[])
        .find((c) => c.username === 'alice');
      assert.ok(row, 'alice should be in the list');
      assert.equal(row.status.text, null);

      await setPrivacy(alice, { profileStatus: 'everyone' });
      const again = await h.app.inject({ method: 'GET', url: '/v1/contacts', headers: bearer(bob) });
      const updated = (again.json().contacts as { username: string; status: { text: string | null } }[])
        .find((c) => c.username === 'alice');
      assert.equal(updated!.status.text, 'Only for some');
    });
  });

  describe('a status belongs to one account', () => {
    it('has no request shape that writes somebody else’s', async () => {
      await setStatus(bob, { text: "Bob's own" });

      // Every way an account id could be smuggled in. The endpoint takes the
      // account from the session, so each of these either writes Bob's own or
      // is refused — and in no case does Alice's change.
      const before = (await me(alice)).status.text;
      for (const payload of [
        { text: 'hijacked', accountId: alice.accountId },
        { text: 'hijacked', id: alice.accountId },
        { text: 'hijacked', userId: alice.accountId },
        { text: 'hijacked', username: alice.username },
      ]) {
        await setStatus(bob, payload);
        assert.equal((await me(alice)).status.text, before, `payload ${JSON.stringify(payload)}`);
      }

      // There is no per-account path to aim at either.
      const byPath = await h.app.inject({
        method: 'PUT',
        url: `/v1/accounts/${alice.accountId}/status`,
        headers: bearer(bob),
        payload: { text: 'hijacked' },
      });
      assert.equal(byPath.statusCode, 404);
    });

    it('refuses an unauthenticated write', async () => {
      const anonymous = await h.app.inject({
        method: 'PUT',
        url: '/v1/accounts/me/status',
        payload: { text: 'nobody' },
      });
      assert.equal(anonymous.statusCode, 401);
    });
  });

  it('bounds what can be stored', async () => {
    const tooLong = await setStatus(alice, { text: 'x'.repeat(141) });
    assert.equal(tooLong.statusCode, 400);
    const tooManyEmoji = await setStatus(alice, { text: 'ok', emoji: '😀😀😀😀😀' });
    assert.equal(tooManyEmoji.statusCode, 400);
  });
});
