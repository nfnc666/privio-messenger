-- Two gaps left by 015, both found by asking what happens when something is
-- interrupted rather than when it goes to plan.

/*
 * A private channel's name was sealed once, when the channel was made, and
 * never again — so it is readable only with epoch 1's key.
 *
 * 015 then decided that a new member of a private channel gets the current
 * epoch and nothing older, which is right for posts and wrong for the name: it
 * left every new member of a rotated private channel looking at "Private
 * channel" forever, with no way to fix it that did not also hand over the old
 * message keys.
 *
 * So the metadata records which key sealed it, and is re-sealed under the new
 * key when the channel rotates. A new member reads the name with the one key
 * they were given, and still cannot open a single post from before they
 * arrived. Public channels are unaffected — their title is a plaintext column,
 * because search cannot run over ciphertext.
 */
ALTER TABLE channels ADD COLUMN metadata_key_epoch integer NOT NULL DEFAULT 1;

/*
 * Whether an epoch was ever finished.
 *
 * The failure this exists for: a device generates the next key, the server
 * records the claim, and the device is then dropped in a river before the key
 * reaches anybody — or simply before it managed to write the key down. The
 * epoch is claimed, nobody holds the key, and the channel cannot be written to
 * ever again, because claiming that epoch a second time with a different key is
 * refused (and rightly: two keys for one epoch splits the channel in half).
 *
 * `abandoned_at` is how a channel gets out of that without going backwards. The
 * epoch is not reused and no old key is reinstated; the channel moves *past* the
 * dead version to a fresh one.
 *
 * The safety of that rests on something the server can check without holding a
 * key: an abandoned epoch can have no posts. Publishing at epoch N requires
 * holding N's key, and the server refuses posts at any other epoch — so if
 * nobody ever held it, nothing was ever published under it. The route enforces
 * that rather than assuming it, so nothing readable can be stranded.
 */
ALTER TABLE channel_key_epochs ADD COLUMN abandoned_at timestamptz;

-- Existing rows keep every value they had: metadata_key_epoch defaults to 1,
-- which is the epoch the metadata was in fact sealed under, and abandoned_at is
-- null because no epoch has been abandoned. Nothing is rewritten and nothing
-- becomes unreadable.
