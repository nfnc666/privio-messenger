import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import http2 from 'node:http2';
import { generateKeyPairSync } from 'node:crypto';
import { X509Certificate } from 'node:crypto';
import { Http2ApnsTransport } from '../src/services/apns_transport.js';
import { ApnsTokenSource } from '../src/services/push_credentials.js';

/**
 * The transport, against a real HTTP/2 server.
 *
 * This exists because the unit tests for `ApnsSender` prove nothing about
 * whether a request can be made at all. Apple's endpoint speaks HTTP/2 only,
 * and Node's global `fetch` offers only `http/1.1` in the TLS ALPN handshake —
 * so the previous implementation would have failed in production during the
 * handshake, with `tlsv1 alert no application protocol`, while every injected-
 * fetch test passed.
 *
 * The server below is configured `allowHTTP1: false`, which is what makes the
 * test meaningful: anything that cannot speak HTTP/2 cannot talk to it.
 */
describe('the APNs transport', () => {
  let server: http2.Http2SecureServer;
  let origin: string;
  let transport: Http2ApnsTransport;

  /** Requests the server saw, so the test can assert what was actually sent. */
  const seen: { path: string; headers: Record<string, unknown>; body: string }[] = [];
  let respondWith = { status: 200, body: '' };

  before(async () => {
    // A throwaway self-signed certificate, generated here so the test carries
    // no key material of its own.
    const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const { execFileSync } = await import('node:child_process');
    const { mkdtempSync, writeFileSync, readFileSync } = await import('node:fs');
    const { tmpdir } = await import('node:os');
    const { join } = await import('node:path');
    void publicKey;

    const dir = mkdtempSync(join(tmpdir(), 'apns-test-'));
    writeFileSync(join(dir, 'key.pem'), privateKey.export({ type: 'pkcs8', format: 'pem' }));
    execFileSync('openssl', [
      'req', '-x509', '-key', join(dir, 'key.pem'), '-out', join(dir, 'cert.pem'),
      '-days', '1', '-subj', '/CN=localhost',
    ]);
    const cert = readFileSync(join(dir, 'cert.pem'));
    assert.ok(new X509Certificate(cert).subject.includes('localhost'));

    server = http2.createSecureServer({
      key: readFileSync(join(dir, 'key.pem')),
      cert,
      // HTTP/2 only, exactly like api.push.apple.com. This is the point.
      allowHTTP1: false,
    });
    server.on('stream', (stream, headers) => {
      let body = '';
      stream.setEncoding('utf8');
      stream.on('data', (chunk: string) => (body += chunk));
      stream.on('end', () => {
        seen.push({
          path: String(headers[':path']),
          headers: headers as Record<string, unknown>,
          body,
        });
        stream.respond({ ':status': respondWith.status });
        stream.end(respondWith.body);
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', () => resolve()));
    const address = server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    origin = `https://127.0.0.1:${port}`;
    // The certificate is self-signed; trusting it for this process only is what
    // lets the test talk to itself over real TLS with real ALPN.
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    transport = new Http2ApnsTransport(origin);
  });

  after(async () => {
    await transport.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
  });

  it('speaks HTTP/2, which is the only thing APNs accepts', async () => {
    respondWith = { status: 200, body: '' };
    const response = await transport.post(
      '/3/device/token-abc',
      { 'apns-topic': 'com.privio.app', 'apns-push-type': 'background' },
      JSON.stringify({ aps: { 'content-available': 1 } }),
    );

    assert.equal(response.status, 200);
    assert.equal(seen.at(-1)!.path, '/3/device/token-abc');
    assert.equal(seen.at(-1)!.headers['apns-topic'], 'com.privio.app');
    assert.equal(JSON.parse(seen.at(-1)!.body).aps['content-available'], 1);
  });

  it('global fetch cannot do this, which is why the transport exists', async () => {
    // The regression, demonstrated rather than described. If a later change
    // swaps the transport back to fetch, this is what would have caught it.
    await assert.rejects(
      fetch(`${origin}/3/device/token-abc`, {
        method: 'POST',
        body: '{}',
        signal: AbortSignal.timeout(5000),
      }),
      (err: Error) => {
        const message = String((err as { cause?: { message?: string } }).cause?.message ?? err.message);
        assert.match(
          message,
          /no application protocol|ALPN|protocol/i,
          `expected an ALPN failure, got: ${message}`,
        );
        return true;
      },
    );
  });

  it('reuses one connection rather than reconnecting per push', async () => {
    // Apple asks for this, and throttles providers that do not.
    const before = seen.length;
    await transport.post('/3/device/a', {}, '{}');
    await transport.post('/3/device/b', {}, '{}');
    assert.equal(seen.length, before + 2);
  });

  it('hands back the status and body Apple sent, without interpreting them', async () => {
    respondWith = { status: 410, body: '{"reason":"Unregistered"}' };
    const response = await transport.post('/3/device/dead', {}, '{}');
    assert.equal(response.status, 410);
    assert.match(response.body, /Unregistered/);
    respondWith = { status: 200, body: '' };
  });

  it('recovers after the connection is dropped underneath it', async () => {
    // A GOAWAY, a restart at Apple's end, a network blip. The next push has to
    // reconnect rather than failing forever on a dead session.
    await transport.post('/3/device/before', {}, '{}');
    await transport.close();
    const after = await transport.post('/3/device/after', {}, '{}');
    assert.equal(after.status, 200);
  });
});

describe('APNs provider tokens', () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;

  it('signs an ES256 JWT with the key id and team in it', () => {
    const source = new ApnsTokenSource({ privateKeyPem: pem, keyId: 'KEY123', teamId: 'TEAM456' });
    const token = source.token();

    const [header, claims, signature] = token.split('.');
    assert.deepEqual(JSON.parse(Buffer.from(header!, 'base64url').toString()), {
      alg: 'ES256',
      kid: 'KEY123',
    });
    assert.equal(JSON.parse(Buffer.from(claims!, 'base64url').toString()).iss, 'TEAM456');
    // ES256 over P-256 is r||s, 64 bytes. A DER signature would be longer and
    // variable, and Apple rejects it with InvalidProviderToken — which is the
    // sort of thing that is only ever found in production.
    assert.equal(Buffer.from(signature!, 'base64url').length, 64);
  });

  it('reuses a token rather than minting one per push', () => {
    // Apple refuses more than one token per twenty minutes.
    let now = 1_000_000;
    const source = new ApnsTokenSource({
      privateKeyPem: pem,
      keyId: 'KEY123',
      teamId: 'TEAM456',
      now: () => now,
    });

    const first = source.token();
    now += 10 * 60 * 1000;
    assert.equal(source.token(), first, 'ten minutes later, the same token');
  });

  it('mints a new one before Apple would call it too old', () => {
    // And refuses one older than an hour.
    let now = 1_000_000;
    const source = new ApnsTokenSource({
      privateKeyPem: pem,
      keyId: 'KEY123',
      teamId: 'TEAM456',
      now: () => now,
    });

    const first = source.token();
    now += 45 * 60 * 1000;
    assert.notEqual(source.token(), first, 'past forty minutes, a fresh one');
  });

  it('never puts the private key in the token', () => {
    const source = new ApnsTokenSource({ privateKeyPem: pem, keyId: 'K', teamId: 'T' });
    assert.equal(source.token().includes('PRIVATE KEY'), false);
  });
});
