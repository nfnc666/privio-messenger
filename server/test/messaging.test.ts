import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
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

describe('messaging', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
    bob = await registerUser(h.app, 'bob');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const send = (from: TestUser, toUsername: string, deviceIds: string[], content = 'ciphertext') =>
    h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(from),
      payload: {
        username: toUsername,
        messages: deviceIds.map((deviceId) => ({
          deviceId,
          registrationId: 4242,
          type: 'ciphertext',
          content: Buffer.from(content).toString('base64'),
        })),
      },
    });

  it('hands out one prekey bundle per device and consumes a one-time prekey', async () => {
    const first = await h.app.inject({ method: 'GET', url: '/v1/keys/bob', headers: bearer(alice) });
    assert.equal(first.statusCode, 200);
    const bundle = first.json().devices[0];
    assert.equal(bundle.deviceId, bob.deviceId);
    assert.ok(bundle.identityKey && bundle.signedPreKey.signature);
    assert.ok(bundle.oneTimePreKey, 'a one-time prekey is handed out while the pool lasts');

    const second = await h.app.inject({ method: 'GET', url: '/v1/keys/bob', headers: bearer(alice) });
    assert.notEqual(
      second.json().devices[0].oneTimePreKey.keyId,
      bundle.oneTimePreKey.keyId,
      'the same one-time prekey is never handed out twice',
    );

    const third = await h.app.inject({ method: 'GET', url: '/v1/keys/bob', headers: bearer(alice) });
    assert.equal(third.json().devices[0].oneTimePreKey, null, 'an exhausted pool still yields a bundle');
  });

  it('delivers ciphertext and stores nothing else', async () => {
    const response = await send(alice, 'bob', [bob.deviceId], 'sealed-payload');
    assert.equal(response.statusCode, 202);

    const inbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
    assert.equal(inbox.statusCode, 200);
    const envelopes = inbox.json().envelopes;
    assert.equal(envelopes.length, 1);
    assert.equal(Buffer.from(envelopes[0].content, 'base64').toString(), 'sealed-payload');
    assert.equal(envelopes[0].senderAccountId, alice.accountId);

    const stored = await pool.query('SELECT content FROM envelopes WHERE id = $1', [envelopes[0].id]);
    assert.equal(
      stored.rows[0].content.toString(),
      'sealed-payload',
      'the server holds exactly the bytes the client sealed — it cannot open them',
    );
  });

  it('keeps envelopes until they are acknowledged', async () => {
    const before = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
    const envelopes = before.json().envelopes;
    assert.ok(envelopes.length > 0);

    const repeat = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
    assert.equal(repeat.json().envelopes.length, envelopes.length, 'a fetch alone does not consume');

    const ack = await h.app.inject({
      method: 'DELETE',
      url: `/v1/messages?upTo=${envelopes[envelopes.length - 1].id}`,
      headers: bearer(bob),
    });
    assert.equal(ack.statusCode, 200);
    const after = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
    assert.equal(after.json().envelopes.length, 0);
  });

  it('rejects a send that misses one of the recipient devices', async () => {
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'bob', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    const bobSecondDeviceId = second.json().deviceId;

    const stale = await send(alice, 'bob', [bob.deviceId]);
    assert.equal(stale.statusCode, 409);
    assert.deepEqual(stale.json().missingDevices, [bobSecondDeviceId].sort());

    const complete = await send(alice, 'bob', [bob.deviceId, bobSecondDeviceId]);
    assert.equal(complete.statusCode, 202);
    assert.equal(complete.json().deliveredTo, 2, 'every device of the recipient gets its own copy');
  });

  it('syncs to the sender’s other devices without echoing to the sending device', async () => {
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'alice', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    const aliceSecondDeviceId = second.json().deviceId;
    const response = await send(alice, 'alice', [aliceSecondDeviceId], 'sync-copy');
    assert.equal(response.statusCode, 202);
    assert.equal(response.json().deliveredTo, 1);
  });

  it('drops messages from a blocked sender without telling them', async () => {
    const carol = await registerUser(h.app, 'carol');
    const block = await h.app.inject({
      method: 'POST',
      url: '/v1/blocks',
      headers: bearer(carol),
      payload: { accountId: alice.accountId },
    });
    assert.equal(block.statusCode, 201);

    const response = await send(alice, 'carol', [carol.deviceId]);
    assert.equal(response.statusCode, 202, 'the sender sees an ordinary success');
    assert.equal(response.json().deliveredTo, 0);

    const inbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(carol) });
    assert.equal(inbox.json().envelopes.length, 0, 'nothing reaches the blocker');
  });

  it('wakes an offline device with a contentless push', async () => {
    const dave = await registerUser(h.app, 'dave');
    await h.app.inject({
      method: 'PUT',
      url: '/v1/devices/current/push',
      headers: bearer(dave),
      payload: { provider: 'apns', token: 'device-push-token' },
    });
    h.push.sent.length = 0;

    await send(alice, 'dave', [dave.deviceId], 'wake-me');
    assert.equal(h.push.sent.length, 1);
    assert.equal(h.push.sent[0]!.deviceId, dave.deviceId);
    assert.deepEqual(
      Object.keys(h.push.sent[0]!).sort(),
      ['deviceId', 'provider', 'token'],
      'the push carries no message content of any kind',
    );
  });

  it('refuses envelopes larger than the ciphertext limit', async () => {
    const oversized = await h.app.inject({
      method: 'POST',
      url: '/v1/messages',
      headers: bearer(alice),
      payload: {
        username: 'bob',
        messages: [
          {
            deviceId: bob.deviceId,
            registrationId: 4242,
            type: 'ciphertext',
            content: Buffer.alloc(70_000).toString('base64'),
          },
        ],
      },
    });
    assert.equal(oversized.statusCode, 400);
  });
  it('gives every device a stable index that survives revocation', async () => {
    const erin = await registerUser(h.app, 'erin');
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'erin', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(second.json().deviceIndex, 2);

    await h.app.inject({
      method: 'DELETE',
      url: `/v1/devices/${second.json().deviceId}`,
      headers: bearer(erin),
    });
    const third = await h.app.inject({
      method: 'POST',
      url: '/v1/sessions',
      payload: { username: 'erin', password: 'correct-horse-battery', device: deviceBody(deviceFixture()) },
    });
    assert.equal(
      third.json().deviceIndex,
      3,
      'a retired index is never reused, or an old session would address a new device',
    );
  });

  it('tells the recipient which device a message came from', async () => {
    const frank = await registerUser(h.app, 'frank');
    await send(alice, 'frank', [frank.deviceId], 'sealed');
    const inbox = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(frank) });
    const envelope = inbox.json().envelopes[0];
    assert.equal(envelope.senderDeviceIndex, 1, 'the index names the session to decrypt with');
  });
});
