-- Buttons under a bot's message, and who pressed which one.
--
-- The requirement this has to meet is attribution: a press must be
-- attributable to **one bot, one message and one permitted person**, and it
-- must not be possible to make the same thing happen twice by tapping twice.
-- All three fall out of the primary key below rather than out of a check
-- somewhere in a route.
--
-- What a button is *not*: a way for a bot to learn anything it was not already
-- being told. A press is delivered to the bot exactly like a message the person
-- wrote, through the same `bot_messages` row and the same take-once delivery.
-- That is why it is a row here rather than a second event system — one
-- ordering, one delivery guarantee, one table to reason about.

-- `[{"id": "yes", "label": "Yes, book it"}]`, at most eight, written by the bot
-- when it sends the message and never changed afterwards. A bot that wants
-- different buttons sends a different message; editing a message under somebody
-- who is looking at it is how a button comes to do something other than what
-- its label said when they decided to press it.
ALTER TABLE bot_messages ADD COLUMN buttons jsonb NOT NULL DEFAULT '[]'::jsonb;

-- What this row *is*. A press is not a chat line: the app does not draw it, and
-- the conversation route leaves it out. It is here so that a press and a
-- message the person typed arrive at the bot in the order they happened, which
-- two tables could not guarantee.
ALTER TABLE bot_messages
  ADD COLUMN kind text NOT NULL DEFAULT 'text' CHECK (kind IN ('text', 'button'));

-- For a press: the bot message whose button was pressed. Null for everything
-- else. `ON DELETE CASCADE` because a press of a message that no longer exists
-- is not a thing the bot should still be told about.
ALTER TABLE bot_messages
  ADD COLUMN pressed_message_id bigint REFERENCES bot_messages(id) ON DELETE CASCADE;

-- A press row may only exist for a press, and a press must name what it pressed.
ALTER TABLE bot_messages ADD CONSTRAINT bot_messages_press_names_a_message
  CHECK ((kind = 'button') = (pressed_message_id IS NOT NULL));

-- The record that makes a press happen once.
--
-- Primary key rather than an index with a check in front of it: a double tap,
-- a retried request and a replayed one all collide on insert, inside the same
-- transaction that writes the delivery row, so there is no window in which two
-- presses of the same button by the same person both become updates.
--
-- Per account, not per press: two different people pressing the same button are
-- two different events, which is the whole point of the button being on a
-- message several people can see in a group.
CREATE TABLE bot_button_presses (
  message_id bigint      NOT NULL REFERENCES bot_messages(id) ON DELETE CASCADE,
  account_id uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  button_id  text        NOT NULL CHECK (char_length(button_id) BETWEEN 1 AND 64),
  pressed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, account_id, button_id)
);
