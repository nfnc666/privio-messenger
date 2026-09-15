-- Editing a post, and publishing one later.
--
-- Both are one column, and neither needs a background job.
--
-- A scheduled post is an ordinary row whose `publish_at` is in the future, and
-- the feed simply does not select it yet. There is no sweeper, no queue and no
-- worker that can fall over at three in the morning and leave a channel silent:
-- the post becomes visible because time passed, not because a process woke up.
-- That works here only because publishing a channel post raises no push — if it
-- ever does, this is the design decision that has to be revisited, because a
-- notification is something that must actually be *sent* at a moment.
--
-- `edited_at` is set only when a post that people have already seen changes.
-- Editing something still scheduled leaves it unmarked: nobody read the earlier
-- version, so there is nothing to disclose.

ALTER TABLE channel_posts
  ADD COLUMN edited_at  timestamptz,
  -- NULL means "already published", which is what every existing row is.
  ADD COLUMN publish_at timestamptz;

-- The author's own scheduled list, which is the only query that asks for these.
CREATE INDEX channel_posts_scheduled_idx
  ON channel_posts (channel_id, publish_at)
  WHERE publish_at IS NOT NULL AND deleted_at IS NULL;
