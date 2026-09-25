-- A bot in a group, and exactly what it is allowed to do there.
--
-- What makes this different from every other bot platform is a fact about the
-- rest of this server rather than a choice made here: **a group message is
-- Signal ciphertext addressed to member devices, and a bot is not a device.**
-- This server cannot hand a bot a group message. Not "does not" — cannot. It
-- holds no key that opens one.
--
-- So the only party that can give a bot a group message is the **sending
-- device**, which had the plaintext because it wrote it. That is where the
-- filter lives: an app forwards a message to a bot when the message is
-- addressed to that bot (a command, a mention of it, or a reply to one of its
-- messages), and otherwise forwards nothing. The bot does not receive the rest
-- of the conversation because nobody ever handed it over.
--
-- This is the distinction migration 029 and docs/bots.md are careful about, and
-- it is the one worth stating plainly here:
--
--   * A **delivery filter** is a server choosing what to pass on. It can be
--     changed by whoever runs the server, and the bot holds the keys either
--     way. That is the usual arrangement elsewhere.
--   * A **cryptographic restriction** is the bot not holding anything that
--     opens the rest. That is the arrangement here, and it is why the rights
--     below are about what a bot may *do*, never about what it may decrypt.
--
-- `reads_all_messages` does not change that. It widens what the senders'
-- devices forward — every new message instead of only the addressed ones — and
-- the app says so in those words before an admin turns it on. Past messages are
-- not forwarded by any setting, because forwarding happens at send time and a
-- message sent before the bot arrived was never offered to it.

CREATE TABLE bot_group_members (
  bot_id      uuid NOT NULL REFERENCES bots(account_id) ON DELETE CASCADE,
  group_id    uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,

  -- Who let it in. Kept because "which admin added this bot" is the first
  -- question anybody asks about a bot they did not expect to find.
  added_by    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  added_at    timestamptz NOT NULL DEFAULT now(),

  -- The rights, one column each rather than a bitmask or a role.
  --
  -- A bitmask saves nothing here and costs the thing that matters: a column
  -- called `may_restrict_members` is readable in a query, in a log and in a
  -- migration, and a bit at position three is not. A *role* would be worse
  -- still — it is how a bot ends up with every admin right because somebody
  -- needed one of them.
  --
  -- All default to false. Adding a bot grants nothing; each right is a
  -- separate decision an admin makes.
  may_send             boolean NOT NULL DEFAULT false,
  may_moderate         boolean NOT NULL DEFAULT false,
  may_restrict_members boolean NOT NULL DEFAULT false,
  may_manage_invites   boolean NOT NULL DEFAULT false,

  -- Whether the members' devices forward every new message or only the ones
  -- addressed to this bot. False on adding, always: a bot that could read the
  -- whole group the moment it was added would make the disclosure screen a
  -- formality.
  reads_all_messages   boolean NOT NULL DEFAULT false,

  PRIMARY KEY (bot_id, group_id)
);

CREATE INDEX bot_group_members_group_idx ON bot_group_members (group_id);

-- Messages a bot receives from a group already have somewhere to live:
-- `bot_messages.scope = 'group'` with `scope_id` set, from migration 029. The
-- column was there before anything wrote it; this is what writes it.
--
-- Nothing here touches `envelopes`. A group's own messages stay ciphertext
-- this server cannot open, and a test asserts that adding a bot to a group
-- does not change that.

-- The sending device's own id for a message, so a retry after a dropped
-- connection is answered rather than delivered a second time.
--
-- The same idea as `sent_message_keys.idempotency_key` on the encrypted path,
-- and it is needed here for the first time because until this migration there
-- was no route for a person to write to a bot at all — `noteContact` was
-- exported and never called, so `mayWriteTo` could never be true and
-- `/v1/bot/send` could never succeed. A bot could be created and configured
-- and never spoken to.
--
-- Nullable, and unique only among the rows that have one: a message written by
-- a client that sends no id is still a message, it simply cannot be retried
-- safely.
ALTER TABLE bot_messages ADD COLUMN client_id text;

CREATE UNIQUE INDEX bot_messages_client_id_idx
  ON bot_messages (bot_id, account_id, client_id)
  WHERE client_id IS NOT NULL;
