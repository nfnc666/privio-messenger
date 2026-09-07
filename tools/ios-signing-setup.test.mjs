import assert from 'node:assert/strict';
import { createPrivateKey, generateKeyPairSync, createVerify } from 'node:crypto';
import { describe, it } from 'node:test';

import {
  AppStoreConnect,
  ascJwt,
  ensureBundleId,
  ensurePushCapability,
  parseArgs,
  planCertificate,
  replaceProfile,
  setUpSigning,
} from './ios-signing-setup.mjs';

/**
 * The setup script talks to Apple, so what is tested here is everything up to
 * the wire: the token Apple will or will not accept, the decisions taken
 * before anything is created, and the requests that come out. The fake below
 * is a recorder — it answers what Apple answers and remembers what it was
 * asked, which is the part a review cannot check by reading.
 */

const { privateKey, publicKey } = generateKeyPairSync('ec', {
  namedCurve: 'P-256',
});
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

/** Answers each request from a table, and keeps the calls. */
function fakeApple(routes) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    const path = url.replace('https://api.appstoreconnect.apple.com', '');
    calls.push({
      method: init.method,
      path,
      body: init.body ? JSON.parse(init.body) : undefined,
      auth: init.headers.authorization,
    });
    const key = `${init.method} ${path.split('?')[0]}`;
    const handler = routes[`${init.method} ${path}`] ?? routes[key];
    if (!handler) {
      return new Response(JSON.stringify({ errors: [{ title: 'no route', detail: key }] }), {
        status: 404,
      });
    }
    const answer = typeof handler === 'function' ? handler(calls.length) : handler;
    const status = answer.status ?? 200;
    // 204 means no content, and `Response` enforces that literally.
    const body = status === 204 || answer.body === undefined ? null : JSON.stringify(answer.body);
    return new Response(body, { status });
  };
  return { calls, api: new AppStoreConnect({ token: 'test-token', fetchImpl }) };
}

const certificateRow = (id, expires) => ({
  id,
  type: 'certificates',
  attributes: { serialNumber: `S${id}`, expirationDate: expires },
});

describe('the App Store Connect token', () => {
  it('is signed in the encoding Apple accepts, not Node’s default', () => {
    // DER is what `createSign().sign()` produces without being told otherwise,
    // and Apple answers a bare 401 for it — which reads like a wrong key and
    // has cost people days. The signature has to be the raw 64-byte pair.
    const token = ascJwt({
      keyId: 'ABC1234567',
      issuerId: '69a6de70-0000-0000-0000-1f2e3d4c5b6a',
      privateKey: pem,
    });
    const [header, payload, signature] = token.split('.');
    assert.equal(Buffer.from(signature, 'base64url').length, 64, 'not ieee-p1363');

    const verified = createVerify('SHA256')
      .update(`${header}.${payload}`)
      .verify(
        { key: publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      );
    assert.ok(verified);
  });

  it('names the key, the issuer and the audience Apple looks for', () => {
    const token = ascJwt({
      keyId: 'ABC1234567',
      issuerId: 'issuer-1',
      privateKey: pem,
      now: 1_700_000_000_000,
    });
    const [header, payload] = token
      .split('.')
      .slice(0, 2)
      .map((part) => JSON.parse(Buffer.from(part, 'base64url').toString()));
    assert.deepEqual(header, { alg: 'ES256', kid: 'ABC1234567', typ: 'JWT' });
    assert.equal(payload.iss, 'issuer-1');
    assert.equal(payload.aud, 'appstoreconnect-v1');
    assert.equal(payload.iat, 1_700_000_000);
    // Apple refuses anything more than twenty minutes out.
    assert.ok(payload.exp - payload.iat <= 20 * 60);
  });
});

describe('deciding about certificates', () => {
  it('makes one while there is room', () => {
    assert.deepEqual(planCertificate({ existing: [certificateRow('a', '2027-01-01')] }), {
      action: 'create',
    });
  });

  it('refuses at the limit rather than revoking somebody’s certificate', () => {
    const plan = planCertificate({
      existing: ['a', 'b', 'c'].map((id) => certificateRow(id, '2027-01-01')),
    });
    assert.equal(plan.action, 'refuse');
    assert.match(plan.reason, /limit/);
    assert.match(plan.reason, /revoke_oldest/, 'the way out has to be in the message');
  });

  it('revokes the oldest, and only when asked', () => {
    const plan = planCertificate({
      existing: [
        certificateRow('young', '2028-01-01'),
        certificateRow('old', '2026-02-01'),
        certificateRow('middle', '2027-01-01'),
      ],
      revokeOldest: true,
    });
    assert.equal(plan.action, 'revoke-then-create');
    assert.equal(plan.revokeId, 'old');
  });
});

describe('the bundle id', () => {
  it('is reused when it is already there, and gives up the team id', async () => {
    const { api, calls } = fakeApple({
      'GET /v1/bundleIds': {
        body: {
          data: [
            { id: 'other', attributes: { identifier: 'app.privio.privio.extra' } },
            { id: 'B1', attributes: { identifier: 'app.privio.privio', seedId: 'TEAM123456' } },
          ],
        },
      },
    });
    const { bundleId, created } = await ensureBundleId(api, {
      identifier: 'app.privio.privio',
      name: 'Privio',
    });
    assert.equal(created, false);
    assert.equal(bundleId.id, 'B1');
    assert.equal(bundleId.attributes.seedId, 'TEAM123456');
    assert.equal(calls.length, 1, 'nothing was created');
  });

  it('is created when it is not, as an iOS identifier', async () => {
    const { api, calls } = fakeApple({
      'GET /v1/bundleIds': { body: { data: [] } },
      'POST /v1/bundleIds': {
        status: 201,
        body: { data: { id: 'B2', attributes: { identifier: 'com.example.privio' } } },
      },
    });
    const { created } = await ensureBundleId(api, {
      identifier: 'com.example.privio',
      name: 'Privio',
    });
    assert.equal(created, true);
    assert.equal(calls[1].body.data.attributes.platform, 'IOS');
    assert.equal(calls[1].body.data.attributes.identifier, 'com.example.privio');
  });
});

describe('push capability', () => {
  it('is switched on', async () => {
    const { api, calls } = fakeApple({
      'POST /v1/bundleIdCapabilities': { status: 201, body: { data: { id: 'C1' } } },
    });
    const result = await ensurePushCapability(api, 'B1');
    assert.deepEqual(result, { enabled: true, alreadyOn: false });
    assert.equal(calls[0].body.data.attributes.capabilityType, 'PUSH_NOTIFICATIONS');
  });

  it('and an App ID that already has it is not an error', async () => {
    const { api } = fakeApple({
      'POST /v1/bundleIdCapabilities': {
        status: 409,
        body: { errors: [{ title: 'Entity already exists', detail: 'already exists' }] },
      },
    });
    assert.deepEqual(await ensurePushCapability(api, 'B1'), {
      enabled: true,
      alreadyOn: true,
    });
  });
});

describe('the provisioning profile', () => {
  it('replaces the one with the same name, because a profile pins a certificate', async () => {
    const { api, calls } = fakeApple({
      'GET /v1/profiles': { body: { data: [{ id: 'P-old', attributes: { name: 'Privio App Store' } }] } },
      'DELETE /v1/profiles/P-old': { status: 204 },
      'POST /v1/profiles': {
        status: 201,
        body: {
          data: {
            id: 'P-new',
            attributes: { name: 'Privio App Store', profileContent: 'YmFzZTY0' },
          },
        },
      },
    });
    const { profile, replaced } = await replaceProfile(api, {
      name: 'Privio App Store',
      bundleIdId: 'B1',
      certificateId: 'CERT1',
    });
    assert.equal(replaced, 1);
    assert.equal(profile.id, 'P-new');
    assert.equal(calls[1].method, 'DELETE');
    const created = calls[2].body.data;
    assert.equal(created.attributes.profileType, 'IOS_APP_STORE');
    assert.equal(created.relationships.bundleId.data.id, 'B1');
    assert.deepEqual(created.relationships.certificates.data, [
      { type: 'certificates', id: 'CERT1' },
    ]);
  });
});

describe('the whole setup', () => {
  const routes = {
    'GET /v1/bundleIds': {
      body: { data: [{ id: 'B1', attributes: { identifier: 'app.privio.privio', seedId: 'TEAM123456' } }] },
    },
    'POST /v1/bundleIdCapabilities': { status: 409, body: { errors: [{ title: 'already exists' }] } },
    'GET /v1/certificates': { body: { data: [] } },
    'POST /v1/certificates': {
      status: 201,
      body: {
        data: {
          id: 'CERT1',
          attributes: {
            serialNumber: 'ABCDEF',
            expirationDate: '2028-01-01T00:00:00Z',
            certificateContent: Buffer.from('cert-bytes').toString('base64'),
          },
        },
      },
    },
    'GET /v1/profiles': { body: { data: [] } },
    'POST /v1/profiles': {
      status: 201,
      body: {
        data: {
          id: 'P1',
          attributes: {
            name: 'Privio App Store',
            expirationDate: '2027-01-01T00:00:00Z',
            profileContent: Buffer.from('profile-bytes').toString('base64'),
          },
        },
      },
    },
  };

  it('produces a certificate, a profile and the team id, in that order', async () => {
    const { api, calls } = fakeApple(routes);
    const result = await setUpSigning(api, {
      identifier: 'app.privio.privio',
      csr: '-----BEGIN CERTIFICATE REQUEST-----\nx\n-----END CERTIFICATE REQUEST-----\n',
      profileName: 'Privio App Store',
    });

    assert.equal(result.teamId, 'TEAM123456');
    assert.equal(result.certificateId, 'CERT1');
    assert.equal(result.profileId, 'P1');
    assert.equal(Buffer.from(result.certificateContent, 'base64').toString(), 'cert-bytes');

    // The profile has to be made after the certificate: it is a snapshot of
    // one, and a profile made first would pin whatever came before.
    const order = calls.map((c) => `${c.method} ${c.path.split('?')[0]}`);
    assert.ok(
      order.indexOf('POST /v1/certificates') < order.indexOf('POST /v1/profiles'),
    );
    assert.ok(order.every((_, i) => calls[i].auth === 'Bearer test-token'));
  });

  it('never revokes anything on a run that was not asked to', async () => {
    const { api, calls } = fakeApple({
      ...routes,
      'GET /v1/certificates': {
        body: { data: ['a', 'b', 'c'].map((id) => certificateRow(id, '2027-01-01')) },
      },
    });
    await assert.rejects(
      setUpSigning(api, {
        identifier: 'app.privio.privio',
        csr: 'csr',
        profileName: 'Privio App Store',
      }),
      /limit/,
    );
    assert.equal(calls.filter((c) => c.method === 'DELETE').length, 0);
  });

  it('reports what Apple said when it refuses', async () => {
    const { api } = fakeApple({
      'GET /v1/bundleIds': {
        status: 401,
        body: { errors: [{ title: 'NOT_AUTHORIZED', detail: 'Authentication credentials are missing or invalid' }] },
      },
    });
    await assert.rejects(
      setUpSigning(api, { identifier: 'x', csr: 'c', profileName: 'p' }),
      /401 — NOT_AUTHORIZED: Authentication credentials are missing or invalid/,
    );
  });
});

describe('the command line', () => {
  it('turns flags into options', () => {
    assert.deepEqual(parseArgs(['--bundle-id', 'app.privio.privio', '--out', '/tmp/x']), {
      bundle_id: 'app.privio.privio',
      out: '/tmp/x',
    });
  });

  it('refuses a flag with nothing after it, rather than guessing', () => {
    assert.throws(() => parseArgs(['--out']), /Unusable argument/);
    assert.throws(() => parseArgs(['out', 'x']), /Unusable argument/);
  });
});
