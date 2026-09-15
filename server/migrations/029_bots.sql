-- Bots: accounts somebody else operates over an HTTP API.
--
-- The decision this migration encodes, before anything else:
--
--   **A conversation with a bot is not end-to-end encrypted, and it is kept
--   out of the encrypted path entirely rather than being a weaker case of it.**
--
-- A Privio message is sealed for a device that holds Signal keys. A bot is a
-- program on somebody's server reached over HTTP; for it to receive a sealed
-- message, this server would have to hold the bot's identity key and open the
-- envelope on its behalf — which is the one thing the whole design exists to
-- make impossible. Rather than quietly weaken that for bot chats, bot messages
-- live in their own table, never touch `envelopes`, and the app says so in
-- plain words before the first message is sent. See `docs/bots.md`.
--
-- The consequence, stated so nobody has to infer it: the operator of a bot
-- reads what is sent to their bot, and so can this server. That is true of
-- every bot platform; what is different here is that it is said out loud and
-- confined to bot conversations, which are the only ones it touches.

-- A bot *is* an account — it has a username, a display name and a picture, and
-- it appears in a chat list like anybody else. What makes it a bot is this row.
CREATE TABLE bots (
  account_id       uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  owner_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  description      text CHECK (description IS NULL OR char_length(description) <= 512),
  -- `[{command, description}]`. Held as one document because it is read and
  -- written whole, never queried into.
  commands         jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- A disabled bot keeps its username and its history and stops receiving.
  -- Deleting is the other thing, and it goes through the account tombstone.
  disabled_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX bots_owner_idx ON bots (owner_account_id);

-- API tokens. Only ever stored as a digest.
--
-- The plaintext is shown once, in a screen that does not put it in the chat
-- history, and is never written to a log. A token nobody wrote down is a token
-- that has to be regenerated, which is the correct failure direction.
--
-- `bytea`, like `sessions.token_hash`, `licenses.key_hash` and
-- `media_objects.download_token_hash`. The type is the argument: a digest held
-- as text is a column somebody has to be told is not readable, and the schema
-- test in `test/schema.test.ts` asserts the type rather than trusting a note.
CREATE TABLE bot_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id       uuid NOT NULL REFERENCES bots(account_id) ON DELETE CASCADE,
  token_hash   bytea NOT NULL UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked_at   timestamptz
);

CREATE INDEX bot_tokens_bot_idx ON bot_tokens (bot_id) WHERE revoked_at IS NULL;

-- Who has written to a bot, which is what licenses the bot to write back.
--
-- A bot may not open a conversation. This table is the record of the user
-- having opened one, and it is the only thing that makes `sendMessage` to that
-- user succeed. Removing the row — blocking the bot — closes it again.
CREATE TABLE bot_contacts (
  bot_id       uuid NOT NULL REFERENCES bots(account_id) ON DELETE CASCADE,
  account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  started_at   timestamptz NOT NULL DEFAULT now(),
  blocked_at   timestamptz,
  PRIMARY KEY (bot_id, account_id)
);

-- Messages to and from a bot.
--
-- Deliberately **not** `envelopes`. Envelopes carry ciphertext this server
-- cannot open; these carry plaintext it can. Keeping them in separate tables is
-- what stops one becoming a weaker version of the other by accident, and makes
-- "which of my messages can the server read" answerable by looking at a schema
-- rather than by reading every route.
CREATE TABLE bot_messages (
  id           bigserial PRIMARY KEY,
  bot_id       uuid NOT NULL REFERENCES bots(account_id) ON DELETE CASCADE,
  -- The human on the other side.
  account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- Where it happened: null for a one-to-one chat with the bot, otherwise the
  -- group or channel the bot was addressed in.
  scope        text NOT NULL DEFAULT 'direct' CHECK (scope IN ('direct', 'group', 'channel')),
  scope_id     uuid,
  -- 'user' wrote it, or the bot did.
  author       text NOT NULL CHECK (author IN ('user', 'bot')),
  body         text NOT NULL CHECK (char_length(body) <= 4096),
  created_at   timestamptz NOT NULL DEFAULT now(),
  -- Set when a long poll has handed it to the operator. Only ever for rows the
  -- *user* wrote: the bot does not receive its own messages back.
  delivered_at timestamptz
);

CREATE INDEX bot_messages_undelivered_idx
  ON bot_messages (bot_id, id)
  WHERE author = 'user' AND delivered_at IS NULL;

CREATE INDEX bot_messages_conversation_idx ON bot_messages (bot_id, account_id, id);

-- The account flag, so every existing profile read says whether it is a bot
-- without joining. What draws the "BOT" badge.
ALTER TABLE accounts ADD COLUMN is_bot boolean NOT NULL DEFAULT false;

-- Usernames nobody may register.
--
-- A table rather than a hardcoded list, because the set will grow and because
-- the reservation has to hold for names that are not yet accounts: @botcreator
-- is created below, but @support and the rest are held empty so that nobody can
-- take a name the product will want to speak with later.
CREATE TABLE reserved_usernames (
  username text PRIMARY KEY CHECK (username ~ '^[a-z0-9_.]{3,32}$'),
  reason   text NOT NULL
);

INSERT INTO reserved_usernames (username, reason) VALUES
  ('botcreator', 'the official assistant that creates bots'),
  ('privio',     'the product'),
  ('support',    'reserved for official support'),
  ('admin',      'reserved'),
  ('system',     'reserved'),
  ('help',       'reserved'),
  ('security',   'reserved');

-- The assistant itself.
--
-- A real account so it can hold a username, a picture and a chat, with a
-- password hash nobody can present: `!` is not a valid Argon2 encoding, so
-- `verifySecret` refuses it for every input rather than accepting some
-- particular one. There is no login for this account; it is driven by the
-- server, not by a person.
INSERT INTO accounts (username, display_name, password_hash, is_bot)
VALUES ('botcreator', 'Bot Creator', '!', true)
ON CONFLICT (username) DO NOTHING;

-- Where a conversation with @botcreator has got to.
--
-- The assistant is a state machine, and this is its one piece of state. Held
-- server-side because the conversation has to survive the app being closed
-- halfway through creating a bot, and per account because two people creating
-- bots at once are two conversations.
CREATE TABLE botcreator_state (
  account_id uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  step       jsonb NOT NULL DEFAULT '{"at":"idle"}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
