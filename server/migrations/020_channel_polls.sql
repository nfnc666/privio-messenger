-- Polls in channel posts.
--
-- THE QUESTION IS NOT HERE, and that is the design. The question and the
-- answers live inside the post's sealed payload, like the post's own text, so
-- the server never learns what was asked or what the options were called. What
-- it holds is the *shape*: how many options there are, how many a person may
-- pick, and when it closes. Three small integers that say nothing about
-- content, and the server needs them because it is the thing enforcing that a
-- vote is in range, that nobody picks four answers in a two-answer poll, and
-- that a closed poll stays closed. A client-side rule is a suggestion.
--
-- A vote is `(post_id, account_id, option_index)` in the clear. The server
-- therefore knows that an account picked option 2 of a poll whose text it
-- cannot read — strictly less than it learns from a reaction, where the emoji
-- itself is readable. The account id is there for the same two reasons as
-- there: it is what stops one person voting ten times, and what lets them
-- change their mind. An anonymous counter gives up both.
--
-- What is not held and not served: who voted for what. The feed answers with a
-- count per option and this reader's own choices. There is no route that
-- returns the rows, and "who picked that" is not a question this API answers.

CREATE TABLE channel_polls (
  post_id      bigint      PRIMARY KEY REFERENCES channel_posts(id) ON DELETE CASCADE,

  -- Two is the fewest that is a question; twelve is more than fits on a phone.
  option_count smallint    NOT NULL CHECK (option_count BETWEEN 2 AND 12),

  -- 1 for "pick one". Higher for a poll that takes several.
  max_choices  smallint    NOT NULL DEFAULT 1 CHECK (max_choices >= 1),

  -- NULL means it stays open.
  closes_at    timestamptz,

  CONSTRAINT max_choices_fits_the_options CHECK (max_choices <= option_count)
);

CREATE TABLE channel_poll_votes (
  post_id      bigint      NOT NULL REFERENCES channel_polls(post_id) ON DELETE CASCADE,
  account_id   uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- Zero-based, and checked against the poll's option_count on the way in. A
  -- number on its own tells the server nothing: it does not know what option 2
  -- is called.
  option_index smallint    NOT NULL CHECK (option_index >= 0),

  created_at   timestamptz NOT NULL DEFAULT now(),

  -- One vote per option per person, enforced rather than checked-then-inserted.
  PRIMARY KEY (post_id, account_id, option_index)
);

CREATE INDEX channel_poll_votes_post_idx ON channel_poll_votes (post_id);
