-- The official Privio channel: which one it is, and who has been offered it.
--
-- Two decisions are encoded here and both are about *not trusting a name*.
--
-- 1. **The channel is named by its id, never by its handle.** A handle is text
--    somebody types; a uuid is the row. Anyone can make a public channel called
--    "Privio Official" with a handle one character different, and a badge keyed
--    on a name would follow them. The columns beside the id record what the
--    handle and the owner *were* when it was designated, so a later audit can
--    see whether either changed — but nothing reads them to decide the badge.
--
-- 2. **Being offered the channel is recorded per account, once.** Leaving is a
--    decision, not a state to be undone by the next sign-in, and the row below
--    is what makes "I removed it and it came back" impossible.

-- A single row, held to one by the primary key.
--
-- `ON DELETE RESTRICT` rather than CASCADE: deleting the channel that is
-- currently the official one should fail loudly and make somebody decide, not
-- quietly leave the product with no official channel and no record that it had
-- one.
CREATE TABLE official_channel (
  singleton         boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  channel_id        uuid NOT NULL REFERENCES channels(id) ON DELETE RESTRICT,

  -- What it was at the moment of designation. Evidence, not authority.
  designated_handle text NOT NULL,
  designated_owner  uuid NOT NULL REFERENCES accounts(id),

  set_at            timestamptz NOT NULL DEFAULT now(),
  -- Which operator did it, as a username. Nothing here is a credential.
  set_by            text
);

-- Who has already been offered the official channel, and who said no.
--
-- The presence of a row means "this account has been through the one-time
-- subscribe". Auto-subscribing looks only at whether the row exists, so:
--
--   * a member who leaves is never re-added, because the row stays;
--   * somebody who joins again voluntarily is not fighting the server, because
--     nothing re-runs;
--   * a new device, a re-login and an app update all find the row and do
--     nothing.
--
-- `opted_out_at` is not what stops the re-add — the row is. It is kept because
-- "left on purpose" and "was offered and stayed" are different facts, and a
-- support question about a missing channel is answered by which one it is.
CREATE TABLE official_channel_offers (
  account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel_id   uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  offered_at   timestamptz NOT NULL DEFAULT now(),
  opted_out_at timestamptz,
  PRIMARY KEY (account_id, channel_id)
);

CREATE INDEX official_channel_offers_channel_idx ON official_channel_offers (channel_id);
