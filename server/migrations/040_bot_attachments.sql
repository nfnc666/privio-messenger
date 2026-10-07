-- Pictures and files a bot sends.
--
-- The honest part first: **these bytes are not encrypted.** Everything else on
-- the bot path is plaintext this server can read — migration 029 says why and
-- the app says so before the first message — and an attachment is no different.
-- It is stored as it arrives, so the operator of the bot and this server can
-- both open it. What would be dishonest is sealing it to look like the rest of
-- Privio while the bot holds the key anyway.
--
-- The narrow part: an id is not a download. `mayDownload` lets exactly one more
-- person than the uploader have it — the account a `bot_messages` row addressed
-- it to. Nobody who merely knows the id, nobody else in the group, and nobody
-- who stopped talking to the bot before it was sent.

-- Which object, if any. `ON DELETE SET NULL` rather than cascade: the retention
-- sweeper removes an expired blob and the message that carried it should stay
-- in the conversation as a message whose file is gone, not disappear.
ALTER TABLE bot_messages
  ADD COLUMN media_id uuid REFERENCES media_objects(id) ON DELETE SET NULL;

-- What to draw before the bytes are there: a picture gets an image frame, a
-- file gets a row with its name. Declared by the bot at upload and not trusted
-- any further than that — the app renders an image and falls back to a file row
-- when the bytes turn out not to be one.
ALTER TABLE bot_messages
  ADD COLUMN media_kind text CHECK (media_kind IS NULL OR media_kind IN ('image', 'file'));

-- The name to show and to save under. The bot's, not the server's.
ALTER TABLE bot_messages
  ADD COLUMN file_name text CHECK (file_name IS NULL OR char_length(file_name) <= 200);

-- An object always has a kind — otherwise there is nothing to draw it as.
--
-- Deliberately **not** `(media_id IS NULL) = (media_kind IS NULL)`, which is
-- what this said first and which made the retention sweeper unable to do its
-- job: `ON DELETE SET NULL` clears `media_id` and leaves the kind behind, so
-- deleting an expired blob failed on the constraint and the bytes stayed
-- forever. A test caught it.
--
-- So the surviving half is the half worth having, and the leftover kind is not
-- a defect: it is how the app knows to draw "this file is no longer on the
-- server" instead of silently dropping the message.
ALTER TABLE bot_messages ADD CONSTRAINT bot_messages_media_has_a_kind
  CHECK (media_id IS NULL OR media_kind IS NOT NULL);

CREATE INDEX bot_messages_media_idx ON bot_messages (media_id) WHERE media_id IS NOT NULL;

-- The new media kind.
--
-- Every existing value is spelled out again, which migration 036 learned the
-- hard way: that file copied 023's list forward, dropped `'sticker'` — added in
-- between by 028 — and every sticker upload started failing on the check. The
-- suite caught it. So this list is written out in full rather than assumed.
ALTER TABLE media_objects DROP CONSTRAINT media_kind_known;

ALTER TABLE media_objects
  ADD CONSTRAINT media_kind_known
  CHECK (kind IN (
    'attachment',
    'avatar',
    'channel_avatar',
    'sticker',
    'group_avatar',
    'bot_attachment'
  ));
