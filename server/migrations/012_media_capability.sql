-- Who may download an attachment.
--
-- `GET /v1/media/:id` checked that the caller was signed in and then threw the
-- account away, so any account that learned an id could fetch the ciphertext of
-- anybody's attachment. The bytes are sealed under a key the server never has,
-- so nothing was readable — but existence, exact size and a copy of the
-- ciphertext all leaked, and harvested ciphertext keeps.
--
-- The fix is a capability rather than a recipient list: the server cannot know
-- who a message was sent to without being told, and telling it would hand it
-- exactly the metadata this design refuses to hold. The uploader gets an
-- unguessable token, puts it inside the sealed payload next to the media key,
-- and whoever can open the message can fetch the blob.
--
-- Only the hash is stored, for the same reason a password is: a dump of this
-- table must not be a set of download tokens.
ALTER TABLE media_objects ADD COLUMN download_token_hash bytea;

-- Avatars are the other kind. Their id is published to contacts, so a token
-- there would be published with it and buy nothing; they are authorised by the
-- contact list instead.
ALTER TABLE media_objects ADD COLUMN kind text NOT NULL DEFAULT 'attachment';
ALTER TABLE media_objects ADD CONSTRAINT media_kind_known CHECK (kind IN ('attachment', 'avatar'));

-- Rows uploaded before this migration have no token and are attachments, so
-- nothing can present one for them. They expire on their own schedule; a
-- pre-release server has nothing else worth keeping here.
