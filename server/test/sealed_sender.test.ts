import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import { PrivateKey, SenderCertificate } from '@signalapp/libsignal-client';
import { config } from '../src/config.js';
import { pool } from '../src/db/pool.js';
import {
  accessKeyMatches,
  loadSealedSenderKeys,
  type SealedSenderKeys,
} from '../src/services/sealed_sender.js';
import {
  bearer,
  closePool,
  createHarness,
  deviceBody,
  deviceFixture,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * Sealed sender, the server's half. See docs/sealed-sender.md.
 *
 * What these tests hold it to: a certificate names the right account, device
 * and **the identity key the server holds**, and chains to the trust root; a
 * sealed send is let in only with the recipient's access key, never reads a
 * session, and stores an envelope that names nobody — and nothing about who
 * sent it reaches the recipient's drain either.
 */
describe('sealed sender', () => {
  let h: TestHarness;
  let keys: SealedSenderKeys;
  let alice: TestUser & { identity: PrivateKey };
  let bob: TestUser & { identity: PrivateKey };
  const bobAccessKey = randomBytes(16);

  /** Registers with a real Curve25519 identity key, as the app does. */
  async function registerWithIdentity(username: string) {
    const identity = PrivateKey.generate();
    const device = deviceFixture();
    const body = {
      ...deviceBody(device),
      identityKey: Buffer.from(identity.getPublicKey().serialize()).toString('base64'),
    };
    const response = await h.app.inject({
      method: 'POST',
      url: '/v1/accounts',
      payload: { username, password: 'correct-horse-battery', device: body },
    });
    assert.equal(response.statusCode, 201, response.body);
    return {
      ...(response.json() as Omit<TestUser, 'password'>),
      password: 'correct-horse-battery',
      identity,
    };
  }

  before(async () => {
    keys = loadSealedSenderKeys({ NODE_ENV: 'test' })!;
    h = await createHarness({ sealedSender: keys });
    alice = await registerWithIdentity('sealedalice');
    bob = await registerWithIdentity('sealedbob');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const sealedSend = (
    payload: Record<string, unknown>,
    headers: Record<string, string> = {},
  ) =>
    h.app.inject({ method: 'POST', url: '/v1/messages/sealed', headers, payload });

  const toBob = (content = Buffer.from('sealed bytes').toString('base64')) => ({
    accountId: bob.accountId,
    messages: [{ deviceId: bob.deviceId, registrationId: 4242, content }],
  });

  describe('certificates', () => {
    it('name the device and the identity key the server holds, and chain to the root', async () => {
      const out = await h.app.inject({
        method: 'GET',
        url: '/v1/certificate/delivery',
        headers: bearer(alice),
      });
      assert.equal(out.statusCode, 200, out.body);
      const certificate = SenderCertificate.deserialize(
        new Uint8Array(Buffer.from(out.json().certificate as string, 'base64')),
      );
      assert.equal(certificate.senderUuid(), alice.accountId);
      assert.equal(certificate.senderDeviceId(), 1);
      assert.deepEqual(
        Buffer.from(certificate.key().serialize()),
        Buffer.from(alice.identity.getPublicKey().serialize()),
        'the certificate must carry the registered identity key',
      );
      assert.equal(certificate.validate(keys.trustRoot, Date.now()), true);

      // A day, not forever: a device that loses its license loses sealed
      // sending within one.
      const expires = new Date(out.json().expiresAt as string).getTime();
      assert.ok(expires - Date.now() <= 24 * 3600_000 + 5_000);
      assert.equal(certificate.validate(keys.trustRoot, expires + 1), false);

      // And another server's root does not vouch for it.
      assert.equal(
        certificate.validate(PrivateKey.generate().getPublicKey(), Date.now()),
        false,
      );
    });

    it('need a session', async () => {
      const out = await h.app.inject({ method: 'GET', url: '/v1/certificate/delivery' });
      assert.equal(out.statusCode, 401);
    });

    it('need a license where the server requires one', async () => {
      (config as { LICENSE_REQUIRED: boolean }).LICENSE_REQUIRED = true;
      try {
        const out = await h.app.inject({
          method: 'GET',
          url: '/v1/certificate/delivery',
          headers: bearer(alice),
        });
        assert.equal(out.statusCode, 403);
        assert.equal(out.json().error, 'license_required');
      } finally {
        (config as { LICENSE_REQUIRED: boolean }).LICENSE_REQUIRED = false;
      }
    });

    it('are refused, not a 500, for a key that cannot be certified', async () => {
      const odd = await h.app.inject({
        method: 'POST',
        url: '/v1/accounts',
        payload: {
          username: 'sealedodd',
          password: 'correct-horse-battery',
          device: deviceBody(deviceFixture()),
        },
      });
      const out = await h.app.inject({
        method: 'GET',
        url: '/v1/certificate/delivery',
        headers: { authorization: `Bearer ${odd.json().token as string}` },
      });
      assert.equal(out.statusCode, 409);
      assert.equal(out.json().error, 'identity_key_unusable');
    });

    it('the trust root is public, and the one certificates chain to', async () => {
      const out = await h.app.inject({ method: 'GET', url: '/v1/certificate/trust-root' });
      assert.equal(out.statusCode, 200);
      assert.deepEqual(
        Buffer.from(out.json().trustRoot as string, 'base64'),
        Buffer.from(keys.trustRoot.serialize()),
      );
    });
  });

  describe('the access key', () => {
    it('is set by its owner, and never handed back', async () => {
      const set = await h.app.inject({
        method: 'PUT',
        url: '/v1/accounts/me/unidentified-access',
        headers: bearer(bob),
        payload: { accessKey: bobAccessKey.toString('base64') },
      });
      assert.equal(set.statusCode, 200, set.body);

      const me = await h.app.inject({ method: 'GET', url: '/v1/accounts/me', headers: bearer(bob) });
      assert.equal(me.body.includes(bobAccessKey.toString('base64')), false);
      assert.equal(me.body.includes('unidentified'), false);
    });

    it('must be sixteen bytes', async () => {
      const short = await h.app.inject({
        method: 'PUT',
        url: '/v1/accounts/me/unidentified-access',
        headers: bearer(bob),
        payload: { accessKey: randomBytes(8).toString('base64') },
      });
      assert.equal(short.statusCode, 400);
    });

    it('compares in one answer for every way of not matching', () => {
      assert.equal(accessKeyMatches(bobAccessKey, Buffer.from(bobAccessKey)), true);
      assert.equal(accessKeyMatches(bobAccessKey, randomBytes(16)), false);
      assert.equal(accessKeyMatches(bobAccessKey, null), false);
      assert.equal(accessKeyMatches(null, bobAccessKey), false);
      assert.equal(accessKeyMatches(bobAccessKey, bobAccessKey.subarray(0, 15)), false);
    });
  });

  describe('sending sealed', () => {
    it('is accepted with the access key, and stores an envelope that names nobody', async () => {
      await pool.query('DELETE FROM envelopes');
      const out = await sealedSend(toBob(), {
        'unidentified-access-key': bobAccessKey.toString('base64'),
      });
      assert.equal(out.statusCode, 202, out.body);

      const { rows } = await pool.query(
        'SELECT envelope_type, sender_account_id, sender_device_id FROM envelopes',
      );
      assert.deepEqual(rows, [
        { envelope_type: 'sealed', sender_account_id: null, sender_device_id: null },
      ]);
    });

    it('and the recipient s drain says nothing about who sent it', async () => {
      const drain = await h.app.inject({ method: 'GET', url: '/v1/messages', headers: bearer(bob) });
      assert.equal(drain.statusCode, 200);
      const [envelope] = drain.json().envelopes as Array<Record<string, unknown>>;
      assert.equal(envelope!.type, 'sealed');
      assert.equal(envelope!.senderAccountId, null);
      assert.equal(envelope!.senderDeviceId, null);
      assert.equal(envelope!.senderDeviceIndex, null);
      assert.equal(drain.body.includes(alice.accountId), false);
    });

    it('one answer for no key, a wrong key, an account that takes none, and no account', async () => {
      const cases: Array<[Record<string, unknown>, Record<string, string>]> = [
        [toBob(), {}],
        [toBob(), { 'unidentified-access-key': randomBytes(16).toString('base64') }],
        // Alice never stored a key, so nobody may send her sealed messages.
        [
          { accountId: alice.accountId, messages: [{ deviceId: alice.deviceId, registrationId: 1, content: 'AA==' }] },
          { 'unidentified-access-key': bobAccessKey.toString('base64') },
        ],
        [
          { accountId: '00000000-0000-4000-8000-000000000000', messages: [{ deviceId: bob.deviceId, registrationId: 1, content: 'AA==' }] },
          { 'unidentified-access-key': bobAccessKey.toString('base64') },
        ],
      ];
      const answers = [];
      for (const [payload, headers] of cases) {
        const out = await sealedSend(payload, headers);
        answers.push(`${out.statusCode} ${out.json().error as string}`);
      }
      assert.deepEqual(answers, Array(4).fill('401 unidentified_access_denied'));
    });

    it('refuses to be identified: a session on a sealed send is an error', async () => {
      const out = await sealedSend(toBob(), {
        'unidentified-access-key': bobAccessKey.toString('base64'),
        authorization: `Bearer ${alice.token}`,
      });
      assert.equal(out.statusCode, 400);
      assert.equal(out.json().error, 'do_not_identify');
    });

    it('still refuses a stale device list, and says what is off', async () => {
      // A device that is not Bob's, in place of the one that is: the same
      // reconciliation as an ordinary send, so nobody's phone is skipped.
      const ghost = '00000000-0000-4000-8000-0000000000aa';
      const out = await sealedSend(
        {
          accountId: bob.accountId,
          messages: [{ deviceId: ghost, registrationId: 1, content: 'AA==' }],
        },
        { 'unidentified-access-key': bobAccessKey.toString('base64') },
      );
      assert.equal(out.statusCode, 409);
      assert.equal(out.json().error, 'device_mismatch');
      assert.deepEqual(out.json().missingDevices, [bob.deviceId]);
      assert.deepEqual(out.json().extraDevices, [ghost]);
    });

    it('a sealed envelope with a sender cannot be stored at all', async () => {
      await assert.rejects(
        pool.query(
          `INSERT INTO envelopes (recipient_device_id, sender_account_id, envelope_type, content)
           VALUES ($1, $2, 'sealed', '\\x00')`,
          [bob.deviceId, alice.accountId],
        ),
        /envelopes_sealed_names_no_sender/,
      );
    });

    it('turning it off closes the door again', async () => {
      await h.app.inject({
        method: 'DELETE',
        url: '/v1/accounts/me/unidentified-access',
        headers: bearer(bob),
      });
      const out = await sealedSend(toBob(), {
        'unidentified-access-key': bobAccessKey.toString('base64'),
      });
      assert.equal(out.statusCode, 401);
    });
  });

  describe('when the account goes', () => {
    it('the wipe takes the access key with it', async () => {
      const carol = await registerWithIdentity('sealedcarol');
      await h.app.inject({
        method: 'PUT',
        url: '/v1/accounts/me/unidentified-access',
        headers: bearer(carol),
        payload: { accessKey: randomBytes(16).toString('base64') },
      });
      await h.app.inject({
        method: 'DELETE',
        url: '/v1/accounts/me',
        headers: bearer(carol),
        payload: { currentPassword: 'correct-horse-battery' },
      });
      const { rows } = await pool.query(
        'SELECT unidentified_access_key FROM accounts WHERE id = $1',
        [carol.accountId],
      );
      assert.equal(rows[0]?.unidentified_access_key ?? null, null);
    });
  });

  describe('without keys configured', () => {
    it('says it is off rather than pretending', async () => {
      const off = await createHarness({ sealedSender: null });
      try {
        const root = await off.app.inject({ method: 'GET', url: '/v1/certificate/trust-root' });
        assert.equal(root.statusCode, 503);
        assert.equal(root.json().error, 'sealed_sender_unavailable');
      } finally {
        await off.close();
      }
    });

    it('a mismatched set stops the server instead of issuing useless certificates', () => {
      const rootA = PrivateKey.generate();
      const fromA = loadSealedSenderKeys({ NODE_ENV: 'test' })!;
      assert.throws(
        () =>
          loadSealedSenderKeys({
            NODE_ENV: 'production',
            SEALED_SENDER_TRUST_ROOT: Buffer.from(rootA.getPublicKey().serialize()).toString('base64'),
            SEALED_SENDER_SERVER_CERTIFICATE: Buffer.from(fromA.serverCertificate.serialize()).toString('base64'),
            SEALED_SENDER_SERVER_KEY: Buffer.from(fromA.serverKey.serialize()).toString('base64'),
          }),
        /do not belong together/,
      );
      assert.equal(loadSealedSenderKeys({ NODE_ENV: 'production' }), null);
    });
  });
});
