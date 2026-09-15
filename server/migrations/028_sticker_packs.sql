-- Sticker and custom-emoji packs.
--
-- One table shape for both, distinguished by `kind`, because they are the same
-- object wearing two sizes: a named, ordered collection of small images that
-- somebody made, each with a standard emoji standing in for it. Splitting them
-- would mean two of every endpoint and two of every bug.

CREATE TABLE sticker_packs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('sticker', 'emoji')),
  title         text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 64),
  -- Private is the default and it is enforced here as well as in the route:
  -- a pack nobody shared is readable by its owner alone, and `share_code` is
  -- the only thing that ever makes it readable by somebody else.
  --
  -- Null means never shared. A revoked share sets it back to null rather than
  -- keeping the code with a flag, so a revoked link cannot be un-revoked by
  -- flipping a boolean and the old URL is dead for good.
  share_code    text UNIQUE CHECK (share_code IS NULL OR char_length(share_code) BETWEEN 8 AND 64),
  shared_at     timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE INDEX sticker_packs_owner_idx ON sticker_packs (owner_account_id) WHERE deleted_at IS NULL;

-- One image in a pack.
--
-- `media_id` points at an already-uploaded object of kind `sticker`, which the
-- media route has already checked the bytes of — see `services/image_header.ts`
-- for what "checked" means: the magic bytes, the dimensions and the size, read
-- out of the file rather than taken from what the client said it was.
CREATE TABLE sticker_items (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pack_id    uuid NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
  media_id   uuid NOT NULL REFERENCES media_objects(id) ON DELETE RESTRICT,
  -- The standard emoji that stands in for this image: what an older client
  -- shows, what a client without the pack shows, and what the picker searches.
  -- Required, because "a sensible fallback" cannot be optional.
  emoji      text NOT NULL CHECK (char_length(emoji) BETWEEN 1 AND 16),
  -- Sparse on purpose, so a reorder rewrites one row rather than all of them.
  position   integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pack_id, position) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX sticker_items_pack_idx ON sticker_items (pack_id, position);

-- Which packs an account has installed, and in what order they appear.
--
-- Separate from ownership: the pack you made is not automatically the pack you
-- use, and a pack somebody shared with you is installed without being yours.
-- Deleting your account takes your installs with it and leaves other people's
-- alone.
CREATE TABLE sticker_installs (
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  pack_id     uuid NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
  position    integer NOT NULL DEFAULT 0,
  installed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, pack_id)
);

-- Favourites and recents, per account.
--
-- Held on the server rather than only on the device, because the brief they
-- answer is "available again after signing out and back in" — a device-local
-- list is exactly what fails that. `used_at` doubles as both: a favourite is a
-- row with `favourite` set, a recent is the newest rows by `used_at`.
CREATE TABLE sticker_uses (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  item_id    uuid NOT NULL REFERENCES sticker_items(id) ON DELETE CASCADE,
  favourite  boolean NOT NULL DEFAULT false,
  used_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, item_id)
);

CREATE INDEX sticker_uses_recent_idx ON sticker_uses (account_id, used_at DESC);

-- The media kind a sticker upload is stored under.
--
-- Its own kind rather than `attachment`, because the rules differ: a sticker is
-- small, must be PNG or WebP, must be within a bounded pixel size, and must not
-- expire the way a message attachment does — a pack whose images were swept
-- away is a pack of empty squares.
ALTER TABLE media_objects DROP CONSTRAINT media_kind_known;

ALTER TABLE media_objects
  ADD CONSTRAINT media_kind_known
  CHECK (kind IN ('attachment', 'avatar', 'channel_avatar', 'sticker'));
