import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import {
  bearer,
  closePool,
  createHarness,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';
import { isPrivateAddress, parsePushEndpoint } from '../src/util/outbound.js';
import {
  RoutingPushSender,
  UnifiedPushSender,
  LoggingPushSender,
  type PushSender,
} from '../src/services/push.js';

describe('outbound endpoint policy', () => {
  it('takes a public https endpoint', () => {
    const url = parsePushEndpoint('https://ntfy.sh/UP1a2b3c4d');
    assert.equal(url.hostname, 'ntfy.sh');
  });

  it('refuses anything that is not https', () => {
    // The wake-up carries nothing, but the request itself is the relay
    // reaching out — over plaintext it would say which endpoint, to anyone
    // on the path.
    assert.throws(() => parsePushEndpoint('http://ntfy.sh/UP1'), /https/);
    assert.throws(() => parsePushEndpoint('ftp://ntfy.sh/UP1'), /https/);
    assert.throws(() => parsePushEndpoint('not a url'), /not a URL/);
  });

  it('refuses addresses inside the network the relay is standing in', () => {
    // This is the whole reason the check exists: a device picks the address,
    // and the relay has reachability a device does not.
    for (const endpoint of [
      'https://127.0.0.1/up',
      'https://10.1.2.3/up',
      'https://192.168.0.1/up',
      'https://172.16.0.1/up',
      'https://169.254.169.254/latest/meta-data',
      'https://100.64.0.1/up',
      'https://[::1]/up',
      'https://[fd00::1]/up',
      'https://[::ffff:127.0.0.1]/up',
      'https://[::ffff:7f00:1]/up',
      'https://[64:ff9b::10.0.0.1]/up',
      'https://[fe80::1]/up',
      'https://[::]/up',
    ]) {
      assert.throws(() => parsePushEndpoint(endpoint), /publicly routable/, endpoint);
    }
  });

  it('refuses credentials smuggled into the URL', () => {
    assert.throws(() => parsePushEndpoint('https://user:pw@ntfy.sh/up'), /credentials/);
  });

  it('honours an allowlist when a deployment sets one', () => {
    const policy = { allowedHosts: ['ntfy.example.org'] };
    assert.ok(parsePushEndpoint('https://ntfy.example.org/UP1', policy));
    assert.throws(() => parsePushEndpoint('https://ntfy.sh/UP1', policy), /not allowed/);
  });

  it('treats anything that is not an address as unusable', () => {
    assert.equal(isPrivateAddress('not-an-address'), true);
    assert.equal(isPrivateAddress('8.8.8.8'), false);
    assert.equal(isPrivateAddress('2606:4700:4700::1111'), false);
    // The form the URL parser hands back, not the form a person types.
    assert.equal(isPrivateAddress('::ffff:7f00:1'), true);
    assert.equal(isPrivateAddress('::ffff:8.8.8.8'), false);
  });
});

describe('the wake-up itself', () => {
  it('carries no content, no identifier and no count', async () => {
    const seen: { url: string; init?: { body?: string; headers?: Record<string, string> } }[] = [];
    const sender = new UnifiedPushSender({
      fetch: async (url, init) => {
        seen.push({ url, init });
        return { ok: true, status: 200 };
      },
    });

    await sender.notify({
      deviceId: 'device-1234',
      provider: 'unifiedpush',
      token: 'https://ntfy.sh/UPsecrettopic',
    });

    assert.equal(seen.length, 1);
    const sent = seen[0]!;
    assert.equal(sent.url, 'https://ntfy.sh/UPsecrettopic');
    assert.equal(sent.init?.body, '.');
    const serialised = JSON.stringify(sent.init);
    assert.ok(!serialised.includes('device-1234'), 'the device id must not travel');
  });

  it('refuses to follow a redirect out of the validated host', async () => {
    // Following one would land the relay on an address nothing checked.
    const sender = new UnifiedPushSender({
      fetch: async (_url, init) => {
        assert.equal(init?.redirect, 'error');
        return { ok: true, status: 200 };
      },
    });

    await sender.notify({
      deviceId: 'd',
      provider: 'unifiedpush',
      token: 'https://ntfy.sh/UP1',
    });
  });

  it('will not post to an endpoint that resolves privately', async () => {
    let called = false;
    const sender = new UnifiedPushSender({
      fetch: async () => {
        called = true;
        return { ok: true, status: 200 };
      },
    });

    await assert.rejects(
      sender.notify({ deviceId: 'd', provider: 'unifiedpush', token: 'https://127.0.0.1/up' }),
      /privately/,
    );
    assert.equal(called, false, 'the check has to happen before the request');
  });

  it('sends each provider to the sender that knows it', async () => {
    const unified = new LoggingPushSender();
    const rest = new LoggingPushSender();
    const router = new RoutingPushSender({ unifiedpush: unified }, rest);

    await router.notify({ deviceId: 'a', provider: 'unifiedpush', token: 'https://ntfy.sh/x' });
    await router.notify({ deviceId: 'b', provider: 'fcm', token: 'token' });

    assert.deepEqual(unified.sent.map((t) => t.deviceId), ['a']);
    assert.deepEqual(rest.sent.map((t) => t.deviceId), ['b']);
  });
});

describe('a wake-up that goes wrong', () => {
  let h: TestHarness;

  after(async () => {
    await h?.close();
  });

  it('does not fail the send it belongs to, and does not crash the process', async () => {
    // The envelope is stored before any of this runs. A distributor that has
    // gone away, or an endpoint that stopped resolving publicly, is somebody
    // else's problem — it must not turn a delivered message into an error the
    // sender sees, and an unhandled rejection here would take the server down.
    const exploding: PushSender = {
      notify: async () => {
        throw new Error('endpoint resolves privately');
      },
    };
    h = await createHarness({ push: exploding });

    const erin = await registerUser(h.app, 'erin');
    const frank = await registerUser(h.app, 'frank');
    await h.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(frank),
      payload: { provider: 'unifiedpush', token: 'https://ntfy.sh/UPgone' },
    });

    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(erin),
      payload: {
        username: 'frank',
        messages: [
          {
            deviceId: frank.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.from('sealed').toString('base64'),
          },
        ],
      },
    });

    assert.equal(response.statusCode, 202, response.body);
  });

  it('does not hold the sender behind a distributor that never answers', async () => {
    // Otherwise registering a black-holing endpoint would cost everyone who
    // messages you the full request timeout, which is a cheap thing to do to
    // other people.
    const hanging: PushSender = { notify: () => new Promise<void>(() => {}) };
    const slow = await createHarness({ push: hanging });

    const gina = await registerUser(slow.app, 'gina');
    const hank = await registerUser(slow.app, 'hank');
    await slow.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(hank),
      payload: { provider: 'unifiedpush', token: 'https://ntfy.sh/UPblackhole' },
    });

    const started = Date.now();
    const response = await slow.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(gina),
      payload: {
        username: 'hank',
        messages: [
          {
            deviceId: hank.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.from('sealed').toString('base64'),
          },
        ],
      },
    });
    const elapsed = Date.now() - started;

    assert.equal(response.statusCode, 202, response.body);
    assert.ok(elapsed < 3000, `the send waited ${elapsed}ms on a dead endpoint`);
    await slow.close();
  });
});

describe('registering an endpoint', () => {
  let h: TestHarness;
  let user: TestUser;

  before(async () => {
    h = await createHarness();
    user = await registerUser(h.app, 'pusher');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  async function register(payload: { provider: string | null; token: string | null }) {
    return h.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(user),
      payload,
    });
  }

  it('accepts a distributor endpoint', async () => {
    const response = await register({
      provider: 'unifiedpush',
      token: 'https://ntfy.sh/UPabc123',
    });

    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().pushEnabled, true);
  });

  it('rejects one pointing back into the network', async () => {
    const response = await register({
      provider: 'unifiedpush',
      token: 'https://169.254.169.254/latest/meta-data',
    });

    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error, 'invalid_push_config');
  });

  it('still takes an APNs token, which is not a URL at all', async () => {
    const response = await register({ provider: 'apns', token: 'a-vendor-token' });
    assert.equal(response.statusCode, 200, response.body);
  });

  it('clears both fields together', async () => {
    const response = await register({ provider: null, token: null });
    assert.equal(response.statusCode, 200);
    assert.equal(response.json().pushEnabled, false);
  });
});
