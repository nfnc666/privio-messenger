-- A picture for a channel.
--
-- Two paths, and they are the same two the rest of a channel already has.
--
-- A **public** channel's title, description and handle are plaintext because
-- discovery cannot search ciphertext. Its picture is the same kind of thing: it
-- is shown to strangers on the invite page, it is the image a messenger draws
-- in a link preview, and it is how somebody recognises the channel in a list of
-- search results. Sealing it would mean a public channel with no picture
-- anywhere it is actually being looked for. So it is stored unsealed, as a
-- media object of its own kind, and served to anyone.
--
-- A **private** channel's picture is sealed with the channel key, like its
-- title and its posts. The server holds ciphertext and a length. The capability
-- to download it travels inside `encrypted_metadata` beside the title — which
-- is already sealed with the channel key and already re-sealed on every
-- rotation, so the picture follows the name without a second mechanism.
--
-- The column is the same either way; what differs is what the bytes behind it
-- are. That is deliberate: a screen asking "does this channel have a picture"
-- should not have to ask which kind of channel it is first.

ALTER TABLE channels
  -- Nulled rather than cascaded when the media object goes, so a channel whose
  -- picture was swept up by retention is a channel with no picture rather than
  -- a channel that vanished.
  ADD COLUMN avatar_media_id  uuid REFERENCES media_objects(id) ON DELETE SET NULL,
  -- What a cache keys off. Without it, replacing a picture leaves every device
  -- showing the old one until something else happens to evict it.
  ADD COLUMN avatar_updated_at timestamptz;

-- The kind that says "this one is meant to be seen by people who are not
-- members". `media_objects.kind` already decides who may download; this adds
-- the third answer, and migration 012's rules are where it is enforced.
ALTER TABLE media_objects DROP CONSTRAINT media_kind_known;

ALTER TABLE media_objects
  ADD CONSTRAINT media_kind_known
  CHECK (kind IN ('attachment', 'avatar', 'channel_avatar'));
