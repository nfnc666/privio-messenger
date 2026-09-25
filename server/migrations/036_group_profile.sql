-- A picture and a description for a group.
--
-- The two are stored differently, and the difference is the whole design.
--
-- **The description is sealed**, with the group key, exactly like the name.
-- A group has no public side at all: it is not discoverable, has no handle and
-- no invite page a stranger reads. So there is no reason its text should be
-- readable here, and every reason it should not be — a sentence describing what
-- a group is for says as much about the people in it as the name does.
--
-- It goes in a **column of its own** rather than into `encrypted_metadata`
-- beside the name. That blob is the UTF-8 name and nothing else, and an older
-- build opens it and shows whatever comes out. Packing two fields into it would
-- make every group on an older build display its own JSON as its name — the
-- most visible string in the app, broken for anybody who had not updated. A
-- second column costs one migration and breaks nothing.
--
-- **The picture is not sealed**, and that is the same answer migration 023 gave
-- for a channel's. A picture is a label on a door rather than a message: it
-- has to be drawable the moment the group is on screen, including before the
-- group key has arrived from another member, and it must not be lost to a key
-- rotation that raced the upload. What replaces encryption is an ownership
-- check rather than nothing — `mayDownload` hands a `group_avatar` only to
-- members of the group that points at it. The messages stay end-to-end
-- encrypted; the picture on the door does not, and this file is where that is
-- written down rather than discovered later.

ALTER TABLE groups
  -- Sealed with the group key, like `encrypted_metadata`. The server holds
  -- ciphertext and a length.
  ADD COLUMN encrypted_description bytea,
  -- Nulled rather than cascaded when the media object goes, so a group whose
  -- picture was swept up by retention is a group with no picture rather than a
  -- group that vanished.
  ADD COLUMN avatar_media_id uuid REFERENCES media_objects(id) ON DELETE SET NULL,
  -- What a cache keys off. Without it, replacing a picture leaves every device
  -- showing the old one until something else happens to evict it.
  ADD COLUMN avatar_updated_at timestamptz;

-- The fifth kind. `media_objects.kind` already decides who may download; this
-- adds the answer "the members of the group that points at it".
--
-- The list is rewritten whole, which is how this constraint has always been
-- changed — and is exactly why `'sticker'` is spelled out here. It was added by
-- migration 028, after `'channel_avatar'` in 023, so anybody copying 023's list
-- forward drops it and every sticker upload starts failing on a check
-- constraint. It happened while writing this file; the suite caught it.
ALTER TABLE media_objects DROP CONSTRAINT media_kind_known;

ALTER TABLE media_objects
  ADD CONSTRAINT media_kind_known
  CHECK (kind IN ('attachment', 'avatar', 'channel_avatar', 'sticker', 'group_avatar'));
