import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
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
 * What the server keeps about *how* people use Privio, beyond what they send.
 *
 * Each case here closes a line in `docs/metadata-privacy-review.md`: the client
 * address in the request log, the user agent of every sign-in, activity
 * recorded to the millisecond, and a session that stayed valid for a year
 * whether or not anybody still used it.
 */

/** Addresses from the documentation ranges, so they cannot be anyone's. */
const FORWARDED = '203.0.113.47';
const DIRECT = '198.51.100.23';
const AGENT = 'PrivioNews/9.9 (TestPhone 1; TestOS 42)';

const HOUR = "date_trunc('hour', now(), 'UTC')";

/** True in SQL when [column] is on the hour and within the last one. */
const onTheHour = (column: string) =>
  `(${column} = date_trunc('hour', ${column}, 'UTC') AND ${column} > now() - interval '1 hour')`;

/**
 * Keeps a test that compares against "this hour" off the turn of the hour,
 * where the hour it set up and the hour the server sees could differ.
 */
async function awayFromTheTurnOfTheHour(): Promise<void> {
  const { rows } = await pool.query<{ remaining: number }>(
    `SELECT extract(epoch FROM ${HOUR} + interval '1 hour' - now())::float AS remaining`,
  );
  const left = rows[0]!.remaining;
  if (left < 5) await new Promise((resolve) => setTimeout(resolve, left * 1000 + 200));
}

/** Waits for the bookkeeping `resolveSession` does after answering. */
async function eventually(check: () => Promise<boolean>, what: string): Promise<void> {
  for (let i = 0; i < 100; i++) {
    if (await check()) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.fail(`never happened: ${what}`);
}

describe('metadata the server keeps', () => {
  let h: TestHarness;
  const log: string[] = [];

  before(async () => {
    h = await createHarness({ logStream: { write: (line) => void log.push(line) } });
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('writes no client address and no user agent into the log', async () => {
    log.length = 0;
    const from = { 'x-forwarded-for': FORWARDED, 'user-agent': AGENT };
    const signUp = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      remoteAddress: DIRECT,
      headers: from,
      payload: { username: 'logreader', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(signUp.statusCode, 201);
    const token = (signUp.json() as { token: string }).token;
    // Looking somebody up is the request whose origin matters most, and the
    // ones that fail are logged too.
    for (const request of [
      { url: '/v1/keys/logreader', headers: { ...from, authorization: `Bearer ${token}` } },
      { url: '/v1/accounts/me', headers: { ...from, authorization: 'Bearer not-a-session' } },
      { url: '/v1/nowhere', headers: from },
    ]) {
      await h.app.inject({ method: 'GET', remoteAddress: DIRECT, ...request });
    }

    assert.ok(
      log.some((line) => line.includes('/v1/keys/logreader')),
      'the requests were logged — otherwise this proves nothing (is LOG_LEVEL above info?)',
    );
    for (const line of log) {
      assert.ok(!line.includes(FORWARDED), `the forwarded address is in the log: ${line}`);
      assert.ok(!line.includes(DIRECT), `the connecting address is in the log: ${line}`);
      assert.ok(!line.includes('TestPhone'), `the user agent is in the log: ${line}`);
    }
  });

  it('keeps nothing of the client with a session', async () => {
    const signIn = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      headers: { 'user-agent': AGENT, 'x-forwarded-for': FORWARDED },
      payload: {
        username: 'logreader',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(signIn.statusCode, 200);
    const { rows } = await pool.query<{ row: string }>(
      `SELECT row_to_json(s)::text AS row FROM sessions s
         JOIN accounts a ON a.id = s.account_id WHERE a.username = 'logreader'`,
    );
    assert.equal(rows.length, 2);
    for (const { row } of rows) {
      assert.ok(!row.includes('TestPhone'), `a session keeps the user agent: ${row}`);
      assert.ok(!row.includes(FORWARDED), `a session keeps the address: ${row}`);
    }
  });

  describe('activity, to the hour', () => {
    let user: TestUser;

    before(async () => {
      user = await registerUser(h.app, 'hourly');
    });

    it('starts out to the hour', async () => {
      const { rows } = await pool.query<{ exact: boolean }>(
        `SELECT ${onTheHour('a.last_seen_at')} AND ${onTheHour('d.last_seen_at')}
            AND ${onTheHour('s.last_used_at')}
            AND s.expires_at = s.last_used_at + make_interval(days => $2) AS exact
           FROM accounts a
           JOIN devices d ON d.account_id = a.id
           JOIN sessions s ON s.device_id = d.id
          WHERE a.id = $1`,
        [user.accountId, config.SESSION_TTL_DAYS],
      );
      assert.equal(rows[0]?.exact, true, 'a new account, device and session hold the hour, not the moment');
    });

    it('records use to the hour, and moves the end of the session out', async () => {
      await awayFromTheTurnOfTheHour();
      // As the rows of somebody last here three days ago, at 10:17:42.5, on a
      // session that would end tomorrow.
      await pool.query(
        `UPDATE accounts SET last_seen_at = ${HOUR} - interval '3 days' + interval '17 min 42.5 s'
          WHERE id = $1`,
        [user.accountId],
      );
      await pool.query(
        `UPDATE devices SET last_seen_at = ${HOUR} - interval '3 days' + interval '17 min 42.5 s'
          WHERE id = $1`,
        [user.deviceId],
      );
      await pool.query(
        `UPDATE sessions SET last_used_at = ${HOUR} - interval '3 days',
                             expires_at = now() + interval '1 day'
          WHERE device_id = $1`,
        [user.deviceId],
      );

      const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
      assert.equal(me.statusCode, 200);

      // The account is written last of the three, so once it has moved the
      // others have too.
      await eventually(async () => {
        const { rows } = await pool.query<{ moved: boolean }>(
          `SELECT last_seen_at > now() - interval '1 day' AS moved FROM accounts WHERE id = $1`,
          [user.accountId],
        );
        return rows[0]?.moved === true;
      }, 'the account was marked as seen');

      const { rows } = await pool.query<{
        account: boolean;
        device: boolean;
        used: boolean;
        ends: boolean;
      }>(
        `SELECT ${onTheHour('a.last_seen_at')} AS account,
                ${onTheHour('d.last_seen_at')} AS device,
                ${onTheHour('s.last_used_at')} AS used,
                s.expires_at = s.last_used_at + make_interval(days => $2) AS ends
           FROM accounts a
           JOIN devices d ON d.account_id = a.id
           JOIN sessions s ON s.device_id = d.id
          WHERE a.id = $1`,
        [user.accountId, config.SESSION_TTL_DAYS],
      );
      assert.deepEqual(rows[0], { account: true, device: true, used: true, ends: true });
    });

    it('writes once an hour, not on every request', async () => {
      await awayFromTheTurnOfTheHour();
      // Used already this hour, with an end the server would not have chosen;
      // the account made to look older, so there is something to wait for.
      await pool.query(
        `UPDATE sessions SET last_used_at = ${HOUR}, expires_at = now() + interval '5 days'
          WHERE device_id = $1`,
        [user.deviceId],
      );
      await pool.query(
        `UPDATE accounts SET last_seen_at = ${HOUR} - interval '2 hours' WHERE id = $1`,
        [user.accountId],
      );

      await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
      await eventually(async () => {
        const { rows } = await pool.query<{ moved: boolean }>(
          `SELECT last_seen_at = ${HOUR} AS moved FROM accounts WHERE id = $1`,
          [user.accountId],
        );
        return rows[0]?.moved === true;
      }, 'the account was marked as seen');

      const { rows } = await pool.query<{ untouched: boolean }>(
        `SELECT expires_at < now() + interval '6 days' AS untouched FROM sessions WHERE device_id = $1`,
        [user.deviceId],
      );
      assert.equal(rows[0]?.untouched, true, 'a session already counted this hour is left alone');
    });

    it('ends a session that was not used for SESSION_TTL_DAYS', async () => {
      await pool.query(
        `UPDATE sessions SET last_used_at = ${HOUR} - make_interval(days => $2),
                             expires_at = ${HOUR} - interval '1 hour'
          WHERE device_id = $1`,
        [user.deviceId, config.SESSION_TTL_DAYS],
      );
      const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(user) });
      assert.equal(me.statusCode, 401, 'and using it again does not bring it back');
    });
  });

  it('lasts ninety days without use, unless configured otherwise', () => {
    // Not a year from sign-in, which signed out people who used Privio every
    // day and left a token nobody used valid for twelve months.
    assert.equal(config.SESSION_TTL_DAYS, 90);
  });
});
