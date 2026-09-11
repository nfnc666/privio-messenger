-- What a channel profile needs that the schema did not hold yet.
--
-- Four things, and they are separate because they answer to different rules.

-- 1. Finer permissions.
--
-- There were five flags and they bundled decisions that are not the same
-- decision: "manage members" meant removing a subscriber *and* handing someone
-- else the power to remove you, and moderating a discussion was not a
-- permission at all — it fell out of "delete posts", which is a different act
-- on different content.
--
-- Splitting them is only safe because `withinAuthority` iterates over whatever
-- keys exist rather than a hardcoded list: nobody can grant a flag they do not
-- hold, including the new ones, without another line of code.
--
-- They default to false. An existing admin therefore keeps exactly what they
-- had and gains nothing by this migration, which is the correct direction for a
-- permission change to fail in. The owner is unaffected: their authority is not
-- stored, it is `OWNER_PERMISSIONS`.
ALTER TABLE channel_members
  ADD COLUMN can_moderate_discussion boolean NOT NULL DEFAULT false,
  ADD COLUMN can_manage_invites      boolean NOT NULL DEFAULT false,
  ADD COLUMN can_manage_livestreams  boolean NOT NULL DEFAULT false,
  -- Deliberately not implied by can_manage_members. An admin who may remove a
  -- spammer should not thereby be able to appoint a second admin who can remove
  -- them back.
  ADD COLUMN can_appoint_admins      boolean NOT NULL DEFAULT false,
  -- "promoted by NFNC", which the admin list shows. Nulled rather than cascaded
  -- when that account goes, so the row survives as "promoted by a deleted
  -- account" instead of the promotion disappearing.
  ADD COLUMN promoted_by uuid REFERENCES accounts(id) ON DELETE SET NULL;

-- Every existing admin was promoted by the owner, because until now there was
-- no other way for one to exist. Recorded rather than left null so the list
-- does not read "promoted by nobody" for every admin a channel already has.
UPDATE channel_members m
   SET promoted_by = c.owner_account_id
  FROM channels c
 WHERE c.id = m.channel_id
   AND m.role = 'admin'
   AND m.promoted_by IS NULL;

-- 2. Channel settings the profile screen offers.
ALTER TABLE channels
  -- Whether a post carries its author's name. Off by default: a channel speaks
  -- with one voice unless somebody decides otherwise, and turning it on is a
  -- decision about other people's names as well as your own.
  ADD COLUMN show_sender_name boolean NOT NULL DEFAULT false,
  -- Shown once to somebody who has just joined. Plaintext here only for a
  -- public channel, whose title and description are already plaintext for the
  -- same reason — a private channel's rides inside `encrypted_metadata` with
  -- its title, sealed under the channel key and re-sealed on rotation.
  ADD COLUMN welcome_message text,
  ADD COLUMN welcome_enabled boolean NOT NULL DEFAULT false,
  -- The channel's own accent and background, as theme token names rather than
  -- free-form colour values: a channel cannot ask for white-on-white or for a
  -- colour that disappears in one of the two themes.
  ADD COLUMN accent_name text,
  ADD COLUMN background_name text,
  -- A group where a channel's posts are discussed, and where comments land.
  -- Nulled rather than cascaded: unlinking a deleted group must leave the
  -- channel standing.
  ADD COLUMN discussion_group_id uuid REFERENCES groups(id) ON DELETE SET NULL,
  -- Whether subscribers may write to the channel's own inbox.
  ADD COLUMN direct_messages_enabled boolean NOT NULL DEFAULT false,
  -- Whether a livestream is running, and who started it. Not a table: a channel
  -- has at most one at a time, and a history of past streams is a record of
  -- when people were present that nothing here needs.
  ADD COLUMN live_started_at timestamptz,
  ADD COLUMN live_started_by uuid REFERENCES accounts(id) ON DELETE SET NULL,
  ADD COLUMN live_room text;

ALTER TABLE channels
  ADD CONSTRAINT channels_accent_known
  CHECK (accent_name IS NULL OR accent_name IN ('green', 'blue', 'purple', 'orange', 'red', 'teal')),
  ADD CONSTRAINT channels_background_known
  CHECK (background_name IS NULL OR background_name IN ('black', 'charcoal', 'midnight'));

-- 3. Muting, per account and per channel.
--
-- A row per person who has muted something, rather than a column on membership:
-- most people mute nothing, and the push path asks "is this muted for this
-- account" on every fan-out, which wants an index rather than a wide table.
--
-- `until` null means muted with no end. A row whose `until` has passed is not
-- muted and is left to be cleaned up rather than deleted on read, so a read
-- path never writes.
CREATE TABLE channel_mutes (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel_id uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  until      timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, channel_id)
);

CREATE INDEX channel_mutes_channel_idx ON channel_mutes (channel_id);

-- 4. The channel's own inbox.
--
-- End-to-end encrypted like any other message: the server stores the sealed
-- bytes and which channel they were addressed to. `answered_at` is what an
-- admin sees as "handled"; nothing about the content is readable here.
CREATE TABLE channel_inbox (
  id          bigserial PRIMARY KEY,
  channel_id  uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  -- Who wrote it. Needed to reply, and to block somebody who is abusing it.
  sender_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  content     bytea NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  answered_at timestamptz
);

CREATE INDEX channel_inbox_channel_idx ON channel_inbox (channel_id, created_at DESC);
