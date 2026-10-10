import { timingSafeEqual } from 'node:crypto';
import {
  PrivateKey,
  PublicKey,
  SenderCertificate,
  ServerCertificate,
} from '@signalapp/libsignal-client';
import type { FastifyBaseLogger } from 'fastify';
import type { Config } from '../config.js';

/**
 * Sealed sender, the server's half: keys, and the certificates it signs.
 *
 * Everything cryptographic here is a call into `@signalapp/libsignal-client`,
 * Signal's own binding of libsignal. This file decides *what* to certify —
 * which account, which device, which identity key, for how long — and never
 * how. See docs/sealed-sender.md.
 */

/** How long a sender certificate is good for. Also the longest a device that
 *  lost its license can still send sealed. */
export const CERTIFICATE_TTL_MS = 24 * 60 * 60 * 1000;

/** Length of an unidentified access key, in bytes. */
export const ACCESS_KEY_BYTES = 16;

export interface SealedSenderKeys {
  trustRoot: PublicKey;
  serverCertificate: ServerCertificate;
  serverKey: PrivateKey;
  /** True when generated at start-up for tests or development. */
  ephemeral: boolean;
}

/**
 * The keys this server signs with, or null when sealed sender is off.
 *
 * Checked before the server takes a request: a certificate signed with a key
 * the trust root never vouched for would be refused by every app, and every
 * sealed message would vanish on arrival. Better to refuse to start.
 */
export function loadSealedSenderKeys(
  cfg: Pick<
    Config,
    | 'NODE_ENV'
    | 'SEALED_SENDER_TRUST_ROOT'
    | 'SEALED_SENDER_SERVER_CERTIFICATE'
    | 'SEALED_SENDER_SERVER_KEY'
  >,
  log?: FastifyBaseLogger,
): SealedSenderKeys | null {
  if (
    cfg.SEALED_SENDER_TRUST_ROOT &&
    cfg.SEALED_SENDER_SERVER_CERTIFICATE &&
    cfg.SEALED_SENDER_SERVER_KEY
  ) {
    const keys: SealedSenderKeys = {
      trustRoot: PublicKey.deserialize(new Uint8Array(Buffer.from(cfg.SEALED_SENDER_TRUST_ROOT, 'base64'))),
      serverCertificate: ServerCertificate.deserialize(
        Buffer.from(cfg.SEALED_SENDER_SERVER_CERTIFICATE, 'base64'),
      ),
      serverKey: PrivateKey.deserialize(Buffer.from(cfg.SEALED_SENDER_SERVER_KEY, 'base64')),
      ephemeral: false,
    };
    assertConsistent(keys);
    return keys;
  }

  if (cfg.NODE_ENV === 'production') {
    log?.info('sealed sender is off: SEALED_SENDER_* is not configured');
    return null;
  }

  // A throwaway set, so tests and a development server exercise the real path.
  // Certificates from it die with the process, which is said out loud rather
  // than discovered.
  const trustRoot = PrivateKey.generate();
  const serverKey = PrivateKey.generate();
  const keys: SealedSenderKeys = {
    trustRoot: trustRoot.getPublicKey(),
    serverCertificate: ServerCertificate.new(1, serverKey.getPublicKey(), trustRoot),
    serverKey,
    ephemeral: true,
  };
  if (cfg.NODE_ENV === 'development') {
    log?.warn(
      'sealed sender is using throwaway keys: certificates will not survive a restart',
    );
  }
  return keys;
}

/**
 * Proves the configured set belongs together by doing what it is for: signing
 * a certificate and validating it against the trust root.
 */
function assertConsistent(keys: SealedSenderKeys): void {
  const probe = PrivateKey.generate().getPublicKey();
  const certificate = SenderCertificate.new(
    '00000000-0000-4000-8000-000000000000',
    null,
    1,
    probe,
    Date.now() + 60_000,
    keys.serverCertificate,
    keys.serverKey,
  );
  if (!certificate.validate(keys.trustRoot, Date.now())) {
    throw new Error(
      'SEALED_SENDER_SERVER_KEY, SEALED_SENDER_SERVER_CERTIFICATE and SEALED_SENDER_TRUST_ROOT do not belong together',
    );
  }
}

/**
 * Signs a certificate naming one device of one account and the identity key
 * this server holds for that device.
 *
 * The key comes from the database, never from the caller: a certificate that
 * named whatever key it was asked to would let a device vouch for a key it does
 * not hold, which is exactly what the recipient relies on the certificate to
 * rule out.
 */
export function issueSenderCertificate(
  keys: SealedSenderKeys,
  sender: { accountId: string; deviceIndex: number; identityKey: Buffer },
  now = Date.now(),
): { certificate: Buffer; expiresAt: Date } {
  const expiresAt = now + CERTIFICATE_TTL_MS;
  const certificate = SenderCertificate.new(
    sender.accountId,
    null,
    sender.deviceIndex,
    PublicKey.deserialize(new Uint8Array(sender.identityKey)),
    expiresAt,
    keys.serverCertificate,
    keys.serverKey,
  );
  return { certificate: Buffer.from(certificate.serialize()), expiresAt: new Date(expiresAt) };
}

/**
 * Whether [presented] is the access key an account stored, in constant time.
 *
 * Every way of not matching — no key stored, wrong length, wrong bytes — is the
 * same `false`, so the caller cannot help but give them the same answer.
 */
export function accessKeyMatches(stored: Buffer | null, presented: Buffer | null): boolean {
  if (!stored || !presented) return false;
  if (stored.length !== ACCESS_KEY_BYTES || presented.length !== ACCESS_KEY_BYTES) return false;
  return timingSafeEqual(stored, presented);
}
