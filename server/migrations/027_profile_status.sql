-- The profile status: a short line somebody chooses to publish about
-- themselves, optionally with an emoji, optionally until a moment in time.
--
-- It did not exist. The account screen carried a row labelled "Status" whose
-- value was a hardcoded English sentence — the same sentence for every user of
-- the app, stored nowhere and settable by nobody. This migration is what that
-- row needed all along.
--
-- Three columns rather than one JSON blob, because the expiry is a timestamp
-- the database has to be able to compare against `now()`, and burying it in
-- jsonb would mean every read parsing it in application code. An expired
-- status has to be invisible on the *read* path (see `services/status.ts`);
-- relying on a sweeper to delete it would mean a missed sweep resurrects
-- something the user believed was gone.
ALTER TABLE accounts
  -- Plain text, never encrypted, and that is a deliberate difference from the
  -- avatar next to it. A profile picture is sealed under the owner's profile
  -- key because the server has no business seeing a face; a status is a line
  -- addressed to whoever is allowed to look, and the server has to be able to
  -- hand it to them. What limits it is the privacy setting, not the crypto —
  -- so `docs/security-model.md` says so rather than leaving it implied.
  ADD COLUMN status_text       text,
  -- Held apart from the text so a client can render it as a glyph beside the
  -- line rather than having to find it inside one. Length is checked here as
  -- well as in the API: a column with no bound is a column somebody fills.
  ADD COLUMN status_emoji      text,
  -- Null means "until I change it". A value in the past means gone, and the
  -- read path treats it as absent from that instant.
  ADD COLUMN status_expires_at timestamptz,
  ADD COLUMN status_updated_at timestamptz;

ALTER TABLE accounts
  ADD CONSTRAINT accounts_status_text_length
    CHECK (status_text IS NULL OR char_length(status_text) BETWEEN 1 AND 140),
  ADD CONSTRAINT accounts_status_emoji_length
    CHECK (status_emoji IS NULL OR char_length(status_emoji) BETWEEN 1 AND 8),
  -- An emoji with no text is a status; text with no emoji is a status; an
  -- expiry with neither is not. Without this, clearing the text but leaving the
  -- expiry would leave a row that expires nothing.
  ADD CONSTRAINT accounts_status_expiry_needs_status
    CHECK (status_expires_at IS NULL OR status_text IS NOT NULL OR status_emoji IS NOT NULL);

-- Lets a sweeper find expired rows without a sequential scan. The sweeper is a
-- tidiness measure only — correctness is on the read path — so the index is
-- partial and stays small: rows with no expiry are the overwhelming majority
-- and are not in it.
CREATE INDEX accounts_status_expires_at_idx
  ON accounts (status_expires_at)
  WHERE status_expires_at IS NOT NULL;
