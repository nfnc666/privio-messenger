import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import * as official from '../src/services/official_channel.js';
import {
  adminBearer,
  bearer,
  closePool,
  createHarness,
  deviceBody,
  deviceFixture,
  registerAdmin,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * The official Privio channel.
 *
 * The four scenarios the brief names — automatic subscribe, permanent removal,
 * voluntary return, and a badge that cannot be taken by a look-alike — plus the
 * two that decide whether this is safe to ship: that designating a channel
 * touches nothing about it, and that an ordinary subscriber gains no rights.
 */
describe('the official channel', () => {
  let h: TestHarness;
  let owner: TestUser;
  let operator: Awaited<ReturnType<typeof registerAdmin>>;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'privio_team');
    operator = await registerAdmin(h.app, 'official_op', 'owner');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  beforeEach(async () => {
    await pool.query('DELETE FROM official_channel');
    await pool.query('DELETE FROM official_channel_offers');
    official.forgetCache();
  });

  /**
   * A public channel owned by `user`.
   *
   * Handles are unique per call because a handle is unique in the schema and
   * these tests share one database. That is convenient here and it is also the
   * point of the feature: the badge follows the **id**, so the tests below can
   * use whatever handle they like and still be about the right channel.
   */
  let nextHandle = 0;
  const uniqueHandle = (base: string) => `${base}_${nextHandle++}`;

  async function publicChannel(user: TestUser, handle: string, title: string) {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(user),
      payload: { visibility: 'public', handle, title, description: 'Official Privio news' },
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; handle: string; verified: boolean };
  }

  /** Designates by id, the way an operator does. */
  const designate = (channelId: string, handle: string, ownerName: string) =>
    h.app.inject({
      method: 'PUT',
      url: '/v1/admin/official-channel',
      headers: adminBearer(operator),
      payload: { channelId, expectedHandle: handle, expectedOwner: ownerName },
    });

  /** Signs in as an existing account, which is where the one-time join runs. */
  const signIn = (user: TestUser) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: user.username,
        password: user.password,
        device: deviceBody(deviceFixture()),
      },
    });

  const myChannels = async (user: TestUser) => {
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/channels',
      headers: bearer(user),
    });
    assert.equal(response.statusCode, 200, response.body);
    return (response.json().channels as { id: string; verified?: boolean }[]);
  };

  describe('designating it', () => {
    it('finds candidates by handle but designates by id', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');

      const found = await h.app.inject({
        method: 'GET',
        url: `/v1/admin/official-channel/candidates?handle=${channel.handle}`,
        headers: adminBearer(operator),
      });
      assert.equal(found.statusCode, 200, found.body);
      const candidates = found.json().candidates as { id: string; owner: { username: string } }[];

      // The route hands back the owner so a human can confirm it. It does not
      // choose; the operator does, by id.
      assert.equal(candidates[0]!.id, channel.id);
      assert.equal(candidates[0]!.owner.username, 'privio_team');

      const set = await designate(channel.id, channel.handle, 'privio_team');
      assert.equal(set.statusCode, 200, set.body);
      assert.equal(set.json().official.channelId, channel.id);
    });

    it('refuses when the owner is not who the operator expected', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');

      // The handle is right, so the *owner* check is the one under test.
      const wrong = await designate(channel.id, channel.handle, 'somebody_else');
      assert.equal(wrong.statusCode, 400);
      assert.equal(wrong.json().error, 'owner_mismatch');

      // And nothing was designated.
      const none = await h.app.inject({
        method: 'GET',
        url: '/v1/admin/official-channel',
        headers: adminBearer(operator),
      });
      assert.equal(none.json().official, null);
    });

    it('refuses when the handle is not the one the operator expected', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      const wrong = await designate(channel.id, 'some_other_handle', 'privio_team');
      assert.equal(wrong.statusCode, 400);
      assert.equal(wrong.json().error, 'handle_mismatch');
    });

    it('changes nothing about the channel itself', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      const before = await pool.query('SELECT * FROM channels WHERE id = $1', [channel.id]);
      const membersBefore = await pool.query(
        'SELECT * FROM channel_members WHERE channel_id = $1 ORDER BY account_id',
        [channel.id],
      );

      await designate(channel.id, channel.handle, 'privio_team');

      const after = await pool.query('SELECT * FROM channels WHERE id = $1', [channel.id]);
      const membersAfter = await pool.query(
        'SELECT * FROM channel_members WHERE channel_id = $1 ORDER BY account_id',
        [channel.id],
      );
      // Picture, description, title, posts, memberships: untouched. The
      // designation is one row in a different table.
      assert.deepEqual(after.rows[0], before.rows[0]);
      assert.deepEqual(membersAfter.rows, membersBefore.rows);
    });

    it('needs the operators capability, not merely an operator session', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      const support = await registerAdmin(h.app, 'official_support', 'support');

      const refused = await h.app.inject({
        method: 'PUT',
        url: '/v1/admin/official-channel',
        headers: adminBearer(support),
        payload: {
          channelId: channel.id,
          expectedHandle: channel.handle,
          expectedOwner: 'privio_team',
        },
      });
      assert.equal(refused.statusCode, 403);
    });
  });

  describe('the badge', () => {
    it('is on the designated channel', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');

      const read = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
      });
      assert.equal(read.json().verified, true);
    });

    it('is not on a channel with the same name', async () => {
      // The whole reason the designation is a uuid. An impostor registers a
      // handle one character away and titles it identically.
      const real = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(real.id, real.handle, 'privio_team');

      const impostor = await registerUser(h.app, 'not_privio');
      const fake = await publicChannel(impostor, uniqueHandle('privio_officia1'), 'Privio Official');

      const read = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${fake.id}`,
        headers: bearer(impostor),
      });
      assert.equal(read.json().verified, false, 'a name must never earn the badge');
    });

    it('cannot be claimed by asking for it', async () => {
      const impostor = await registerUser(h.app, 'chancer');
      const response = await h.app.inject({
        method: 'POST',
        url: '/v1/channels',
        headers: bearer(impostor),
        payload: {
          visibility: 'public',
          handle: uniqueHandle('privio_official'),
          title: 'Privio Official',
          verified: true,
          official: true,
        },
      });
      assert.equal(response.statusCode, 201, response.body);
      assert.equal(response.json().verified, false);
    });

    it('moves when the designation moves, and leaves the old one plain', async () => {
      const first = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      const second = await publicChannel(owner, uniqueHandle('privio_news'), 'Privio News');
      await designate(first.id, first.handle, 'privio_team');
      await designate(second.id, second.handle, 'privio_team');

      const oldOne = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${first.id}`,
        headers: bearer(owner),
      });
      assert.equal(oldOne.json().verified, false);
    });

    it('is off everywhere when nothing is designated', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      const read = await h.app.inject({
        method: 'GET',
        url: `/v1/channels/${channel.id}`,
        headers: bearer(owner),
      });
      assert.equal(read.json().verified, false);
    });
  });

  describe('subscribing everybody, once', () => {
    it('a new account is subscribed when it registers', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');

      const newcomer = await registerUser(h.app, 'newcomer_one');
      const channels = await myChannels(newcomer);

      assert.ok(channels.some((c) => c.id === channel.id), 'it should be in their list');
      assert.equal(channels.find((c) => c.id === channel.id)!.verified, true);
    });

    it('an account that existed first is subscribed on its next sign-in', async () => {
      // The case that matters for a live product: everybody already has an
      // account, and this has to reach them without a migration touching
      // their rows.
      const existing = await registerUser(h.app, 'was_here_already');
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');

      assert.equal((await myChannels(existing)).some((c) => c.id === channel.id), false);

      const session = await signIn(existing);
      assert.equal(session.statusCode, 200, session.body);
      const after = { ...existing, token: session.json().token as string };

      assert.ok((await myChannels(after)).some((c) => c.id === channel.id));
    });

    it('subscribes as a plain subscriber, with no rights', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const newcomer = await registerUser(h.app, 'newcomer_two');

      const { rows } = await pool.query(
        'SELECT * FROM channel_members WHERE channel_id = $1 AND account_id = $2',
        [channel.id, newcomer.accountId],
      );
      assert.equal(rows[0]!.role, 'subscriber');
      assert.equal(rows[0]!.can_post, false);
      assert.equal(rows[0]!.can_manage_members, false);
      assert.equal(rows[0]!.can_delete_channel, false);
    });

    it('does not disturb the channel s own owner', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const before = await pool.query(
        'SELECT * FROM channel_members WHERE channel_id = $1 AND account_id = $2',
        [channel.id, owner.accountId],
      );
      assert.equal(before.rows[0]!.role, 'owner');

      // The owner signs in again, which is where the one-time join runs.
      const session = await signIn(owner);
      assert.equal(session.statusCode, 200);

      const after = await pool.query(
        'SELECT * FROM channel_members WHERE channel_id = $1 AND account_id = $2',
        [channel.id, owner.accountId],
      );
      assert.equal(after.rows[0]!.role, 'owner', 'an auto-subscribe must not demote the owner');
      assert.deepEqual(after.rows[0], before.rows[0]);
    });

    it('counts the member exactly once', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const newcomer = await registerUser(h.app, 'newcomer_three');

      const { rows: first } = await pool.query('SELECT member_count FROM channels WHERE id = $1', [
        channel.id,
      ]);
      // Three sign-ins later, still the same count.
      for (let i = 0; i < 3; i++) await signIn(newcomer);
      const { rows: later } = await pool.query('SELECT member_count FROM channels WHERE id = $1', [
        channel.id,
      ]);
      assert.equal(later[0]!.member_count, first[0]!.member_count);
    });
  });

  describe('leaving it, and meaning it', () => {
    it('stays gone across a sign-in', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const person = await registerUser(h.app, 'wants_out');
      assert.ok((await myChannels(person)).some((c) => c.id === channel.id));

      const left = await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/members/me`,
        headers: bearer(person),
      });
      assert.equal(left.statusCode, 200, left.body);

      // The thing this whole table exists for.
      const session = await signIn(person);
      const after = { ...person, token: session.json().token as string };
      assert.equal(
        (await myChannels(after)).some((c) => c.id === channel.id),
        false,
        'a channel somebody removed must not come back',
      );
    });

    it('records that it was deliberate', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const person = await registerUser(h.app, 'wants_out_two');
      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/members/me`,
        headers: bearer(person),
      });

      const { rows } = await pool.query(
        'SELECT * FROM official_channel_offers WHERE account_id = $1',
        [person.accountId],
      );
      assert.equal(rows.length, 1);
      assert.notEqual(rows[0]!.opted_out_at, null);
    });

    it('can be joined again on purpose, and stays joined', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const person = await registerUser(h.app, 'changed_their_mind');

      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/members/me`,
        headers: bearer(person),
      });
      const rejoined = await h.app.inject({
        method: 'POST',
        url: `/v1/channels/${channel.id}/join`,
        headers: bearer(person),
        payload: {},
      });
      assert.equal(rejoined.statusCode, 200, rejoined.body);
      assert.ok((await myChannels(person)).some((c) => c.id === channel.id));

      const { rows } = await pool.query(
        'SELECT opted_out_at FROM official_channel_offers WHERE account_id = $1',
        [person.accountId],
      );
      assert.equal(rows[0]!.opted_out_at, null, 'the record should match what is true');
    });

    it('leaving a second time is still permanent', async () => {
      const channel = await publicChannel(owner, uniqueHandle('privio_official'), 'Privio Official');
      await designate(channel.id, channel.handle, 'privio_team');
      const person = await registerUser(h.app, 'out_again');

      for (let i = 0; i < 2; i++) {
        await h.app.inject({
          method: 'DELETE',
          url: `/v1/channels/${channel.id}/members/me`,
          headers: bearer(person),
        });
        await h.app.inject({
          method: 'POST',
          url: `/v1/channels/${channel.id}/join`,
          headers: bearer(person),
          payload: {},
        });
      }
      await h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channel.id}/members/me`,
        headers: bearer(person),
      });

      const session = await signIn(person);
      const after = { ...person, token: session.json().token as string };
      assert.equal((await myChannels(after)).some((c) => c.id === channel.id), false);
    });
  });
});
