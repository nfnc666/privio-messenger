import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { after, before, describe, it } from 'node:test';
// `ws` ships no type declarations in this tree and adding @types/ws for two
// test files is more dependency than the tests are worth. The surface used
// here is four methods, so it is described rather than installed.
// @ts-expect-error — no bundled declarations; the surface used is typed below.
import WebSocketImpl from 'ws';

interface Socket {
  readonly readyState: number;
  on(event: 'open' | 'close' | 'message' | 'error', listener: (arg: never) => void): void;
  send(data: string): void;
  close(): void;
}
const WebSocket = WebSocketImpl as unknown as new (url: string) => Socket;

import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
import { RedisBus, type DeliveryBus, type Wake } from '../src/services/bus.js';
import { DeliveryService } from '../src/services/delivery.js';
import { announceRevocation } from '../src/services/revocation.js';
import {
  bearer,
  closePool,
  createHarness,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * The overlaps: a session that ends while the connection is in the middle of
 * something, and the backstops that have to work when the broadcast does not.
 *
 * The existing suite covers a revocation that arrives at an idle socket. These
 * cover the awkward moments around it — a revocation landing while a read of
 * the queue is in flight, the timer that catches an expiry nobody announces,
 * and what a bus outage actually costs.
 */

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Opens a socket and collects every frame it is sent. */
async function connect(url: string, token: string): Promise<{ socket: Socket; frames: string[] }> {
  const frames: string[] = [];
  const socket = new WebSocket(`${url}?token=${encodeURIComponent(token)}`);
  socket.on('message', (raw: never) => frames.push(String(raw)));
  await new Promise<void>((resolve, reject) => {
    socket.on('open', () => resolve());
    socket.on('error', (err: never) => reject(err as unknown as Error));
  });
  return { socket, frames };
}

function closedWithin(socket: Socket, ms: number): Promise<number | 'still open'> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve('still open'), ms);
    socket.on('close', (code: never) => {
      clearTimeout(timer);
      resolve(code as unknown as number);
    });
  });
}

async function sendTo(h: TestHarness, from: TestUser, to: TestUser): Promise<void> {
  const response = await h.app.inject({
    method: 'POST',
    url: '/v1/messages',
    headers: bearer(from),
    payload: {
      username: to.username,
      messages: [
        {
          deviceId: to.deviceId,
          registrationId: 4242,
          type: 'ciphertext',
          content: Buffer.from('sealed').toString('base64'),
        },
      ],
    },
  });
  assert.equal(response.statusCode, 202, response.body);
}

const queuedFor = async (deviceId: string): Promise<number> => {
  const result = await pool.query<{ n: number }>(
    'SELECT count(*)::int AS n FROM envelopes WHERE recipient_device_id = $1',
    [deviceId],
  );
  return result.rows[0]?.n ?? 0;
};

describe('a session that ends mid-flight', () => {
  let h: TestHarness;
  let url: string;
  let sender: TestUser;
  const originalInterval = config.WS_REVALIDATE_MS;

  before(async () => {
    // Short enough to watch the real timer do its work, long enough not to
    // hammer the database. This is the actual `setInterval` the server runs —
    // the point of making the interval configuration was to be able to test
    // it rather than a stand-in for it.
    config.WS_REVALIDATE_MS = 300;
    h = await createHarness();
    await h.app.listen({ port: 0, host: '127.0.0.1' });
    const address = h.app.server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    url = `ws://127.0.0.1:${port}/v1/ws`;
    sender = await registerUser(h.app, 'race_sender');
  });

  // Deliberately not `closePool()` here: the suites below share this process's
  // pool, and ending it in the first `after` takes them all down with it.
  after(async () => {
    config.WS_REVALIDATE_MS = originalInterval;
    await h.close();
  });

  it('is not overtaken by the read it started before it ended', async () => {
    const owner = await registerUser(h.app, 'race_owner');
    const { socket, frames } = await connect(url, owner.token);
    await sleep(100); // let the connect-time drain finish

    // Park the next read of the queue. The guard that mattered used to be on
    // the near side of this await only: by the time the rows came back the
    // session could have ended, and the batch went out anyway.
    const realFetch = DeliveryService.prototype.fetch;
    let release!: () => void;
    const parked = new Promise<void>((resolve) => {
      release = resolve;
    });
    let parkedOnce = false;
    DeliveryService.prototype.fetch = async function patched(
      this: DeliveryService,
      ...args: Parameters<typeof realFetch>
    ) {
      if (!parkedOnce) {
        parkedOnce = true;
        await parked;
      }
      return realFetch.apply(this, args);
    };

    try {
      await sendTo(h, sender, owner);
      await sleep(150);
      assert.ok(parkedOnce, 'the read should be in flight');

      const loggedOut = await h.app.inject({
        method: 'DELETE',
        url: '/v1/sessions/current',
        headers: bearer(owner),
      });
      assert.equal(loggedOut.statusCode, 200, loggedOut.body);
      await sleep(50);
      release();
      await sleep(250);
    } finally {
      DeliveryService.prototype.fetch = realFetch;
    }

    assert.deepEqual(
      frames.filter((frame) => frame.includes('"envelopes"')),
      [],
      'a session that ended mid-read was still sent the batch',
    );
    assert.equal(
      await queuedFor(owner.deviceId),
      1,
      'and the envelope stays queued for the device that is still entitled to it',
    );
  });

  it('cannot acknowledge with a frame that was already in the pipe', async () => {
    const owner = await registerUser(h.app, 'race_acker');
    const { socket } = await connect(url, owner.token);
    await sendTo(h, sender, owner);
    await sleep(150);
    assert.equal(await queuedFor(owner.deviceId), 1);

    // Revocation and acknowledgement in the same tick: the socket must not
    // empty the queue on its way out. An ack deletes, which is the half of the
    // bug that loses messages rather than merely leaking them.
    const loggedOut = await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(owner),
    });
    assert.equal(loggedOut.statusCode, 200, loggedOut.body);
    try {
      socket.send(JSON.stringify({ type: 'ack', upTo: 999_999 }));
    } catch {
      // Sending on a socket the server has just closed is allowed to throw.
    }
    await sleep(250);

    assert.equal(await queuedFor(owner.deviceId), 1, 'the queue was emptied by a revoked session');
  });

  it('is closed by the periodic re-check when nothing announces it', async () => {
    // Nothing broadcasts an expiry: it simply becomes true one day. The timer
    // is the only thing that notices, and it is driven here for real — no bus
    // publish, no stand-in call, just the interval the server sets up.
    const owner = await registerUser(h.app, 'race_expired');
    const { socket } = await connect(url, owner.token);
    // Let the handshake's own re-read finish first. Without this pause the
    // expiry can land before it, and the socket closes at the door — which
    // proves nothing about the interval, the thing under test here.
    await sleep(150);
    const closing = closedWithin(socket, 4000);

    await pool.query(
      "UPDATE sessions SET expires_at = now() - interval '1 hour' WHERE device_id = $1",
      [owner.deviceId],
    );

    assert.equal(await closing, 4401, 'the interval never re-read the session');
  });

  it('survives a database outage rather than treating it as a mass logout', async () => {
    const owner = await registerUser(h.app, 'race_dbdown');
    const { socket } = await connect(url, owner.token);

    // Every read fails, including the periodic one. An outage is not a
    // revocation: closing every connection because Postgres blinked would sign
    // out an entire deployment at the worst possible moment.
    const realQuery = pool.query.bind(pool);
    (pool as { query: unknown }).query = () => Promise.reject(new Error('connection refused'));
    let stillOpen: number | 'still open';
    try {
      stillOpen = await closedWithin(socket, config.WS_REVALIDATE_MS * 3);
    } finally {
      (pool as { query: unknown }).query = realQuery;
    }
    assert.equal(stillOpen, 'still open', 'a database blip closed a valid session');

    // And once the database is back, the same timer still enforces the truth.
    await pool.query(
      "UPDATE sessions SET expires_at = now() - interval '1 hour' WHERE device_id = $1",
      [owner.deviceId],
    );
    assert.equal(await closedWithin(socket, 4000), 4401);
  });
});

describe('when the bus cannot deliver the revocation', () => {
  let h: TestHarness;
  let url: string;
  const originalInterval = config.WS_REVALIDATE_MS;
  const warnings: string[] = [];

  /** A bus that accepts subscriptions and fails every publish — Redis down. */
  const brokenBus: DeliveryBus = {
    publish: () => Promise.reject(new Error('redis unreachable')),
    subscribe: () => () => {},
    close: async () => {},
  };

  before(async () => {
    config.WS_REVALIDATE_MS = 300;
    h = await createHarness({ bus: brokenBus });
    await h.app.listen({ port: 0, host: '127.0.0.1' });
    const address = h.app.server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    url = `ws://127.0.0.1:${port}/v1/ws`;
  });

  after(async () => {
    config.WS_REVALIDATE_MS = originalInterval;
    await h.close();
    await closePool();
  });

  it('still signs the device out, and the socket closes at the next re-check', async () => {
    const user = await registerUser(h.app, 'bus_down');
    const { socket } = await connect(url, user.token);

    const loggedOut = await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(user),
    });
    // The logout is a committed transaction. A bus that cannot carry the news
    // must not be able to fail it — the alternative is somebody who cannot
    // sign out while Redis is down.
    assert.equal(loggedOut.statusCode, 200, loggedOut.body);

    // This is the residual window, and it is bounded by the re-check interval
    // rather than open-ended: the socket closes, just later than it would have.
    assert.equal(await closedWithin(socket, config.WS_REVALIDATE_MS * 6), 4401);
  });

  it('says so in the log instead of failing silently', async () => {
    const log = {
      warn(details: Record<string, unknown>, message: string) {
        warnings.push(message);
        assert.ok(!JSON.stringify(details).includes('token'), 'no credential in the line');
      },
    };
    await announceRevocation(brokenBus, { sessionId: 's', deviceId: 'd' }, log);
    assert.equal(warnings.length, 1);
    assert.match(warnings[0] ?? '', /revocation broadcast failed/);
  });
});

describe('the Redis bus itself', () => {
  /** The three methods `RedisBus` uses, over a real EventEmitter. */
  class FakeRedis extends EventEmitter {
    readonly published: string[] = [];
    subscribed?: string;
    disconnected = false;
    failSubscribe = false;

    async subscribe(channel: string): Promise<void> {
      if (this.failSubscribe) throw new Error('no connection');
      this.subscribed = channel;
    }
    async publish(_channel: string, message: string): Promise<number> {
      this.published.push(message);
      return 1;
    }
    disconnect(): void {
      this.disconnected = true;
    }
  }

  const busWith = (publisher: FakeRedis, subscriber: FakeRedis) =>
    new RedisBus(
      publisher as unknown as ConstructorParameters<typeof RedisBus>[0],
      subscriber as unknown as ConstructorParameters<typeof RedisBus>[1],
    );

  it('does not bring the process down when a client reports an error', () => {
    const publisher = new FakeRedis();
    const subscriber = new FakeRedis();
    busWith(publisher, subscriber);

    // An EventEmitter with no `error` listener rethrows, which for ioredis
    // means a Redis outage takes the server with it. This asserts the listener
    // exists by the only means that proves it: emitting.
    assert.doesNotThrow(() => publisher.emit('error', new Error('ECONNREFUSED')));
    assert.doesNotThrow(() => subscriber.emit('error', new Error('ECONNREFUSED')));
  });

  it('does not swallow a subscription that never happened', async () => {
    const publisher = new FakeRedis();
    const subscriber = new FakeRedis();
    subscriber.failSubscribe = true;
    const errors: unknown[] = [];
    busWith(publisher, subscriber);
    subscriber.on('error', (err: unknown) => errors.push(err));

    await sleep(10);
    // A subscribe that failed and was never reported is a node that silently
    // stops receiving revocations. It surfaces as an error on the client,
    // which is where an operator's handler already listens.
    assert.equal(errors.length, 1);
  });

  it('carries a revocation across the wire and back out to a listener', async () => {
    const publisher = new FakeRedis();
    const subscriber = new FakeRedis();
    const bus = busWith(publisher, subscriber);
    const seen: Wake[] = [];
    bus.subscribe((wake) => seen.push(wake));

    await bus.publish({ deviceId: 'device-1', kind: 'revoked', sessionId: 'session-1' });
    assert.equal(publisher.published.length, 1);

    // What another instance would receive.
    const frame = publisher.published[0];
    assert.ok(frame);
    subscriber.emit('message', 'privio:wake', frame);
    assert.deepEqual(seen, [{ deviceId: 'device-1', kind: 'revoked', sessionId: 'session-1' }]);
  });
});
