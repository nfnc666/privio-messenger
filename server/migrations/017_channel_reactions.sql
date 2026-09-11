-- Reactions on channel posts.
--
-- WHAT THE SERVER LEARNS, stated plainly because it is more than it learns
-- about anything else in a channel: which account reacted to which post, with
-- which emoji, and when. The posts themselves stay sealed — this table says
-- nothing about what was reacted *to* — but "who responded to what" is real
-- metadata and it is held in the clear.
--
-- There is no version of this feature that avoids it. A count has to be
-- counted somewhere, and the one place every member can agree on is the
-- server; an account id is what stops one person counting ten times and what
-- lets them take a reaction back. Anonymous counters would give up both. So
-- the choice was between the feature and the metadata, and the honest thing is
-- to hold the metadata visibly and say so in the security model rather than
-- claim a privacy property the table does not have.
--
-- What is *not* held: reactions are not sent as push, are not attributed in
-- the feed, and the list of who reacted is not served to anybody. The counts
-- are aggregate, and a member sees which of them are their own — nothing else.

CREATE TABLE channel_post_reactions (
  post_id    bigint      NOT NULL REFERENCES channel_posts(id) ON DELETE CASCADE,
  account_id uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- One of the channel's configured emojis, checked against that list on the
  -- way in. Not free text: an unchecked column here is a place to write
  -- whatever you like into somebody else's channel.
  emoji      text        NOT NULL CHECK (length(emoji) BETWEEN 1 AND 16),

  created_at timestamptz NOT NULL DEFAULT now(),

  -- One reaction of each kind per person per post, enforced rather than
  -- checked-then-inserted.
  PRIMARY KEY (post_id, account_id, emoji)
);

-- The feed asks for the counts of fifty posts at a time.
CREATE INDEX channel_post_reactions_post_idx ON channel_post_reactions (post_id);

-- Which emojis a channel offers. An admin can change the set; what is already
-- on a post stays, because removing an emoji from the menu is not a reason to
-- silently discard what people have already said with it.
ALTER TABLE channels
  ADD COLUMN reaction_emojis text[] NOT NULL DEFAULT ARRAY['👍', '❤️', '🔥', '👏', '😂', '😮'];
