// This file is about what the server hands out for a call, and the credentials
// depend on configuration read once at import time.
process.env.ICE_SERVERS = 'stun:stun.example.org:3478,turns:turn.example.org:5349';
process.env.TURN_SECRET = 'a-shared-secret-at-least-16';
process.env.TURN_TTL_SECONDS = '3600';

import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
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
const { iceConfiguration } = await import('../src/services/ice.js');
const { deviceBody, deviceFixture, truncateAll } = await import('./helpers.js');

describe('what a call asks the server for', () => {
  let app: FastifyInstance;
  let bus: InstanceType<typeof InProcessBus>;
  let dir: string;
  let token: string;

  before(async () => {
    await migrate();
    await truncateAll();
    dir = await mkdtemp(join(tmpdir(), 'privio-calls-'));
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
        username: 'caller',
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

  it('hands out the configured servers, with credentials only for TURN', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/v1/calls/ice',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(response.statusCode, 200);
    const body = response.json();

    assert.equal(body.iceServers.length, 2);
    const [stun, turn] = body.iceServers;

    assert.equal(stun.urls, 'stun:stun.example.org:3478');
    assert.equal(stun.username, undefined, 'a STUN server needs no credential');
    assert.equal(stun.credential, undefined);

    assert.equal(turn.urls, 'turns:turn.example.org:5349');
    assert.ok(turn.username, 'a relay does');
    assert.ok(turn.credential);
  });

  it('mints the credential coturn will check, over the expiry', async () => {
    const body = (
      await app.inject({
        method: 'GET',
        url: '/v1/calls/ice',
        headers: { authorization: `Bearer ${token}` },
      })
    ).json();
    const turn = body.iceServers[1];

    // Exactly what coturn's use-auth-secret computes: base64 HMAC-SHA1 of the
    // username under the shared secret.
    const expected = createHmac('sha1', process.env.TURN_SECRET!)
      .update(turn.username)
      .digest('base64');
    assert.equal(turn.credential, expected);
    assert.equal(String(body.expiresAt), turn.username, 'the username is the expiry');
    assert.ok(body.expiresAt > Math.floor(Date.now() / 1000), 'and it is in the future');
  });

  it('names no account in the credential', async () => {
    const body = (
      await app.inject({
        method: 'GET',
        url: '/v1/calls/ice',
        headers: { authorization: `Bearer ${token}` },
      })
    ).json();

    // The relay operator would otherwise be able to tie every relayed call to
    // an account, which is the linkage the rest of this server avoids.
    assert.match(body.iceServers[1].username, /^\d+$/);
    assert.ok(!body.iceServers[1].username.includes('caller'));
  });

  it('refuses an unauthenticated caller', async () => {
    const response = await app.inject({ method: 'GET', url: '/v1/calls/ice' });
    assert.equal(response.statusCode, 401, 'relay capacity is not public');
  });

  it('a credential expires, and the next one differs', () => {
    const first = iceConfiguration(new Date(1_700_000_000_000));
    const later = iceConfiguration(new Date(1_700_003_600_000));

    assert.notEqual(first.iceServers[1]!.credential, later.iceServers[1]!.credential);
    assert.ok(later.expiresAt! > first.expiresAt!);
  });
});
