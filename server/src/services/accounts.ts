import { pool, withTransaction } from '../db/pool.js';
import type { BlobStorage } from './storage.js';
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
 *
 * [storage] is not optional in spirit: deleting the rows that name the
 * attachments and the backup, and leaving the files, is worse than deleting
 * neither. The retention sweeper finds expired attachments through
 * `media_objects.expires_at`, so a blob whose row is gone is a blob nothing
 * will ever reach again — it stays until the disk is thrown away. Under a
 * duress code, where the whole promise is that the content is gone, that is the
 * one outcome that must not happen.
 */
export async function wipeAccount(accountId: string, storage: BlobStorage): Promise<void> {
  const orphaned: string[] = [];
  await withTransaction(async (client) => {
    // Envelopes, sessions and prekeys cascade from devices.
    await client.query('DELETE FROM devices WHERE account_id = $1', [accountId]);
    await client.query('DELETE FROM envelopes WHERE sender_account_id = $1', [accountId]);
    await client.query('DELETE FROM contacts WHERE account_id = $1 OR contact_account_id = $1', [accountId]);
    await client.query('DELETE FROM group_members WHERE account_id = $1', [accountId]);
    const { rows: backups } = await client.query<{ storage_key: string }>(
      'DELETE FROM backups WHERE account_id = $1 RETURNING storage_key',
      [accountId],
    );
    const { rows: media } = await client.query<{ storage_key: string }>(
      'DELETE FROM media_objects WHERE owner_account_id = $1 RETURNING storage_key',
      [accountId],
    );
    orphaned.push(...[...backups, ...media].map((r) => r.storage_key));
    await client.query(
      `UPDATE accounts
       SET recovery_blob = NULL, totp_secret = NULL, totp_enabled_at = NULL, duress_code_hash = NULL
       WHERE id = $1`,
      [accountId],
    );
  });

  // After the commit, never inside it: a transaction that rolled back after the
  // files were gone would leave rows pointing at nothing, which is the same
  // problem facing the other way. One file that will not delete must not stop
  // the rest — a wipe half-done is worse than a wipe with one file left.
  await Promise.all(orphaned.map((key) => storage.delete(key).catch(() => {})));
}

/** Soft-deletes the account and hard-deletes everything attached to it. */
export async function deleteAccount(accountId: string, storage: BlobStorage): Promise<void> {
  await wipeAccount(accountId, storage);
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
