-- Channels: one author, many readers.
--
-- The difference from a group is not the size but the direction. A group message
-- is sealed once per member device; a channel post is sealed once, under a
-- channel key, and read by everyone who holds it. That is what makes a channel
-- cheap, and it is also why a member who leaves keeps whatever they already had.
--
-- Public channels are discoverable, which forces a decision: search cannot work
-- over ciphertext, so the title, description and category of a public channel
-- are plaintext here — deliberately, and only those. The posts are not. A
-- private channel keeps even its title sealed, the way a group does.

CREATE TABLE channels (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  visibility          text NOT NULL CHECK (visibility IN ('public', 'private')),

  -- Public only. The handle is how a channel is linked to and found.
  handle              text UNIQUE CHECK (handle ~ '^[a-z0-9_.]{3,32}$'),
  title               text,
  description         text,
  category            text,

  -- Private only: the title, sealed with the channel key.
  encrypted_metadata  bytea,

  -- Identifies the channel in an invite link. The key that opens its posts is
  -- NOT here and never reaches the server; see 006_join_links.sql for how it
  -- gets to a new member instead.
  invite_code         text NOT NULL UNIQUE,

  -- A hint the client honours, not a control the server can enforce. Anyone who
  -- can read a post can copy it; see docs/security-model.md.
  restrict_saving     boolean NOT NULL DEFAULT false,

  member_count        integer NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz,

  CONSTRAINT public_channels_are_named CHECK (
    visibility <> 'public' OR (handle IS NOT NULL AND title IS NOT NULL)
  )
);

CREATE INDEX channels_discovery_idx ON channels (visibility, category, member_count DESC)
  WHERE visibility = 'public' AND deleted_at IS NULL;

CREATE TABLE channel_members (
  channel_id  uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'subscriber' CHECK (role IN ('owner', 'admin', 'subscriber')),
  joined_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel_id, account_id)
);
CREATE INDEX channel_members_account_idx ON channel_members (account_id);

CREATE TABLE channel_posts (
  id                bigserial PRIMARY KEY,
  channel_id        uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  author_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,

  -- Sealed with the channel key. The server has no key for this column.
  content           bytea NOT NULL,

  -- Attachments are ordinary encrypted media objects, keyed inside the post.
  media_id          uuid REFERENCES media_objects(id) ON DELETE SET NULL,

  pinned            boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);
CREATE INDEX channel_posts_feed_idx ON channel_posts (channel_id, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX channel_posts_pinned_idx ON channel_posts (channel_id) WHERE pinned AND deleted_at IS NULL;
