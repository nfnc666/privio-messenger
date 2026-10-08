-- Polls a bot sends, and who answered what.
--
-- The honest part first, as for everything on the bot path: **a bot poll is
-- not sealed and not anonymous to the bot.** The question, the answers and
-- each person's choice are plaintext this server can read, and the bot is told
-- who voted for what — that is what a bot asking a question is for. A channel
-- poll is different on purpose: there the question travels sealed and the
-- server only knows the shape. Here there is nobody to seal it for, because
-- the bot that wrote the question holds it in the clear anyway (migration 029).
--
-- One poll, many messages. A poll is its own row so that a bot can put the same
-- question to everybody who has started it and read one tally back, which is
-- the difference between a poll and a row of buttons. Each send is still a
-- `bot_messages` row addressed to one person, so the rule for who may see and
-- answer it is the rule that already governs every bot message: the person it
-- was addressed to, and nobody else.

CREATE TABLE bot_polls (
  id           bigserial PRIMARY KEY,
  bot_id       uuid        NOT NULL REFERENCES bots(account_id) ON DELETE CASCADE,
  question     text        NOT NULL CHECK (char_length(question) BETWEEN 1 AND 300),
  -- `["Monday", "Tuesday"]`. Fixed when the poll is made and never changed: an
  -- answer somebody picked must still say what it said when they picked it.
  options      jsonb       NOT NULL,
  -- 1 is a single-choice poll. More lets a person pick up to that many.
  max_choices  smallint    NOT NULL DEFAULT 1 CHECK (max_choices >= 1),
  -- Whether the people answering may see the tally. Off unless the bot asks:
  -- a person answering a bot does not know who else was asked, and with few
  -- people a tally gives away how somebody else answered. A bot that wants the
  -- numbers shown has to say so, and the app then says that it will.
  show_results boolean     NOT NULL DEFAULT false,
  -- When it stops taking answers by itself, if ever.
  closes_at    timestamptz,
  -- When the bot closed it early. Separate from `closes_at` so the record says
  -- which of the two happened.
  closed_at    timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_polls_options_shape CHECK (
    jsonb_typeof(options) = 'array'
    AND jsonb_array_length(options) BETWEEN 2 AND 10
  ),
  CONSTRAINT bot_polls_choices_fit CHECK (max_choices <= jsonb_array_length(options))
);

CREATE INDEX bot_polls_bot_idx ON bot_polls (bot_id, id);

-- The poll a message carries, or that a vote row answers.
--
-- `ON DELETE CASCADE`: a poll is deleted only with its bot, and then the
-- messages go too — `deleteBot` removes them first in any case.
ALTER TABLE bot_messages
  ADD COLUMN poll_id bigint REFERENCES bot_polls(id) ON DELETE CASCADE;

CREATE INDEX bot_messages_poll_idx ON bot_messages (poll_id) WHERE poll_id IS NOT NULL;

-- A third kind of row: a person's answer, delivered to the bot in order with
-- what they typed and what they pressed — the same reason migration 039 made a
-- press a row here rather than a second event stream.
--
-- Every existing value is written out again, as 040 learned to: a list that is
-- assumed rather than copied is how a kind silently stops being accepted.
ALTER TABLE bot_messages DROP CONSTRAINT bot_messages_kind_check;
ALTER TABLE bot_messages
  ADD CONSTRAINT bot_messages_kind_check CHECK (kind IN ('text', 'button', 'vote'));

-- A vote must say which poll it answers.
ALTER TABLE bot_messages ADD CONSTRAINT bot_messages_vote_names_a_poll
  CHECK (kind <> 'vote' OR poll_id IS NOT NULL);

-- What each person currently has picked.
--
-- One row per option picked, keyed so that picking the same option twice is
-- impossible rather than checked. Changing an answer replaces the person's rows
-- in one transaction; an empty answer removes them, which takes the vote back.
-- Per poll, not per message: somebody who was sent the same poll twice has one
-- answer, not two.
CREATE TABLE bot_poll_votes (
  poll_id      bigint      NOT NULL REFERENCES bot_polls(id) ON DELETE CASCADE,
  account_id   uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  option_index smallint    NOT NULL CHECK (option_index >= 0),
  voted_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (poll_id, account_id, option_index)
);
