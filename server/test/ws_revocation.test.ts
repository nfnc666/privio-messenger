import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { once } from 'node:events';
// `ws` ships no type declarations in this tree and adding @types/ws for one
// test file is more dependency than the test is worth. The surface used here
// is four methods, so it is described rather than installed.
// @ts-expect-error — no bundled declarations; the surface used is typed below.
import WebSocketImpl from 'ws';

interface Socket {
  readonly readyState: number;
  on(event: 'open' | 'close' | 'message' | 'error', listener: (arg: never) => void): void;
  send(data: string): void;
  close(): void;
}
const WebSocket = WebSocketImpl as unknown as new (url: string) => Socket;
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
 * Revoking a session has to reach a connection that is already open.
 *
 * The bug: the socket resolved its session once, at the door, and never again.
 * A device that signed out, was revoked from another phone, or belonged to an
 * account that had just changed its password kept its connection — and kept
 * receiving envelopes. Worse, its acknowledgements kept working, and an
 * acknowledgement deletes envelopes: a signed-out device quietly emptied the
 * queue of messages the real device had not read.
 *
 * These drive a real WebSocket against a listening server, because that is the
 * only way to test the thing that was broken. `inject` does not open sockets.
 */
describe('revoking a session that is already connected', () => {
  let h: TestHarness;
  let url: string;
  let owner: TestUser;
  let sender: TestUser;

  before(async () => {
    h = await createHarness();
    await h.app.listen({ port: 0, host: '127.0.0.1' });
    const address = h.app.server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    url = `ws://127.0.0.1:${port}/v1/ws`;
    owner = await registerUser(h.app, 'ws_owner');
    sender = await registerUser(h.app, 'ws_sender');
  });

  after(async () => {
    await h.close();
    await closePool();
  });

  /** Opens a socket and waits until it is actually connected. */
  async function connect(token: string): Promise<Socket> {
    const socket = new WebSocket(`${url}?token=${encodeURIComponent(token)}`);
    await once(socket as unknown as NodeJS.EventEmitter, 'open');
    return socket;
  }

  /** Resolves with the close code, or rejects if nothing closes in time. */
  function closedWithin(socket: Socket, ms: number): Promise<number> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('socket stayed open')), ms);
      socket.on('close', (code: never) => {
        clearTimeout(timer);
        resolve(code as unknown as number);
      });
    });
  }

  /** One sealed envelope to a device, through the ordinary send path. */
  async function sendTo(user: TestUser) {
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(sender),
      payload: {
        username: user.username,
        messages: [
          {
            deviceId: user.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.from('sealed').toString('base64'),
          },
        ],
      },
    });
    assert.equal(response.statusCode, 202, response.body);
  }

  async function queuedFor(deviceId: string): Promise<number> {
    const { rows } = await pool.query<{ count: string }>(
      'SELECT count(*) FROM envelopes WHERE recipient_device_id = $1',
      [deviceId],
    );
    return Number(rows[0]!.count);
  }

  it('a logout closes the socket that is already open', async () => {
    const socket = await connect(owner.token);
    const closing = closedWithin(socket, 4000);

    const out = await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(owner),
    });
    assert.equal(out.statusCode, 200, out.body);

    assert.equal(await closing, 4401, 'the connection is closed, not left running');
  });

  it('and delivers nothing afterwards', async () => {
    // The half that matters: after the close, envelopes stay queued for the
    // device rather than being handed to a connection that should not exist.
    const user = await registerUser(h.app, 'ws_quiet');
    const socket = await connect(user.token);
    const closing = closedWithin(socket, 4000);

    const frames: string[] = [];
    socket.on('message', (data: never) => frames.push(String(data)));

    await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(user),
    });
    await closing;

    await sendTo(user);
    await new Promise((r) => setTimeout(r, 300));

    assert.equal(
      frames.some((f) => f.includes('envelopes')),
      false,
      'nothing was delivered after the revocation',
    );
    assert.equal(await queuedFor(user.deviceId), 1, 'and the envelope is still queued');
  });

  it('a revoked connection cannot acknowledge, so it cannot empty the queue', async () => {
    // The more damaging half. An acknowledgement deletes envelopes; a
    // signed-out device that could still send one was deleting messages the
    // real device had never read.
    const user = await registerUser(h.app, 'ws_acker');
    await sendTo(user);
    assert.equal(await queuedFor(user.deviceId), 1);

    const socket = await connect(user.token);
    const closing = closedWithin(socket, 4000);
    await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(user),
    });
    await closing;

    // Sent anyway, the way a modified or lagging client would.
    try {
      socket.send(JSON.stringify({ type: 'ack', upTo: 999_999 }));
    } catch {
      // Closed already, which is also a correct outcome.
    }
    await new Promise((r) => setTimeout(r, 300));

    assert.equal(await queuedFor(user.deviceId), 1, 'the envelope survived');
  });

  it('revoking a device from another phone closes its socket', async () => {
    const user = await registerUser(h.app, 'ws_revoked_device');
    const socket = await connect(user.token);
    const closing = closedWithin(socket, 4000);

    // A second device of the same account does the revoking, which is how this
    // happens in the app.
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: user.username,
        password: 'correct-horse-battery',
        device: (await import('./helpers.js')).deviceBody(
          (await import('./helpers.js')).deviceFixture(),
        ),
      },
    });
    assert.equal(second.statusCode, 200, second.body);

    const revoked = await h.app.inject({
      method: 'DELETE',
      url: `/v1/devices/${user.deviceId}`,
      headers: { authorization: `Bearer ${second.json().token}` },
    });
    assert.equal(revoked.statusCode, 200, revoked.body);

    assert.equal(await closing, 4401);
  });

  it('a password change closes the other devices, and not the one that changed it', async () => {
    const user = await registerUser(h.app, 'ws_password');
    const other = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: {
        username: user.username,
        password: 'correct-horse-battery',
        device: (await import('./helpers.js')).deviceBody(
          (await import('./helpers.js')).deviceFixture(),
        ),
      },
    });
    const otherToken = other.json().token as string;

    const doomed = await connect(user.token);
    const kept = await connect(otherToken);
    const closing = closedWithin(doomed, 4000);
    let keptClosed = false;
    kept.on('close', () => {
      keptClosed = true;
    });

    const changed = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts/me/password',
      headers: { authorization: `Bearer ${otherToken}` },
      payload: {
        currentPassword: 'correct-horse-battery',
        newPassword: 'a-much-better-passphrase-now',
      },
    });
    assert.equal(changed.statusCode, 200, changed.body);

    assert.equal(await closing, 4401, 'the other device is signed out');
    assert.equal(keptClosed, false, 'and the device that made the change is not');
    kept.close();
  });

  it('deleting the account closes every socket it had', async () => {
    const user = await registerUser(h.app, 'ws_deleted');
    const socket = await connect(user.token);
    const closing = closedWithin(socket, 4000);

    const gone = await h.app.inject({
      method: 'DELETE',
      url: '/v1/accounts/me',
      headers: bearer(user),
      payload: { currentPassword: 'correct-horse-battery' },
    });
    assert.equal(gone.statusCode, 200, gone.body);

    assert.equal(await closing, 4401);
  });

  it('a revocation published before the socket subscribed still closes it', async () => {
    // The race the door alone cannot close. The session is revoked *first*, so
    // any broadcast has already happened and been heard by nobody; the
    // connection then opens. Without the re-check after subscribing it would
    // sit there believing a session that ended before it existed.
    const user = await registerUser(h.app, 'ws_race');
    await h.app.inject({
      method: 'DELETE',
      url: '/v1/sessions/current',
      headers: bearer(user),
    });

    const socket = new WebSocket(`${url}?token=${encodeURIComponent(user.token)}`);
    const code = await new Promise<number>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('socket stayed open')), 4000);
      socket.on('close', (c: never) => {
        clearTimeout(timer);
        resolve(c as unknown as number);
      });
    });

    assert.equal(code, 4401, 'refused, whichever order the two happened in');
  });

  it('an expired session is not honoured on a connection that is already open', async () => {
    // Expiry is not a revocation and nothing broadcasts it: it just becomes
    // true one day. The periodic re-check is what catches it, driven here by
    // moving the expiry into the past and asking for the check directly.
    const user = await registerUser(h.app, 'ws_expired');
    const socket = await connect(user.token);
    const closing = closedWithin(socket, 4000);

    await pool.query(
      "UPDATE sessions SET expires_at = now() - interval '1 hour' WHERE device_id = $1",
      [user.deviceId],
    );
    // The same signal a revocation sends, so the test does not have to wait a
    // minute for the timer. What is being checked is that the re-read of the
    // session refuses an expired one — not the interval, which is a constant.
    await h.bus.publish({ deviceId: user.deviceId, kind: 'revoked' });

    assert.equal(await closing, 4401);
  });
});
