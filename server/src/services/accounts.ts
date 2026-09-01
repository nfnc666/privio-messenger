import { pool, withTransaction } from '../db/pool.js';
import { hashSecret, verifySecret } from '../util/crypto.js';

export interface AccountRow {
  id: string;
  username: string;
  display_name: string | null;
  password_hash: string;
  totp_secret: string | null;
  totp_enabled_at: Date | null;
  duress_code_hash: string | null;
  privacy: PrivacySettings;
  avatar_media_id: string | null;
  avatar_updated_at: Date | null;
  created_at: Date;
  last_seen_at: Date;
}

export interface PrivacySettings {
  lastSeen?: 'everyone' | 'contacts' | 'nobody';
  readReceipts?: boolean;
  typingIndicators?: boolean;
  whoCanAddMeToGroups?: 'everyone' | 'contacts';
}

export async function findByUsername(username: string): Promise<AccountRow | null> {
  const { rows } = await pool.query<AccountRow>(
    'SELECT * FROM accounts WHERE username = $1 AND deleted_at IS NULL',
    [username],
  );
  return rows[0] ?? null;
}

export async function findById(accountId: string): Promise<AccountRow | null> {
  const { rows } = await pool.query<AccountRow>(
    'SELECT * FROM accounts WHERE id = $1 AND deleted_at IS NULL',
    [accountId],
  );
  return rows[0] ?? null;
}

/**
 * Duress wipe. Entering the duress code where the password goes destroys every
 * device, session, queued envelope, contact and backup for the account, leaving
 * a shell that still answers "wrong password" so the wipe is not observable.
 */
export async function wipeAccount(accountId: string): Promise<void> {
  await withTransaction(async (client) => {
    // Envelopes, sessions and prekeys cascade from devices.
    await client.query('DELETE FROM devices WHERE account_id = $1', [accountId]);
    await client.query('DELETE FROM envelopes WHERE sender_account_id = $1', [accountId]);
    await client.query('DELETE FROM contacts WHERE account_id = $1 OR contact_account_id = $1', [accountId]);
    await client.query('DELETE FROM group_members WHERE account_id = $1', [accountId]);
    await client.query('DELETE FROM backups WHERE account_id = $1', [accountId]);
    await client.query('DELETE FROM media_objects WHERE owner_account_id = $1', [accountId]);
    await client.query(
      `UPDATE accounts
       SET recovery_blob = NULL, totp_secret = NULL, totp_enabled_at = NULL, duress_code_hash = NULL
       WHERE id = $1`,
      [accountId],
    );
  });
}

/** Soft-deletes the account and hard-deletes everything attached to it. */
export async function deleteAccount(accountId: string): Promise<void> {
  await wipeAccount(accountId);
  await pool.query(
    // Free the username by scoping it to the tombstone, so it can be reclaimed.
    `UPDATE accounts
     SET deleted_at = now(),
         username = left('deleted.' || replace(id::text, '-', ''), 32),
         display_name = NULL,
         password_hash = ''
     WHERE id = $1`,
    [accountId],
  );
}

export async function setPassword(accountId: string, password: string): Promise<void> {
  await pool.query('UPDATE accounts SET password_hash = $2 WHERE id = $1', [
    accountId,
    await hashSecret(password),
  ]);
}

export async function setDuressCode(accountId: string, duressCode: string | null): Promise<void> {
  await pool.query('UPDATE accounts SET duress_code_hash = $2 WHERE id = $1', [
    accountId,
    duressCode === null ? null : await hashSecret(duressCode),
  ]);
}

export async function matchesDuressCode(account: AccountRow, candidate: string): Promise<boolean> {
  if (!account.duress_code_hash) return false;
  return verifySecret(account.duress_code_hash, candidate);
}

export function publicProfile(account: AccountRow) {
  return {
    id: account.id,
    username: account.username,
    displayName: account.display_name,
    // A pointer to ciphertext. Without the owner's profile key it opens nothing.
    avatarMediaId: account.avatar_media_id,
    avatarUpdatedAt: account.avatar_updated_at?.toISOString() ?? null,
  };
}
