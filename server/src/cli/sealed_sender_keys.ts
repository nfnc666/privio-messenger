import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PrivateKey, ServerCertificate } from '@signalapp/libsignal-client';

/**
 * Generates the sealed sender keys, on a machine you trust, once.
 *
 *   npm --workspace server run sealed-sender:keys -- --out ./sealed-sender-keys
 *
 * Writes two private keys to files readable only by you (mode 0600) and prints
 * the two **public** values for the server's environment. No secret is ever
 * printed: a key in a terminal is a key in a scroll-back buffer, a screen share
 * and a shell recording.
 *
 * Then:
 *
 * 1. set `SEALED_SENDER_TRUST_ROOT` and `SEALED_SENDER_SERVER_CERTIFICATE` to
 *    the printed values, and `SEALED_SENDER_SERVER_KEY` to the contents of
 *    `server.key`, as secrets of the deployment;
 * 2. **move `trust-root.key` off this machine** and keep it offline. It is only
 *    needed to issue a new server certificate — after a server key is
 *    compromised or rotated — and with it offline, that can happen without the
 *    apps noticing anything but a new certificate.
 *
 * To rotate the server key later, keep the trust root:
 *
 *   npm --workspace server run sealed-sender:keys -- --out ./new --trust-root-key ./trust-root.key
 *
 * See docs/sealed-sender.md.
 */

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function writeSecret(path: string, key: PrivateKey): void {
  if (existsSync(path)) {
    throw new Error(`${path} exists; refusing to overwrite a key`);
  }
  // `wx` together with the mode: created by this call or not at all, and never
  // readable by anybody else for even a moment.
  writeFileSync(path, Buffer.from(key.serialize()).toString('base64') + '\n', {
    mode: 0o600,
    flag: 'wx',
  });
}

function main(): void {
  const out = argument('out');
  if (!out) {
    console.error('usage: sealed-sender:keys --out <directory> [--trust-root-key <file>]');
    process.exit(2);
  }
  const dir = resolve(out);
  mkdirSync(dir, { recursive: true, mode: 0o700 });

  const existingRoot = argument('trust-root-key');
  const trustRoot = existingRoot
    ? PrivateKey.deserialize(
        new Uint8Array(Buffer.from(readFileSync(existingRoot, 'utf8').trim(), 'base64')),
      )
    : PrivateKey.generate();
  const serverKey = PrivateKey.generate();
  // Key id 1 for a new trust root; a rotation should be told a new one.
  const keyId = Number(argument('key-id') ?? '1');
  const certificate = ServerCertificate.new(keyId, serverKey.getPublicKey(), trustRoot);

  if (!existingRoot) writeSecret(join(dir, 'trust-root.key'), trustRoot);
  writeSecret(join(dir, 'server.key'), serverKey);

  console.log('# Public values for the server environment:');
  console.log(
    `SEALED_SENDER_TRUST_ROOT=${Buffer.from(trustRoot.getPublicKey().serialize()).toString('base64')}`,
  );
  console.log(
    `SEALED_SENDER_SERVER_CERTIFICATE=${Buffer.from(certificate.serialize()).toString('base64')}`,
  );
  console.log('');
  console.log(`# SEALED_SENDER_SERVER_KEY: the contents of ${join(dir, 'server.key')} (a secret).`);
  if (!existingRoot) {
    console.log(`# Move ${join(dir, 'trust-root.key')} off this machine and keep it offline.`);
  }
}

main();
