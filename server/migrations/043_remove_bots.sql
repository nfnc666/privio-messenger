-- Bots are removed from Privio.
--
-- A conversation with a bot was the one place this server held what people
-- wrote in the clear — migration 029 said so, and the app said so before every
-- bot chat. Privio's measure is maximum privacy, and a feature whose design is
-- an exception to that does not belong in it. So the feature goes, and so does
-- everything it stored: the conversations, button presses and poll answers,
-- webhooks, tokens, the files bots sent, the bots' place in groups, and the bot
-- accounts themselves, @botcreator included.
--
-- **Irreversible by intent.** Nothing here can be restored, and nothing
-- should be: what is deleted is plaintext people typed to programs somebody
-- else ran. Migrations 029 and 037–041 stay in the chain unchanged, because
-- applied migrations are never edited; this one undoes what they built.

-- Files bots sent, and the bots' own pictures: expired now, so the retention
-- sweep removes the bytes from storage along with the rows. Dropping only the
-- rows would leave blobs that no sweep could ever find again.
UPDATE accounts SET avatar_media_id = NULL WHERE is_bot;
UPDATE media_objects
   SET expires_at = now(), retained_at = NULL
 WHERE kind = 'bot_attachment'
    OR owner_account_id IN (SELECT id FROM accounts WHERE is_bot);

-- People's ties to bots: a bot in somebody's contacts or block list.
DELETE FROM contacts
 WHERE account_id IN (SELECT id FROM accounts WHERE is_bot)
    OR contact_account_id IN (SELECT id FROM accounts WHERE is_bot);
DELETE FROM blocks
 WHERE account_id IN (SELECT id FROM accounts WHERE is_bot)
    OR blocked_account_id IN (SELECT id FROM accounts WHERE is_bot);

-- The bot accounts, tombstoned the way a deleted account is: the row stays so
-- nothing that once named it points at nothing, and the name is freed into the
-- tombstone. `reserved_usernames` keeps `botcreator` reserved, so nobody can
-- later take the name and be mistaken for the assistant that used to have it.
UPDATE accounts
   SET deleted_at = COALESCE(deleted_at, now()),
       username = left('deleted.' || replace(id::text, '-', ''), 32),
       display_name = NULL,
       status_text = NULL,
       status_emoji = NULL,
       status_expires_at = NULL,
       status_updated_at = NULL,
       unidentified_access_key = NULL
 WHERE is_bot;

-- Everything the bot feature built. One statement, so the foreign keys between
-- these tables are resolved together; nothing outside them refers to them.
DROP TABLE
  bot_poll_votes,
  bot_polls,
  bot_button_presses,
  bot_messages,
  bot_webhooks,
  bot_group_members,
  bot_contacts,
  bot_tokens,
  botcreator_state,
  bots;

-- The flag that told a bot from a person. With no bots, it says nothing.
ALTER TABLE accounts DROP COLUMN is_bot;

-- `media_objects.kind` still admits 'bot_attachment' (migration 040). The rows
-- expired above need it to stay valid until the retention sweep deletes them
-- and their files; nothing can create a new one, because the route that did is
-- gone. The constraint can be narrowed by a later migration once those rows are
-- swept.
