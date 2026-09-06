-- Versioned channel keys, so that removing somebody can actually take the
-- future away from them.
--
-- Until now a channel had exactly one key for its whole life. Removing a member
-- deleted a row and stopped them being *sent* new posts, but they still held the
-- key, and a channel's posts are readable by anyone holding it. Anyone who kept
-- a copy of the app's storage — or simply stayed signed in on a second device —
-- could go on reading everything published afterwards.
--
-- The fix is a key version, called an epoch here, that the server counts and
-- never holds a key for. Removal increments it; a remaining member's device
-- generates the next key and seals it to the others over the sessions they
-- already have. The server's whole role is to say which epoch is current and to
-- refuse posts sealed under an older one.

-- Which epoch this channel is currently on. Only ever increases: a rollback
-- would hand a removed member the future back, so there is a trigger below that
-- makes it impossible rather than a convention that it should not happen.
ALTER TABLE channels ADD COLUMN key_epoch integer NOT NULL DEFAULT 1;

-- Which key sealed this post. Every post is answerable to exactly one epoch, so
-- a member who holds epochs 1 and 3 but not 2 knows precisely which posts it
-- cannot open, rather than guessing from a decryption failure.
--
-- The default backfills every existing post to 1, which is correct: they were
-- all sealed with the one key that existed before this migration, and that key
-- becomes epoch 1 on every device that holds it.
ALTER TABLE channel_posts ADD COLUMN key_epoch integer NOT NULL DEFAULT 1;

/*
 * Who claimed each epoch, and under what label.
 *
 * The problem this solves is two admins removing two different people at the
 * same moment. Both devices see the epoch go up, both generate a key, and
 * without arbitration the channel now has two epoch-2 keys and half the members
 * hold each — posts that nobody can read, silently.
 *
 * So claiming an epoch is a database insert with (channel_id, epoch) as the
 * primary key: the first writer wins and the loser is told, re-reads, throws
 * its own key away and asks for the winner's.
 *
 * `key_id` is a random label the claiming device invents. It is NOT derived
 * from the key and tells the server nothing about it — its only job is to let a
 * device recognise "the key I hold for this epoch is the one everybody else
 * agreed on". The server still has no key for any channel, before or after.
 */
CREATE TABLE channel_key_epochs (
  channel_id      uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  epoch           integer NOT NULL,
  key_id          text NOT NULL CHECK (length(key_id) BETWEEN 8 AND 64),
  claimed_by      uuid REFERENCES accounts(id) ON DELETE SET NULL,
  claimed_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel_id, epoch)
);

/*
 * Epoch 1 for every channel that already exists.
 *
 * The label is a placeholder rather than a real claim: no device invented it,
 * and nothing verifies it. It exists so that the "which epoch is claimed" query
 * has an answer for old channels, and so that migration is a no-op for anyone
 * whose channel has never rotated — they keep the key they have, it becomes
 * epoch 1, and every existing post is already marked epoch 1 above. No post
 * becomes unreadable and no key has to be redistributed.
 */
INSERT INTO channel_key_epochs (channel_id, epoch, key_id, claimed_by)
SELECT id, 1, 'migrated-epoch-1', owner_account_id FROM channels;

-- The epoch may go up and may not come down.
--
-- A server that could lower it could re-admit a removed member to everything
-- published since, which is the whole thing this migration exists to prevent.
-- Stated as a constraint so that a bug, a bad migration or a careless UPDATE
-- fails loudly instead of quietly undoing a removal.
CREATE OR REPLACE FUNCTION channels_epoch_only_advances() RETURNS trigger AS $$
BEGIN
  IF NEW.key_epoch < OLD.key_epoch THEN
    RAISE EXCEPTION 'channel key_epoch may not go backwards (% -> %)', OLD.key_epoch, NEW.key_epoch;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER channels_epoch_only_advances
  BEFORE UPDATE OF key_epoch ON channels
  FOR EACH ROW EXECUTE FUNCTION channels_epoch_only_advances();
