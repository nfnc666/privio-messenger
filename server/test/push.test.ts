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
import { pool } from '../src/db/pool.js';
import type { ApnsTransport } from '../src/services/apns_transport.js';
import { isPrivateAddress, parsePushEndpoint } from '../src/util/outbound.js';
import {
  ApnsSender,
  FcmSender,
  RoutingPushSender,
  UnifiedPushSender,
  LoggingPushSender,
  type FetchLike,
  type PushOutcome,
  type PushSender,
  type PushTarget,
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
    const hanging: PushSender = { notify: () => new Promise<PushOutcome>(() => {}) };
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
  let caller: TestUser;

  /**
   * A sender the tests can steer, because the two things worth checking here
   * are what the relay is *told* and what it does about it. One harness, not
   * one per test: `createHarness` truncates, so a second one would delete the
   * device the first one registered.
   */
  const relay = {
    outcome: 'sent' as 'sent' | 'gone',
    sent: [] as PushTarget[],
    notify: async (target: PushTarget) => {
      relay.sent.push(target);
      return relay.outcome;
    },
  };

  before(async () => {
    h = await createHarness({ push: relay });
    user = await registerUser(h.app, 'pusher');
    caller = await registerUser(h.app, 'caller');
  });
  after(async () => {
    await h.close();
    // The pool is closed by the last describe in this file: node runs them in
    // order in one process, and ending it early leaves the rest without a
    // database.
  });

  async function register(payload: {
    provider: string | null;
    token: string | null;
    voipToken?: string | null;
  }) {
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

  it('takes a VoIP token alongside the APNs one', async () => {
    const response = await register({
      provider: 'apns',
      token: 'a-vendor-token',
      voipToken: 'a-pushkit-token',
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().callsRing, true);
  });

  it('refuses a VoIP token for a provider that has no such thing', async () => {
    // Android rings on the same token as everything else and a distributor has
    // one endpoint. Storing a second one there would be storing a string that
    // nothing will ever read.
    const response = await register({
      provider: 'fcm',
      token: 'a-vendor-token',
      voipToken: 'a-pushkit-token',
    });
    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error, 'invalid_push_config');
  });

  it('signing out takes the VoIP token with it', async () => {
    await register({ provider: 'apns', token: 'a-vendor-token', voipToken: 'a-pushkit-token' });
    await register({ provider: null, token: null });

    const { rows } = await pool.query('SELECT push_token, voip_token FROM devices WHERE id = $1', [
      user.deviceId,
    ]);
    assert.equal(rows[0].push_token, null);
    assert.equal(rows[0].voip_token, null, 'a device that stopped being pushed to stopped ringing');
  });

  /** One sealed envelope from `caller` to `pusher`'s device. */
  async function sendTo(type: string) {
    relay.sent.length = 0;
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(caller),
      payload: {
        username: 'pusher',
        messages: [
          {
            deviceId: user.deviceId,
            registrationId: 4242,
            type,
            content: Buffer.from('sealed').toString('base64'),
          },
        ],
      },
    });
    assert.equal(response.statusCode, 202, response.body);
  }

  it('a call wakes the device as a call, and a message does not', async () => {
    await register({ provider: 'apns', token: 'live-token', voipToken: 'live-voip' });

    await sendTo('call_signal');
    const ring = relay.sent.find((t) => t.deviceId === user.deviceId);
    assert.equal(ring?.urgency, 'call');
    assert.equal(ring?.voipToken, 'live-voip', 'and on the token that can ring it');

    await sendTo('ciphertext');
    const message = relay.sent.find((t) => t.deviceId === user.deviceId);
    assert.equal(message?.urgency, 'normal', 'a message can wait for a battery window');
  });

  it('a token the vendor calls dead is dropped, so the relay stops calling it', async () => {
    await register({ provider: 'apns', token: 'a-dead-token' });

    relay.outcome = 'gone';
    await sendTo('ciphertext');
    relay.outcome = 'sent';

    const { rows } = await pool.query(
      'SELECT push_provider, push_token FROM devices WHERE id = $1',
      [user.deviceId],
    );
    assert.equal(rows[0].push_token, null);
    assert.equal(rows[0].push_provider, null);
  });

  it('a "gone" for a token already replaced does not unregister the new one', async () => {
    // The wake-up and the re-registration race by nature: a vendor answering
    // about yesterday's token must not silently switch off a device that is
    // working perfectly today.
    await register({ provider: 'apns', token: 'old-token' });
    relay.outcome = 'gone';
    await sendTo('ciphertext');
    // The reply is still in flight when the device registers its new token.
    await register({ provider: 'apns', token: 'new-token' });
    relay.outcome = 'sent';

    const { rows } = await pool.query('SELECT push_token FROM devices WHERE id = $1', [
      user.deviceId,
    ]);
    assert.equal(rows[0].push_token, 'new-token');
  });
});

describe('the vendor senders', () => {
  /** Records what would have gone to Apple or Google, and answers as they do. */
  function recorder(status = 200, body = '') {
    const calls: { url: string; headers: Record<string, string>; body: string }[] = [];
    const fetch: FetchLike = async (url, init) => {
      calls.push({ url, headers: init?.headers ?? {}, body: init?.body ?? '' });
      return { ok: status < 400, status, text: async () => body };
    };
    return { calls, fetch };
  }

  /**
   * A stand-in transport, for the payload rules only.
   *
   * What this cannot show, and what the HTTP/2 test in
   * `apns_transport.test.ts` exists for: whether the request can be made at
   * all. Apple speaks HTTP/2 only, and a fake here would be just as happy with
   * a sender that could never connect.
   */
  function apnsRecorder(status = 200, body = '') {
    const calls: { path: string; headers: Record<string, string>; body: string }[] = [];
    const transport = {
      post: async (path: string, headers: Record<string, string>, payload: string) => {
        calls.push({ path, headers, body: payload });
        return { status, body };
      },
      close: async () => {},
    };
    return { calls, transport };
  }

  const apns = (transport: { post: ApnsTransport['post']; close: ApnsTransport['close'] }) =>
    new ApnsSender({ authorization: async () => 'jwt', topic: 'com.privio.app', transport });

  const fcm = (fetch: FetchLike) =>
    new FcmSender({ authorization: async () => 'oauth', projectId: 'privio', fetch });

  it('an APNs message wake-up carries no alert and no content', async () => {
    const { calls, transport } = apnsRecorder();
    await apns(transport).notify({ deviceId: 'd1', provider: 'apns', token: 'tok' });

    const sent = calls[0]!;
    assert.equal(sent.headers['apns-push-type'], 'background');
    assert.equal(sent.headers['apns-topic'], 'com.privio.app');
    const payload = JSON.parse(sent.body);
    assert.deepEqual(payload, { aps: { 'content-available': 1 } });
    assert.equal(sent.body.includes('alert'), false, 'Apple never carries a word of it');
  });

  it('an APNs call goes to the VoIP token, on the VoIP topic, at once', async () => {
    const { calls, transport } = apnsRecorder();
    await apns(transport).notify({
      deviceId: 'd1',
      provider: 'apns',
      token: 'tok',
      voipToken: 'voip-tok',
      urgency: 'call',
    });

    const sent = calls[0]!;
    assert.equal(sent.path, '/3/device/voip-tok', 'a call rings on its own token');
    assert.equal(sent.headers['apns-push-type'], 'voip');
    assert.equal(sent.headers['apns-topic'], 'com.privio.app.voip');
    assert.equal(sent.headers['apns-priority'], '10');
  });

  it('a call to a device with no VoIP token is not sent as a background push', async () => {
    // Sending it on the ordinary token would arrive whenever iOS felt like it,
    // which for a ringing phone is indistinguishable from never — and the
    // device would have no way to tell it apart from a message.
    const { calls, transport } = apnsRecorder();
    await apns(transport).notify({ deviceId: 'd1', provider: 'apns', token: 'tok', urgency: 'call' });
    assert.equal(calls.length, 0);
  });

  it('APNs 410 means the token is gone', async () => {
    const { transport } = apnsRecorder(410);
    assert.equal(
      await apns(transport).notify({ deviceId: 'd1', provider: 'apns', token: 'tok' }),
      'gone',
    );
  });

  it('APNs BadDeviceToken means the token is gone; a bad topic does not', async () => {
    const bad = apnsRecorder(400, '{"reason":"BadDeviceToken"}');
    assert.equal(
      await apns(bad.transport).notify({ deviceId: 'd1', provider: 'apns', token: 'tok' }),
      'gone',
    );
    const mine = apnsRecorder(403, '{"reason":"ExpiredProviderToken"}');
    assert.equal(
      await apns(mine.transport).notify({ deviceId: 'd1', provider: 'apns', token: 'tok' }),
      'sent',
      'the operator\'s credentials are not this device\'s fault',
    );
  });

  it('an FCM wake-up is data-only, so Google composes nothing', async () => {
    const { calls, fetch } = recorder();
    await fcm(fetch).notify({ deviceId: 'd1', provider: 'fcm', token: 'tok' });

    const payload = JSON.parse(calls[0]!.body);
    assert.equal('notification' in payload.message, false, 'a notification block would be text at Google');
    assert.deepEqual(payload.message.data, { privio: 'wake' });
    assert.equal(payload.message.android.priority, 'NORMAL');
  });

  it('an FCM call is high priority, and says only that it is a call', async () => {
    const { calls, fetch } = recorder();
    await fcm(fetch).notify({ deviceId: 'd1', provider: 'fcm', token: 'tok', urgency: 'call' });

    const payload = JSON.parse(calls[0]!.body);
    assert.deepEqual(payload.message.data, { privio: 'call' });
    assert.equal(payload.message.android.priority, 'HIGH');
    assert.equal(payload.message.android.ttl, '60s');
  });

  it('FCM 404 is UNREGISTERED; 403 is the operator\'s problem', async () => {
    const gone = recorder(404, '');
    assert.equal(await fcm(gone.fetch).notify({ deviceId: 'd1', provider: 'fcm', token: 'tok' }), 'gone');
    const mine = recorder(403, '');
    assert.equal(await fcm(mine.fetch).notify({ deviceId: 'd1', provider: 'fcm', token: 'tok' }), 'sent');
  });

  it('neither sender ever puts a recipient or a count on the wire', async () => {
    // The rule, asserted rather than trusted: everything leaving here is
    // opaque. The device id is ours, and it does not travel.
    const a = apnsRecorder();
    await apns(a.transport).notify({ deviceId: 'device-of-nina', provider: 'apns', token: 'tok' });
    const g = recorder();
    await fcm(g.fetch).notify({ deviceId: 'device-of-nina', provider: 'fcm', token: 'tok' });

    for (const sent of [...a.calls, ...g.calls]) {
      assert.equal(sent.body.includes('nina'), false);
      assert.equal(JSON.stringify(sent.headers).includes('nina'), false);
    }
  });
});

describe('what an unconfigured provider reports', () => {
  /*
   * The bug this covers: unconfigured APNs and FCM fell through to
   * `LoggingPushSender`, which records the intent and answers `sent`. The relay
   * therefore reported successful delivery for every wake-up it had no means to
   * make — quietly, in production, for as long as nobody looked.
   */

  it('answers skipped, never sent', async () => {
    const { createPushSender } = await import('../src/services/push_setup.js');
    const setup = createPushSender();

    // Nothing is configured in the test environment, which is the case being
    // tested: this is what a self-hosted server without an Apple or Google
    // account looks like.
    assert.equal(setup.configured.includes('apns'), false);
    assert.equal(setup.configured.includes('fcm'), false);

    for (const provider of ['apns', 'fcm'] as const) {
      const outcome = await setup.sender.notify({
        deviceId: 'd1',
        provider,
        token: 'a-token',
      });
      assert.equal(outcome, 'skipped', `${provider} must not claim to have delivered`);
    }
    await setup.close();
  });

  it('still delivers UnifiedPush, which needs no credentials', async () => {
    const { createPushSender } = await import('../src/services/push_setup.js');
    const setup = createPushSender();
    assert.equal(setup.configured.includes('unifiedpush'), true);
    await setup.close();
  });

  it('a skipped push does not drop the envelope or fail the send', async () => {
    // The rule that outranks all of this: the message is already stored. A push
    // that could not be made is not a message that was lost, and must not be
    // reported to the sender as a failure.
    const skipping: PushSender = { notify: async () => 'skipped' };
    const h = await createHarness({ push: skipping });
    const alice = await registerUser(h.app, 'skipsender');
    const bob = await registerUser(h.app, 'skiprecipient');

    await h.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(bob),
      payload: { provider: 'apns', token: 'a-token' },
    });

    const sent = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(alice),
      payload: {
        username: 'skiprecipient',
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
    assert.equal(sent.statusCode, 202, sent.body);

    const { rows } = await pool.query<{ count: string }>(
      'SELECT count(*) FROM envelopes WHERE recipient_device_id = $1',
      [bob.deviceId],
    );
    assert.equal(Number(rows[0]!.count), 1, 'the envelope is queued and waiting');

    // And the token was not dropped: `skipped` is not `gone`.
    const { rows: device } = await pool.query<{ push_token: string | null }>(
      'SELECT push_token FROM devices WHERE id = $1',
      [bob.deviceId],
    );
    assert.equal(device[0]!.push_token, 'a-token');

    await h.close();
    await closePool();
  });
});
