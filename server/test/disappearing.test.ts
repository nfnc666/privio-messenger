import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { runRetentionSweep } from '../src/services/cleanup.js';
import { LocalFileStorage } from '../src/services/storage.js';
import { MAX_DISAPPEAR_SECONDS } from '../src/util/validate.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * The ceiling, and who may move it.
 *
 * The app offers a list of timers that stops at twenty-four hours. That list
 * is a convenience; this is the rule. Everything here is written against the
 * API rather than against the screen, because a promise that a message goes
 * away has to survive a caller that never opened the app.
 */
// One harness for the file: `createHarness` truncates, and the pool is shared,
// so a per-describe close pulls it out from under the next block.
let h: TestHarness;
let alice: TestUser;
let bob: TestUser;
let admin: TestUser;
let member: TestUser;
let groupId: string;

before(async () => {
  h = await createHarness();
  alice = await registerUser(h.app, 'timer.alice');
  bob = await registerUser(h.app, 'timer.bob');
  admin = await registerUser(h.app, 'group.admin');
  member = await registerUser(h.app, 'group.member');

  const created = await h.app.inject({
    method: 'POST',
    url: '/v1/groups',
    headers: bearer(admin),
    payload: {
      encryptedMetadata: Buffer.from('sealed-name').toString('base64'),
      memberIds: [member.accountId],
    },
  });
  if (created.statusCode !== 201) throw new Error(`group create failed: ${created.body}`);
  groupId = created.json().id;
});
after(async () => {
  await h?.close();
  await closePool();
});

describe('a timer is at most a day', () => {

  const send = (expiresInSeconds?: number) =>
    h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(alice),
      payload: {
        username: 'timer.bob',
        ...(expiresInSeconds === undefined ? {} : { expiresInSeconds }),
        messages: [
          {
            deviceId: bob.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.from('sealed').toString('base64'),
          },
        ],
      },
    });

  it('accepts a day and refuses a second more', async () => {
    assert.equal(MAX_DISAPPEAR_SECONDS, 86_400);
    assert.equal((await send(MAX_DISAPPEAR_SECONDS)).statusCode, 202);

    // Refused rather than quietly reduced. A caller that believed it set a
    // week and got a day would be told nothing, and the difference between
    // those two is the entire promise.
    const tooLong = await send(MAX_DISAPPEAR_SECONDS + 1);
    assert.equal(tooLong.statusCode, 400);

    const week = await send(60 * 60 * 24 * 7);
    assert.equal(week.statusCode, 400, 'a week used to be allowed and must not be');
  });

  it('writes the expiry the sender asked for onto the stored envelope', async () => {
    await send(30);
    const { rows } = await pool.query<{ expires_at: Date | null; created_at: Date }>(
      `SELECT expires_at, created_at FROM envelopes
       WHERE recipient_device_id = $1 ORDER BY id DESC LIMIT 1`,
      [bob.deviceId],
    );
    const seconds = (rows[0]!.expires_at!.getTime() - rows[0]!.created_at.getTime()) / 1000;
    assert.ok(Math.abs(seconds - 30) < 5, `expected about 30s, got ${seconds}`);
  });

  it('sweeps an envelope whose time is up, undelivered', async () => {
    // The point of the server half: a device that never comes back must not
    // leave a thirty-second message sitting here as ciphertext for a month.
    await send(30);
    const { rows } = await pool.query<{ id: string }>(
      'SELECT id FROM envelopes WHERE recipient_device_id = $1 ORDER BY id DESC LIMIT 1',
      [bob.deviceId],
    );
    const id = rows[0]!.id;
    await pool.query("UPDATE envelopes SET expires_at = now() - interval '1 second' WHERE id = $1", [id]);

    await runRetentionSweep(new LocalFileStorage('/tmp/privio-sweep-test'));

    const { rowCount } = await pool.query('SELECT 1 FROM envelopes WHERE id = $1', [id]);
    assert.equal(rowCount, 0, 'an expired envelope survived the sweep');
  });

  it('bounds the account-wide default too', async () => {
    const ok = await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(alice),
      payload: { privacy: { disappearAfterSeconds: MAX_DISAPPEAR_SECONDS } },
    });
    assert.equal(ok.statusCode, 200);
    assert.equal(ok.json().privacy.disappearAfterSeconds, MAX_DISAPPEAR_SECONDS);

    const tooLong = await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(alice),
      payload: { privacy: { disappearAfterSeconds: MAX_DISAPPEAR_SECONDS + 1 } },
    });
    assert.equal(tooLong.statusCode, 400, 'the default was the way round the ceiling');

    // Off is a value, and it survives a reload like any other setting.
    const off = await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(alice),
      payload: { privacy: { disappearAfterSeconds: null } },
    });
    assert.equal(off.statusCode, 200);
    const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(alice) });
    assert.equal(me.json().privacy.disappearAfterSeconds, null);
  });
});

describe("a group's timer is the group's to set", () => {
  const announce = (from: TestUser, to: TestUser, type: string) =>
    h.app.inject({
      method: 'POST',
      url: `/v1/messages/group/${groupId}`,
      headers: bearer(from),
      payload: {
        messages: [
          {
            deviceId: to.deviceId,
            registrationId: 4242,
            type,
            content: Buffer.from('sealed-timer-change').toString('base64'),
          },
        ],
      },
    });

  it('lets an admin announce a change and refuses a member', async () => {
    assert.equal((await announce(admin, member, 'group_update')).statusCode, 202);

    // The app greys the menu out for a member. This is what happens when
    // somebody skips the app: the server knows the role and the content stays
    // sealed, so the rule is enforced without the server reading anything.
    const refused = await announce(member, admin, 'group_update');
    assert.equal(refused.statusCode, 403);
    assert.equal(refused.json().error, 'not_an_admin');
  });

  it('still lets a member send ordinary messages', async () => {
    // The check is about announcements, not about speaking: a member losing
    // the ability to write would be a far worse bug than the one this fixes.
    assert.equal((await announce(member, admin, 'ciphertext')).statusCode, 202);
  });
});
