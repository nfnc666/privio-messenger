import { createHmac, randomBytes } from 'node:crypto';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import { ApiError } from '../util/errors.js';

/**
 * License keys.
 *
 * A key is a bearer secret: whoever holds it can redeem it, and after that it
 * belongs to one account for good. Nothing here ever logs or returns a key that
 * was not just generated in the same call.
 */

// Crockford base32 — no I, L, O or U, so a key can be read off a screen and
// typed on a phone without the ambiguous glyphs turning into support tickets.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const KEY_BODY_LENGTH = 16;

export interface LicenseStatus {
  licensed: boolean;
  source?: string;
  redeemedAt?: string;
  /** Active devices this license covers. */
  maxDevices?: number;
  /** How many of them are in use, so a client can say "3 of 5" without guessing. */
  devices?: number;
}

function requireSecret(): string {
  if (!config.LICENSE_HASH_SECRET) {
    throw new Error('LICENSE_HASH_SECRET is not configured — licensing is unavailable');
  }
  return config.LICENSE_HASH_SECRET;
}

/**
 * 16 characters of base32 is 80 bits of entropy, which is far past what the
 * rate limiter on the redemption endpoint would ever let anyone search.
 * 256 % 32 === 0, so the byte-to-symbol mapping is uniform.
 */
export function generateLicenseKey(): string {
  const bytes = randomBytes(KEY_BODY_LENGTH);
  const body = Array.from(bytes, (b) => ALPHABET[b % 32]).join('');
  return `PRIVIO-${body.slice(0, 4)}-${body.slice(4, 8)}-${body.slice(8, 12)}-${body.slice(12, 16)}`;
}

/**
 * Folds the shapes a human can produce onto one canonical form: case,
 * separators and the characters Crockford treats as aliases. A key typed with
 * an O instead of a zero still activates.
 */
export function normaliseLicenseKey(input: string): string {
  const cleaned = input.toUpperCase().replace(/[^0-9A-Z]/g, '');
  // Strip the prefix before folding aliases — it contains an I and an O itself.
  const body = cleaned.startsWith('PRIVIO') ? cleaned.slice('PRIVIO'.length) : cleaned;
  return body.replace(/O/g, '0').replace(/[IL]/g, '1').replace(/U/g, 'V');
}

export function licenseHash(key: string): Buffer {
  return createHmac('sha256', requireSecret()).update(normaliseLicenseKey(key)).digest();
}

export type IssueResult =
  | { status: 'issued'; licenseKey: string; licenseId: string }
  | { status: 'already_issued'; licenseId: string | null };

/**
 * Issues a license for a confirmed order.
 *
 * The plaintext key is returned exactly once, here, and afterwards only its
 * hash survives — so the caller has to persist what it gets. A retried webhook
 * is answered with `already_issued` rather than a second key: the order is not
 * charged twice, so it must not mint twice either.
 */
export async function issueLicense(input: {
  paymentProvider: string;
  paymentReference: string;
  source?: 'key' | 'apple' | 'google';
  /** Omitted means the column default, which is what every earlier license has. */
  maxDevices?: number;
}): Promise<IssueResult> {
  const licenseKey = generateLicenseKey();

  try {
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO licenses (key_hash, source, payment_provider, payment_reference, max_devices)
       VALUES ($1, $2, $3, $4, COALESCE($5, 5)) RETURNING id`,
      [
        licenseHash(licenseKey),
        input.source ?? 'key',
        input.paymentProvider,
        input.paymentReference,
        input.maxDevices ?? null,
      ],
    );
    return { status: 'issued', licenseKey, licenseId: rows[0]!.id };
  } catch (err) {
    if ((err as { code?: string }).code !== '23505') throw err;
    const existing = await findByPayment(input.paymentProvider, input.paymentReference);
    return { status: 'already_issued', licenseId: existing?.id ?? null };
  }
}

export async function findByPayment(
  paymentProvider: string,
  paymentReference: string,
): Promise<{ id: string; status: string } | null> {
  const { rows } = await pool.query<{ id: string; status: string }>(
    'SELECT id, status FROM licenses WHERE payment_provider = $1 AND payment_reference = $2',
    [paymentProvider, paymentReference],
  );
  return rows[0] ?? null;
}

/** Chargebacks and refunds. A revoked license stops counting immediately. */
export async function revokeByPayment(
  paymentProvider: string,
  paymentReference: string,
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE licenses SET status = 'revoked'
      WHERE payment_provider = $1 AND payment_reference = $2 AND status = 'active'`,
    [paymentProvider, paymentReference],
  );
  return (rowCount ?? 0) > 0;
}

/**
 * Redeems a key for an account.
 *
 * The whole decision is one UPDATE: the row is only claimed if it is still
 * unredeemed, so two devices racing with the same key cannot both win, and
 * there is no window between a check and a write for them to race in.
 */
export async function redeem(key: string, accountId: string): Promise<LicenseStatus> {
  const hash = licenseHash(key);

  const { rows } = await pool
    .query<{ source: string; redeemed_at: Date; max_devices: number }>(
      `UPDATE licenses SET redeemed_by = $2, redeemed_at = now()
        WHERE key_hash = $1 AND status = 'active' AND redeemed_by IS NULL
        RETURNING source, redeemed_at, max_devices`,
      [hash, accountId],
    )
    .catch((err: { code?: string }) => {
      // The partial unique index on redeemed_by: this account already holds a
      // license. The transaction rolled back, so the key was not consumed.
      if (err.code === '23505') {
        throw ApiError.conflict(
          'account_already_licensed',
          'This account already has an active license',
        );
      }
      throw err;
    });

  const claimed = rows[0];
  if (claimed) {
    return {
      licensed: true,
      source: claimed.source,
      redeemedAt: claimed.redeemed_at.toISOString(),
      maxDevices: claimed.max_devices,
      devices: await activeDeviceCount(accountId),
    };
  }

  // Nothing was claimed. Only now is it worth asking why — reading first would
  // have opened the race the UPDATE closes.
  const { rows: found } = await pool.query<{
    status: string;
    redeemed_by: string | null;
    source: string;
    redeemed_at: Date | null;
    max_devices: number;
  }>(
    'SELECT status, redeemed_by, source, redeemed_at, max_devices FROM licenses WHERE key_hash = $1',
    [hash],
  );

  const license = found[0];
  if (!license) throw ApiError.notFound('license_not_found', 'No such license key');
  if (license.status === 'revoked') {
    throw ApiError.conflict('license_revoked', 'This license has been revoked');
  }
  // Re-sending the same key from the same account is a retry, not an error.
  if (license.redeemed_by === accountId) {
    return {
      licensed: true,
      source: license.source,
      redeemedAt: license.redeemed_at?.toISOString(),
      maxDevices: license.max_devices,
      devices: await activeDeviceCount(accountId),
    };
  }
  throw ApiError.conflict('license_already_redeemed', 'This key has already been used');
}

/** Devices that count against the limit: registered and not revoked. */
async function activeDeviceCount(accountId: string): Promise<number> {
  const { rows } = await pool.query<{ count: string }>(
    'SELECT count(*) FROM devices WHERE account_id = $1 AND revoked_at IS NULL',
    [accountId],
  );
  return Number(rows[0]!.count);
}

export async function statusFor(accountId: string): Promise<LicenseStatus> {
  const { rows } = await pool.query<{ source: string; redeemed_at: Date; max_devices: number }>(
    `SELECT source, redeemed_at, max_devices FROM licenses
      WHERE redeemed_by = $1 AND status = 'active'`,
    [accountId],
  );
  const license = rows[0];
  if (!license) return { licensed: false };
  return {
    licensed: true,
    source: license.source,
    redeemedAt: license.redeemed_at.toISOString(),
    maxDevices: license.max_devices,
    devices: await activeDeviceCount(accountId),
  };
}

export async function isLicensed(accountId: string): Promise<boolean> {
  const { rows } = await pool.query(
    `SELECT 1 FROM licenses WHERE redeemed_by = $1 AND status = 'active'`,
    [accountId],
  );
  return rows.length > 0;
}
