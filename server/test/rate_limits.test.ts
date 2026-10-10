// The real budget, not the test one: this file is about the limiter itself, so
// it opts out of the multiplier every other test relies on. Set before the
// first import of the config, which reads it once.
process.env.RATE_LIMIT_FACTOR = '1';

import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';

const { buildApp } = await import('../src/app.js');
const { migrate } = await import('../src/db/migrate.js');
const { pool } = await import('../src/db/pool.js');
const { InProcessBus } = await import('../src/services/bus.js');
const { LoggingPushSender } = await import('../src/services/push.js');
const { LocalFileStorage } = await import('../src/services/storage.js');
const { deviceBody, deviceFixture, truncateAll } = await import('./helpers.js');

describe('rate limits', () => {
  let app: FastifyInstance;
  let bus: InstanceType<typeof InProcessBus>;
  let dir: string;
  let token: string;

  before(async () => {
    await migrate();
    await truncateAll();
    dir = await mkdtemp(join(tmpdir(), 'privio-ratelimit-'));
    bus = new InProcessBus();
    app = await buildApp({
      bus,
      push: new LoggingPushSender(),
      storage: new LocalFileStorage(dir),
    });
    await app.ready();

    const registered = await app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: {
        username: 'limits',
        password: 'correct-horse-battery',
        device: deviceBody(deviceFixture()),
      },
    });
    assert.equal(registered.statusCode, 201);
    token = registered.json().token;
  });

  after(async () => {
    await app.close();
    await bus.close();
    await rm(dir, { recursive: true, force: true });
    await pool.end();
  });

  it('reading your own account is not rationed like a login', async () => {
    // This is what a settings screen does. It used to share the login budget,
    // so opening one a few times could lock someone out of their own account
    // for five minutes.
    for (let attempt = 0; attempt < 25; attempt += 1) {
      const response = await app.inject({
        method: 'GET',
        url: '/v1/accounts/me',
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(response.statusCode, 200, `request ${attempt + 1} was refused`);
    }
  });

  it('guessing a password is', async () => {
    const attempt = () =>
      app.inject({
        method: 'POST',
        url: '/v1/sessions',
        payload: {
          username: 'limits',
          password: 'wrong-guess',
          device: deviceBody(deviceFixture()),
        },
      });

    // The register in `before` already spent one of the ten.
    const codes: number[] = [];
    for (let i = 0; i < 12; i += 1) codes.push((await attempt()).statusCode);

    assert.ok(
      codes.includes(429),
      `expected the limiter to refuse one of these: ${codes.join(', ')}`,
    );
  });

  // Last in the file: the second test spends this address's whole budget.
  it('two people behind one address have a budget each', async () => {
    // Found in a browser: every client was limited by address, because the
    // limiter ran before authentication had said who was asking. Everybody
    // behind a carrier's NAT shared one key-fetch budget of sixty an hour.
    const register = async (username: string) => {
      const response = await app.inject({
        method: 'POST',
        url: '/v1/accounts',
        payload: { username, password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
      });
      assert.equal(response.statusCode, 201);
      return response.json().token as string;
    };
    const first = await register('nat_first');
    const second = await register('nat_second');
    await register('nat_target');
    const fetchKeys = (as: string) =>
      app.inject({
        method: 'GET',
        url: '/v1/keys/nat_target',
        headers: { authorization: `Bearer ${as}` },
      });

    let refusedAt = 0;
    for (let attempt = 1; attempt <= 61 && refusedAt === 0; attempt += 1) {
      if ((await fetchKeys(first)).statusCode === 429) refusedAt = attempt;
    }
    assert.equal(refusedAt, 61, 'the first device is held to its sixty an hour');
    assert.equal(
      (await fetchKeys(second)).statusCode,
      200,
      'a second device at the same address was refused on the first one\'s account',
    );
  });

  it('a made-up token is limited by address, as before', async () => {
    // Resolving the session in the limiter must not let a client buy fresh
    // budgets with invented tokens.
    const codes = new Set<number>();
    for (let attempt = 0; attempt < 320; attempt += 1) {
      const response = await app.inject({
        method: 'GET',
        url: '/v1/accounts/me',
        headers: { authorization: `Bearer invented-${attempt}` },
      });
      codes.add(response.statusCode);
      if (response.statusCode === 429) break;
    }
    assert.ok(codes.has(429), `never limited: ${[...codes].join(', ')}`);
  });
});
