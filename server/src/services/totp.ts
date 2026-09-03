import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { config } from '../config.js';

/**
 * TOTP secrets, sealed for storage.
 *
 * A TOTP secret is a bearer credential: it does not expire, and whoever reads
 * it can produce valid codes for as long as the factor is on. In the clear, a
 * database leak on its own — a stolen backup, a replica, one injection —
 * defeated the second factor for every account, with nobody ever touching the
 * server.
 *
 * The key lives in the environment, so an attacker needs the database *and*
 * the process configuration. Against a fully compromised host this buys
 * nothing, because the host holds the key; that is the honest limit of it and
 * it is stated wherever this is described.
 */

/** Marks a sealed value, so a secret stored before this existed is recognised. */
const PREFIX = 'v1';

export class TotpKeyMissing extends Error {
  constructor() {
    super('TOTP_SECRET_KEY is not configured');
    this.name = 'TotpKeyMissing';
  }
}

function keyFrom(raw: string | undefined): Buffer {
  if (!raw) throw new TotpKeyMissing();
  const key = Buffer.from(raw, 'base64');
  if (key.length !== 32) {
    throw new Error('TOTP_SECRET_KEY must be base64 of exactly 32 bytes');
  }
  return key;
}

/** True when this deployment can store a new secret safely. */
export function canStoreSecrets(): boolean {
  try {
    keyFrom(config.TOTP_SECRET_KEY);
    return true;
  } catch {
    return false;
  }
}

/**
 * Seals a secret for the database.
 *
 * A fresh nonce every time, so the same secret sealed twice is not the same
 * bytes — otherwise the column would leak which accounts share a secret, which
 * for a re-enrolment is which account this is.
 */
export function sealSecret(secret: string, rawKey = config.TOTP_SECRET_KEY): string {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', keyFrom(rawKey), nonce);
  const sealed = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [PREFIX, nonce.toString('base64'), Buffer.concat([sealed, tag]).toString('base64')].join('.');
}

/**
 * Opens what [sealSecret] wrote.
 *
 * Returns null when it cannot be opened — a wrong key, or a tampered row.
 * Null rather than a throw because the caller's answer is the same either way:
 * this code does not check out.
 *
 * A value with no marker is a secret stored before sealing existed and is
 * returned as it is. That keeps already-enrolled accounts working; new ones
 * are always sealed.
 */
export function openSecret(stored: string | null, rawKey = config.TOTP_SECRET_KEY): string | null {
  if (stored === null) return null;
  const parts = stored.split('.');
  if (parts.length !== 3 || parts[0] !== PREFIX) return stored;

  try {
    const nonce = Buffer.from(parts[1]!, 'base64');
    const payload = Buffer.from(parts[2]!, 'base64');
    const tag = payload.subarray(payload.length - 16);
    const body = payload.subarray(0, payload.length - 16);
    const decipher = createDecipheriv('aes-256-gcm', keyFrom(rawKey), nonce);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
  } catch {
    return null;
  }
}
