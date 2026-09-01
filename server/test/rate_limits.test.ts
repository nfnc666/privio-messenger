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
});
