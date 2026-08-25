-- Privio core schema.
--
-- Design rule: the server stores routing metadata and opaque ciphertext only.
-- Every column that could carry user content (message bodies, group names,
-- media, backups) is a bytea blob that was sealed on a client device.

CREATE TABLE accounts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Usernames are normalised to lowercase by the API before they get here.
  username          text NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_.]{3,32}$'),
  display_name      text,
  password_hash     text NOT NULL,
  -- TOTP secret for optional two-factor auth.
  totp_secret       text,
  totp_enabled_at   timestamptz,
  -- Entering this code instead of the password wipes the account (see docs/security-model.md).
  wipe_code_hash    text,
  -- Client-encrypted blob that lets a user restore their identity from a recovery key.
  recovery_blob     bytea,
  privacy           jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),
  last_seen_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE TABLE devices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id      uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name            text NOT NULL,
  platform        text NOT NULL CHECK (platform IN ('ios', 'android', 'desktop', 'web')),
  -- Signal-protocol registration id and long-term identity public key.
  registration_id integer NOT NULL,
  identity_key    bytea NOT NULL,
  push_provider   text CHECK (push_provider IN ('apns', 'fcm')),
  push_token      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  revoked_at      timestamptz
);
CREATE INDEX devices_account_idx ON devices (account_id) WHERE revoked_at IS NULL;

CREATE TABLE sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_id     uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  -- SHA-256 of the bearer token. The token itself is never stored.
  token_hash    bytea NOT NULL UNIQUE,
  user_agent    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz
);
CREATE INDEX sessions_account_idx ON sessions (account_id);

-- X3DH key material. Public keys only; private halves never leave the device.
CREATE TABLE signed_prekeys (
  device_id   uuid PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  key_id      integer NOT NULL,
  public_key  bytea NOT NULL,
  signature   bytea NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE one_time_prekeys (
  device_id   uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  key_id      integer NOT NULL,
  public_key  bytea NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, key_id)
);

CREATE TABLE contacts (
  account_id          uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  contact_account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  alias               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, contact_account_id),
  CHECK (account_id <> contact_account_id)
);

CREATE TABLE blocks (
  account_id          uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  blocked_account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, blocked_account_id),
  CHECK (account_id <> blocked_account_id)
);

-- Groups: the server knows who is a member (it has to fan out envelopes) but
-- the group name, avatar and every message stay encrypted client-side.
CREATE TABLE groups (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  encrypted_metadata bytea,
  created_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);

CREATE TABLE group_members (
  group_id    uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  added_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX group_members_account_idx ON group_members (account_id);

-- Per-device delivery queue. Rows are deleted once the device acknowledges them.
CREATE TABLE envelopes (
  id                  bigserial PRIMARY KEY,
  recipient_device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  sender_account_id   uuid REFERENCES accounts(id) ON DELETE SET NULL,
  sender_device_id    uuid REFERENCES devices(id) ON DELETE SET NULL,
  group_id            uuid REFERENCES groups(id) ON DELETE CASCADE,
  envelope_type       text NOT NULL CHECK (envelope_type IN ('prekey', 'ciphertext', 'receipt', 'typing', 'key_change', 'group_update', 'call_signal')),
  content             bytea NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX envelopes_recipient_idx ON envelopes (recipient_device_id, id);

-- Client-encrypted attachments. The server sees length and an upload owner.
CREATE TABLE media_objects (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  byte_size         bigint NOT NULL,
  storage_key       text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  expires_at        timestamptz NOT NULL
);
CREATE INDEX media_expiry_idx ON media_objects (expires_at);

-- Client-encrypted account backups, sealed with a recovery key the server never sees.
CREATE TABLE backups (
  account_id  uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  storage_key text NOT NULL,
  byte_size   bigint NOT NULL,
  version     integer NOT NULL DEFAULT 1,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
