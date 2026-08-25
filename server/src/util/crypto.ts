import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { hash as argon2Hash, verify as argon2Verify, Algorithm } from '@node-rs/argon2';

// Deliberately thin wrappers. Privio writes no cryptographic primitives of its
// own — this module only composes vetted implementations (Node's WebCrypto-backed
// `node:crypto` and the RustCrypto Argon2 binding).

const ARGON2_OPTIONS = {
  algorithm: Algorithm.Argon2id,
  memoryCost: 64 * 1024, // 64 MiB
  timeCost: 3,
  parallelism: 1,
} as const;

/** Hashes a password or PIN with Argon2id. The returned string embeds its own salt and params. */
export function hashSecret(secret: string): Promise<string> {
  return argon2Hash(secret, ARGON2_OPTIONS);
}

/** Constant-time-ish verification; never throws on a malformed stored hash. */
export async function verifySecret(storedHash: string, secret: string): Promise<boolean> {
  try {
    return await argon2Verify(storedHash, secret, ARGON2_OPTIONS);
  } catch {
    return false;
  }
}

/** A 256-bit opaque bearer token, URL-safe. Only its SHA-256 is ever persisted. */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

export function tokenHash(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

export function constantTimeEquals(a: Buffer, b: Buffer): boolean {
  return a.length === b.length && timingSafeEqual(a, b);
}

export function sha256(data: Buffer): Buffer {
  return createHash('sha256').update(data).digest();
}
