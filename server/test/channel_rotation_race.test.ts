import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import {
  bearer,
  closePool,
  createHarness,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * The race between publishing a post and rotating the channel's key.
 *
 * Two database connections, and an interleaving forced rather than hoped for.
 * Before the fix in this branch the publish route ran three separate
 * statements on the pool — permission, `SELECT key_epoch`, `INSERT` — and a
 * removal committing in the gap between the second and third left a post
 * stored under the superseded epoch: readable by the person who had just been
 * removed, which is the one thing the whole rotation design exists to prevent.
 *
 * Timing tests that race two requests and hope are worthless; they pass on a
 * fast machine and fail in February. So the interleaving here is made
 * deterministic with a lock held from a second connection: the removal's own
 * `FOR UPDATE` on the channel row is taken by hand, the publish is started and
 * demonstrably blocked, and only then is the rotation completed and released.
 *
 * Run against the code before the fix, the first test here returns **201**:
 * the post is accepted and stored at the epoch the channel has just left.
 *
 * One detail from doing that is worth keeping, because it is the reason "put it
 * in a transaction" would not have been enough on its own. The old code *did*
 * block — the INSERT's foreign key to `channels` takes a `FOR KEY SHARE` lock
 * on the referenced row, which conflicts with the remover's `FOR UPDATE`. So it
 * waited, looking for all the world like it was properly serialised, and then
 * inserted the epoch it had read several statements earlier and never
 * rechecked. The lock has to be taken *before* the read it protects, not
 * incidentally afterwards by something else.
 */
describe('publishing while somebody is being removed', () => {
  let h: TestHarness;
  let owner: TestUser;
  let doomed: TestUser;
  let channelId: string;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'race_owner');
    doomed = await registerUser(h.app, 'race_doomed');

    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(owner),
      payload: { visibility: 'public', handle: 'race', title: 'Race' },
    });
    channelId = created.json().id;
    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/join`,
      headers: bearer(doomed),
    });
  });

  after(async () => {
    await h.close();
    await closePool();
  });

  const publish = (epoch: number) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/posts`,
      headers: bearer(owner),
      payload: { content: Buffer.from('sealed').toString('base64'), keyEpoch: epoch },
    });

  const epochNow = async () => {
    const { rows } = await pool.query<{ key_epoch: number }>(
      'SELECT key_epoch FROM channels WHERE id = $1',
      [channelId],
    );
    return rows[0]!.key_epoch;
  };

  /** How many connections are waiting on a lock right now. */
  const blockedQueries = async () => {
    const { rows } = await pool.query<{ count: string }>(
      `SELECT count(*) FROM pg_stat_activity
       WHERE datname = current_database() AND wait_event_type = 'Lock'`,
    );
    return Number(rows[0]!.count);
  };

  it('a post cannot be stored under an epoch a rotation has already left', async () => {
    const before = await epochNow();

    // A second connection, standing in for the removal request that is halfway
    // through its transaction.
    const remover = await pool.connect();
    try {
      await remover.query('BEGIN');
      await remover.query('SELECT key_epoch FROM channels WHERE id = $1 FOR UPDATE', [channelId]);

      // The publish starts now, with the rotation in flight. It must not be
      // able to read the epoch and get as far as an INSERT.
      const inFlight = publish(before);

      // Wait for it to actually be blocked, rather than assuming it is. If the
      // route were still reading on the pool without a lock this would never
      // become true, and the test would fail here rather than by luck.
      let blocked = 0;
      for (let attempt = 0; attempt < 100 && blocked === 0; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 20));
        blocked = await blockedQueries();
      }
      assert.ok(blocked > 0, 'the publish must wait for the rotation, not read around it');

      // The removal completes: membership gone, epoch advanced.
      await remover.query('DELETE FROM channel_members WHERE channel_id = $1 AND account_id = $2', [
        channelId,
        doomed.accountId,
      ]);
      await remover.query('UPDATE channels SET key_epoch = key_epoch + 1 WHERE id = $1', [
        channelId,
      ]);
      await remover.query('COMMIT');

      const response = await inFlight;

      assert.equal(
        response.statusCode,
        409,
        `a post sealed under epoch ${before} must be refused once the channel has moved on`,
      );
      assert.equal(response.json().error, 'stale_key_epoch');
    } finally {
      await remover.query('ROLLBACK').catch(() => {});
      remover.release();
    }

    // And nothing was written under the old epoch on the way past.
    const now = await epochNow();
    const { rows } = await pool.query<{ key_epoch: number }>(
      'SELECT key_epoch FROM channel_posts WHERE channel_id = $1',
      [channelId],
    );
    assert.equal(
      rows.some((r) => r.key_epoch < now),
      false,
      'no post may sit at an epoch the channel has already left',
    );
  });

  it('a post that gets in before the rotation is kept, at the epoch it used', async () => {
    // The other half, and the reason the lock is FOR SHARE rather than
    // FOR UPDATE: publishing must not be serialised against itself, and a post
    // that legitimately beat the rotation is not lost by it.
    const epoch = await epochNow();
    const both = await Promise.all([publish(epoch), publish(epoch)]);

    for (const response of both) {
      assert.equal(response.statusCode, 201, response.body);
      assert.equal(response.json().keyEpoch, epoch);
    }
  });

  it('removing the same member twice does not spend two epochs', async () => {
    // Two admins clicking at once. Without the re-check inside the lock both
    // would advance the epoch, and the channel would sit on a version nobody
    // has a key for — unwritable until somebody generates one.
    const victim = await registerUser(h.app, 'race_twice');
    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channelId}/join`,
      headers: bearer(victim),
    });

    const before = await epochNow();
    const remove = () =>
      h.app.inject({
        method: 'DELETE',
        url: `/v1/channels/${channelId}/members/${victim.accountId}`,
        headers: bearer(owner),
      });

    const [first, second] = await Promise.all([remove(), remove()]);

    const codes = [first.statusCode, second.statusCode].sort();
    assert.deepEqual(codes, [200, 404], 'one removal happens; the other finds nobody to remove');
    assert.equal(await epochNow(), before + 1, 'and exactly one epoch is spent');
  });
});
