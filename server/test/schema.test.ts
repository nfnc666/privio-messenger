import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { closePool, createHarness, type TestHarness } from './helpers.js';

/**
 * What the server is allowed to be able to read.
 *
 * Every free-text column in the schema, each with the reason it is not sealed.
 * The list is the point: adding a column that holds something a person typed is
 * easy, reviewing a migration and noticing is not, and a plaintext column that
 * nobody argued for is how a messenger ends up knowing more than it says. A new
 * one fails this test until it is either sealed or written down here.
 */
const READABLE: Record<string, string> = {
  // Identity, deliberately public: this is how people find each other.
  'accounts.username': 'the handle others look up',
  'accounts.display_name': 'shown to anyone who can look the account up',

  // Credentials. Hashes, not secrets — and the two that are secrets are sealed
  // under a key held outside the database (see "Two-factor secrets").
  'accounts.password_hash': 'Argon2id digest',
  'accounts.totp_secret': 'sealed under TOTP_SECRET_KEY before it gets here',
  'accounts.duress_code_hash': 'Argon2id digest',
  'accounts.privacy': 'the account s own switches, which the server enforces',

  // Capabilities and pointers. None of them says anything about content.
  'backups.storage_key': 'where the sealed blob is, not what is in it',
  'media_objects.storage_key': 'same',
  'media_objects.kind': 'attachment or avatar, which decides who may download it',
  'channels.invite_code': 'the capability in a link, meant to be shared',
  'groups.invite_code': 'the same',
  'sent_message_keys.idempotency_key': 'opaque to the server; it is compared, never read',
  'schema_migrations.name': 'not user data',

  // Enumerations the server acts on.
  'channels.visibility': 'decides whether it is listed at all',
  'channel_members.role': 'enforced by the server',
  'group_members.role': 'the same',
  'envelopes.envelope_type': 'prekey or ciphertext — which cipher opens it',
  'key_requests.scope': 'group or channel',

  // A public channel is discoverable, and search cannot run over ciphertext.
  // This is the one place content-adjacent text is deliberately readable, and
  // it applies to public channels only: a private one seals its title.
  'channels.handle': 'how a public channel is linked to and found',
  'channels.title': 'public channels are searchable by name',
  'channels.description': 'the same',
  'channels.category': 'the same',

  // Devices. A push token is an address the server posts to, so it cannot be
  // sealed; the rest is what the connected-devices screen shows.
  'devices.name': 'shown in the device list',
  'devices.platform': 'shown in the device list',
  'devices.push_provider': 'which service to wake',
  'devices.push_token': 'an address this server sends to; sealing it would break it',
  'sessions.user_agent': 'shown beside the session in the device list',

  // Licensing, which is an order record rather than anything about a person.
  'licenses.source': 'key, apple or google',
  'licenses.status': 'active or revoked',
  'licenses.payment_provider': 'the order this license was issued for',
  'licenses.payment_reference': 'the same',

};

describe('what the server can read', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('has no free-text column that nobody argued for', async () => {
    const { rows } = await pool.query<{ name: string }>(
      `SELECT table_name || '.' || column_name AS name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND data_type IN ('text', 'character varying', 'json', 'jsonb')
        ORDER BY table_name, ordinal_position`,
    );
    const unexplained = rows.map((r) => r.name).filter((name) => !(name in READABLE));
    assert.deepEqual(
      unexplained,
      [],
      'a new readable column: seal it, or add it to READABLE with the reason',
    );
  });

  it('keeps every message-bearing column opaque', async () => {
    // The columns that carry what people actually said. If any of these ever
    // stops being bytea, the central claim has quietly changed.
    const sealed = [
      ['envelopes', 'content'],
      ['channel_posts', 'content'],
      ['groups', 'encrypted_metadata'],
      ['channels', 'encrypted_metadata'],
      ['accounts', 'recovery_blob'],
    ];
    for (const [table, column] of sealed) {
      const { rows } = await pool.query<{ data_type: string }>(
        `SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2`,
        [table, column],
      );
      assert.equal(rows[0]?.data_type, 'bytea', `${table}.${column} must stay opaque`);
    }
  });

  it('stores no session token or license key, only digests', async () => {
    for (const [table, column] of [
      ['sessions', 'token_hash'],
      ['licenses', 'key_hash'],
      ['media_objects', 'download_token_hash'],
    ]) {
      const { rows } = await pool.query<{ data_type: string }>(
        `SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2`,
        [table, column],
      );
      assert.equal(rows[0]?.data_type, 'bytea', `${table}.${column} holds a digest`);
    }
  });
});
