-- Media somebody put in their own "Saved" area, which must outlive the
-- ordinary attachment retention.
--
-- An attachment is swept after `MEDIA_TTL_DAYS` because a message has been
-- delivered by then and every device has its own copy. A saved item is the
-- opposite case: the server's copy is what a *second* device fetches, possibly
-- months later, and sweeping it would turn somebody's saved photo into a
-- broken placeholder on their other phone. Avatars already have this exemption
-- (see `services/cleanup.ts`); this is the same idea with an explicit column
-- instead of a reference from another table, because a saved item is pointed
-- at only from inside sealed client data the server cannot read.
--
-- What this column is **not**: it is not a copy of the message. The blob stays
-- exactly what it was — ciphertext the server has no key for — and the fact
-- that it is retained says nothing about what is in it, only that its owner
-- asked for it to be kept.
ALTER TABLE media_objects
  ADD COLUMN retained_at timestamptz;

-- The sweep reads this on every pass, and retained rows are the minority.
CREATE INDEX media_retained_idx ON media_objects (owner_account_id)
  WHERE retained_at IS NOT NULL;
