-- Profile pictures.
--
-- The avatar is an ordinary encrypted media object: the server holds ciphertext
-- and a pointer to it, and never the key. What is new here is only that the
-- pointer lives on the account, so a contact can find it.

ALTER TABLE accounts
  ADD COLUMN avatar_media_id uuid REFERENCES media_objects(id) ON DELETE SET NULL,
  ADD COLUMN avatar_updated_at timestamptz;

-- An avatar is not a message attachment and must not be swept away after the
-- attachment retention window; it lives as long as it is someone's picture.
CREATE INDEX media_avatar_idx ON accounts (avatar_media_id) WHERE avatar_media_id IS NOT NULL;
