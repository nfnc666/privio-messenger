-- Unread markers, and making a channel post actually notify anybody.

-- 1. How far each account has read, per channel.
--
-- Per account rather than per device, and stored here rather than locally, so
-- reading a channel on a phone clears the badge on a laptop. That is the whole
-- reason it is not a local number.
--
-- `last_read_post_id` only ever moves forward — see the route. A device that
-- has been offline holds a stale idea of where the reader got to, and letting
-- it write that back would mark things unread that somebody has already seen.
CREATE TABLE channel_reads (
  account_id        uuid   NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel_id        uuid   NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  last_read_post_id bigint NOT NULL,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, channel_id)
);

-- 2. Whether a post has already raised a notification.
--
-- Set the moment one goes out, so nothing is notified twice: not by a retry,
-- not by a restart, and not by the sweeper below passing over the same row.
--
-- **This is the column that revisits migration 018.** That migration made
-- scheduled posts work with no queue and no worker: a post becomes visible
-- because time passed, not because a process woke up, so nothing can fall over
-- at three in the morning and leave a channel silent. It said, in as many
-- words, that this holds *only* while publishing raises no push — and that if
-- one ever did, the decision would have to be revisited.
--
-- It is revisited here, and the good property is kept. Visibility still needs
-- no worker: `publish_at` in the past is all it takes. Only the *notification*
-- needs something to happen at a moment, so a sweeper sends the ones that came
-- due. If that sweeper dies, a scheduled post still publishes on time and the
-- only thing lost is the push — which is the right thing to lose, and is
-- exactly the failure mode 018 was protecting against, one notch smaller.
ALTER TABLE channel_posts ADD COLUMN notified_at timestamptz;

-- The sweeper's query: published, due, and not yet notified. Partial, because
-- the interesting rows are a vanishing fraction of the table and stop being
-- interesting the moment they are notified.
CREATE INDEX channel_posts_pending_notification_idx
  ON channel_posts (publish_at)
  WHERE notified_at IS NULL AND deleted_at IS NULL;
