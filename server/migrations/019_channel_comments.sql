-- Comments under a channel post, and being barred from writing them.
--
-- Off by default, and per channel. A channel is a broadcast; turning its posts
-- into threads changes what the thing is, and that is the owner's decision to
-- make rather than a default somebody discovers when the first argument breaks
-- out under a post.
--
-- A comment is sealed exactly like a post: same channel key, same epoch, same
-- refusal under a superseded one. The server stores ciphertext and cannot read
-- a word of it — which is also why moderation here can only ever be "remove
-- this row" and "stop this account writing more". There is no filtering a
-- server cannot read, and a channel that promised one would be promising
-- something it would have to break encryption to deliver.
--
-- What is readable, as everywhere else in a channel: who wrote it and when.
-- The author id has to be, or an admin could not remove one person's comments
-- and the thread could not say who is speaking.

ALTER TABLE channels
  -- Not a capability an admin holds but a shape the channel has, so it sits
  -- here rather than in channel_members.
  ADD COLUMN comments_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE channel_post_comments (
  id                bigserial   PRIMARY KEY,
  post_id           bigint      NOT NULL REFERENCES channel_posts(id) ON DELETE CASCADE,

  -- Nulled rather than cascaded when an account goes: the thread keeps its
  -- shape, and the comment shows as from a deleted account instead of the
  -- replies around it losing their context.
  author_account_id uuid        REFERENCES accounts(id) ON DELETE SET NULL,

  -- Sealed with the channel key. The server has no key for this column.
  content           bytea       NOT NULL,

  -- Which version sealed it, so a reader knows what to open it with — and so
  -- the server can refuse one written under a key somebody was removed from.
  key_epoch         integer     NOT NULL DEFAULT 1,

  created_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX channel_post_comments_thread_idx
  ON channel_post_comments (post_id, id)
  WHERE deleted_at IS NULL;

-- Barred from speaking, still able to read.
--
-- Deliberately not the same thing as being removed from the channel: removing
-- somebody rotates the key and cuts them off from everything, which is the
-- right answer to "should not be here" and much too heavy an answer to "will
-- not stop arguing under every post". This bars the voice and leaves the
-- reading, and it covers reactions as well as comments — a reaction is a way of
-- speaking too, and an admin who silenced somebody would not expect them to go
-- on stamping emojis on every post.
CREATE TABLE channel_bans (
  channel_id uuid        NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  account_id uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- Who did it. Kept because an admin acting on another admin's decision
  -- should be able to see whose it was.
  banned_by  uuid        REFERENCES accounts(id) ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel_id, account_id)
);
