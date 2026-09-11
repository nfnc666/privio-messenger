-- What an invite link is allowed to do, and who gets to walk in on it.
--
-- One link per channel, as before, with three limits on it and a way to make
-- it stop working. Deliberately not a table of many links: a channel with six
-- live invites is six things to keep track of and six ways to be surprised,
-- and the thing people actually ask for is "this link is out there and I want
-- it dead", which is rotating the one code.
--
-- **Revoking is rotating.** A new code takes effect the moment it is written,
-- and every copy of the old one — in a message, on a poster, in somebody's
-- clipboard — stops resolving. There is no list of past codes and no grace
-- period: a link that still half-works is the thing being revoked.
--
-- The counter is honest about what it counts: joins through the link, not
-- clicks. Somebody who opens the link, looks at the preview and walks away has
-- not used it up.

ALTER TABLE channels
  -- NULL means it does not expire.
  ADD COLUMN invite_expires_at     timestamptz,
  -- NULL means no limit. Otherwise the link stops working once uses reaches it.
  ADD COLUMN invite_max_uses       integer CHECK (invite_max_uses IS NULL OR invite_max_uses > 0),
  ADD COLUMN invite_uses           integer NOT NULL DEFAULT 0,
  -- When on, the link puts people in a queue instead of in the channel.
  ADD COLUMN invite_needs_approval boolean NOT NULL DEFAULT false;

-- People who followed a link into a channel that asks first.
--
-- Not members: they hold no key, are sent nothing, and the channel does not
-- count them. What the row says is that somebody knocked — and it exists at all
-- so that an admin sees the knock, since the alternative is a link that
-- silently does nothing and a person who assumes it is broken.
CREATE TABLE channel_join_requests (
  channel_id   uuid        NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  account_id   uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel_id, account_id)
);

CREATE INDEX channel_join_requests_channel_idx
  ON channel_join_requests (channel_id, requested_at);
