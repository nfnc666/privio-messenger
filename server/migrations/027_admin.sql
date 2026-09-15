-- Operators.
--
-- WHAT AN ADMIN IS AND IS NOT, said here because every screen built on these
-- tables has to say it too.
--
-- The one rule does not bend for staff: the server holds no key that opens a
-- message, so neither does an operator. There is no column below that could
-- carry plaintext content, no route in `routes/admin.ts` that reads an
-- envelope, a backup, a media blob or a private channel's title, and no way to
-- act as an account. What an operator can see is what the server already had to
-- know in order to route bytes — a username, when a device last checked in, how
-- many rows are queued — plus the plaintext a *public* channel publishes on
-- purpose so that it can be searched for.
--
-- That is a deliberately small surface, and it is small for the same reason the
-- rest of the schema is: capability that exists gets used, subpoenaed, and
-- stolen. An admin account is the most valuable credential on the server
-- precisely because it is the only one that sees across accounts, so it gets
-- its own table rather than a flag on `accounts` — a staff member's own Privio
-- account and their operator login are different credentials, revoked
-- separately, and compromising one does not hand over the other.

CREATE TABLE admin_users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Not a Privio username and not in the same namespace: this is a login for
  -- the panel, and an operator who also uses the messenger has two identities
  -- on purpose.
  username        text NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_.-]{3,32}$'),
  display_name    text,

  -- Argon2id, same parameters as an account password. Never a shared secret,
  -- never recoverable: a forgotten operator password is a new operator row made
  -- by somebody who still has one, which is also the only recovery path there
  -- should be for a credential this strong.
  password_hash   text NOT NULL,

  -- Sealed exactly as an account's is, by `services/totp.ts`. Nullable because
  -- the bootstrap admin is created before anyone can scan a QR code, and
  -- `totp_enabled_at` is what the login actually checks.
  totp_secret     text,
  totp_enabled_at timestamptz,

  -- What this operator may do. Enforced in `routes/admin.ts`, listed here so
  -- the set is visible from the schema:
  --   owner    — everything, including creating and disabling other operators
  --   admin    — moderation and licensing, but cannot touch operator accounts
  --   support  — licensing and lookups; cannot suspend a channel
  --   viewer   — reads only; every write is refused
  -- A new role must be added here *and* in ADMIN_ROLES, or the check fails
  -- closed, which is the right direction for a permission bug.
  role            text NOT NULL DEFAULT 'viewer'
                    CHECK (role IN ('owner', 'admin', 'support', 'viewer')),

  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  last_login_at   timestamptz,

  -- Disabled rather than deleted. The audit log references this row, and an
  -- audit trail whose actors can be erased is not an audit trail.
  disabled_at     timestamptz
);

-- Operator sessions.
--
-- Deliberately short-lived compared with an account session, which lasts a
-- year: a phone in someone's pocket staying signed in is the feature, a browser
-- tab on a shared workstation staying signed in is the incident. The panel
-- re-authenticates rather than silently refreshing.
CREATE TABLE admin_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,

  -- SHA-256 of the bearer token, as everywhere else. The token itself is never
  -- stored, so a database leak does not hand over live operator sessions.
  token_hash    bytea NOT NULL UNIQUE,

  -- Recorded because "where was this session used from" is the first question
  -- asked about an operator action that looks wrong.
  ip            inet,
  user_agent    text,

  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz
);
CREATE INDEX admin_sessions_user_idx ON admin_sessions (admin_user_id)
  WHERE revoked_at IS NULL;

-- Every operator action, append-only.
--
-- There is no UPDATE or DELETE path to this table anywhere in the server, and
-- the panel offers no way to clear it. A log an operator can edit records
-- nothing about the operator, which is the only party it exists to record.
--
-- `actor_username` duplicates what `admin_user_id` already points at. That
-- denormalisation is on purpose: an operator can be renamed, and the log has to
-- read as what was true when the action happened rather than what is true now.
CREATE TABLE admin_audit_log (
  id             bigserial   PRIMARY KEY,

  -- Nulled rather than cascaded, for the same reason the transfer record is:
  -- the action outlives the account that took it.
  admin_user_id  uuid        REFERENCES admin_users(id) ON DELETE SET NULL,
  actor_username text        NOT NULL,

  -- Dotted and stable (`license.revoke`, `channel.suspend`, `admin.disable`).
  -- Stable because alerting keys off it.
  action         text        NOT NULL,

  -- What it was done to. `target_id` is text rather than uuid because a target
  -- is sometimes an order reference or a handle, and a log that cannot record
  -- the odd target records it as nothing at all.
  target_type    text,
  target_id      text,

  -- Room for the shape of the action — which reason, which fields changed.
  -- MUST NOT carry user content: nothing that reaches this column is allowed to
  -- come from a message, a post, a backup or a private channel's metadata. The
  -- writers in `services/admin_audit.ts` are the enforcement of that, and there
  -- is exactly one of them so the rule has one place to be checked.
  detail         jsonb       NOT NULL DEFAULT '{}'::jsonb,

  ip             inet,
  at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_log_at_idx ON admin_audit_log (at DESC);
CREATE INDEX admin_audit_log_actor_idx ON admin_audit_log (admin_user_id, at DESC);
CREATE INDEX admin_audit_log_target_idx ON admin_audit_log (target_type, target_id, at DESC);

-- Taking a public channel out of discovery.
--
-- The narrowest action that answers a report, and the only moderation action
-- the server is *able* to take honestly. It does not delete posts — the server
-- cannot read them to know what it would be deleting — and it does not touch
-- the members who already hold the channel key. A suspended channel stops being
-- listed, stops resolving by handle, and stops being reachable by invite code;
-- everyone already in it keeps what they already had, because there is no
-- mechanism by which they could not.
--
-- Public only. A private channel is not discoverable in the first place, so
-- suspending it would remove nothing while claiming to have acted.
ALTER TABLE channels
  ADD COLUMN suspended_at     timestamptz,
  ADD COLUMN suspended_reason text CHECK (
    suspended_reason IS NULL OR suspended_reason IN ('spam', 'abuse', 'illegal', 'impersonation', 'other')
  ),
  ADD CONSTRAINT channels_suspension_consistent
    CHECK ((suspended_at IS NULL) = (suspended_reason IS NULL));

COMMENT ON COLUMN channels.suspended_at IS
  'Public channel removed from discovery by an operator. Members keep access; no post is touched.';

-- The discovery index carried `WHERE visibility = 'public' AND deleted_at IS
-- NULL`, which no longer matches what discovery asks — every listing query now
-- also excludes suspended rows, and a partial index whose predicate is broader
-- than the query still gets used but scans the suspended rows to throw them
-- away. Replaced rather than added to, so there is one index for one query.
DROP INDEX IF EXISTS channels_discovery_idx;
CREATE INDEX channels_discovery_idx ON channels (visibility, category, member_count DESC)
  WHERE visibility = 'public' AND deleted_at IS NULL AND suspended_at IS NULL;

-- Marking a report as dealt with.
--
-- The queue an operator works is "channels with reports nobody has looked at",
-- not "reports". Reviewing is therefore per channel and closes every standing
-- report on it at once: they are all the same signal about the same channel,
-- and leaving nine of them open after acting on the tenth would show the
-- channel back in the queue for a decision that was already made.
--
-- Clearing a channel does not delete the reports. Somebody reported it, that
-- happened, and the next operator to look deserves to know it happened before
-- and was judged fine.
ALTER TABLE channel_reports
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN reviewed_by uuid REFERENCES admin_users(id) ON DELETE SET NULL;

CREATE INDEX channel_reports_open_idx ON channel_reports (channel_id)
  WHERE reviewed_at IS NULL;
