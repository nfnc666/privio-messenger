-- Handing a channel on, and reporting one.
--
-- Neither needs a new table for the handover: ownership already lives in
-- `channel_members.role`, and a transfer is two rows changing inside one
-- transaction. What is new is the record that it happened, because "who gave
-- this channel away and when" is the one question an owner who loses a channel
-- will ask, and a role column cannot answer it.

CREATE TABLE channel_ownership_transfers (
  id             bigserial   PRIMARY KEY,
  channel_id     uuid        NOT NULL REFERENCES channels(id) ON DELETE CASCADE,

  -- Both nulled rather than cascaded when an account goes: the record of the
  -- handover survives the accounts that made it.
  from_account_id uuid       REFERENCES accounts(id) ON DELETE SET NULL,
  to_account_id   uuid       REFERENCES accounts(id) ON DELETE SET NULL,

  transferred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX channel_ownership_transfers_channel_idx
  ON channel_ownership_transfers (channel_id, transferred_at DESC);

-- Reports.
--
-- WHAT A REPORT CAN AND CANNOT DELIVER, said here because the screen has to say
-- it too. The server cannot read a channel's posts — that is the whole design —
-- so a report hands an operator the channel's id, the reason chosen, and
-- nothing else. For a *public* channel there is also its title, description and
-- handle, which are plaintext for search. For a private one there is nothing to
-- look at at all.
--
-- A report is therefore a signal about a channel, not evidence of anything in
-- it. Promising more would mean promising to read the posts, which would mean
-- not encrypting them.
--
-- The reason is a fixed set rather than free text: free text is a place for
-- somebody to paste the content they are reporting, which would put the very
-- thing the encryption protects into a readable column, written by a person who
-- had every reason to.
CREATE TABLE channel_reports (
  channel_id   uuid        NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  account_id   uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reason       text        NOT NULL CHECK (
    reason IN ('spam', 'abuse', 'illegal', 'impersonation', 'other')
  ),
  reported_at  timestamptz NOT NULL DEFAULT now(),

  -- One standing report per person per channel. Reporting twice is not twice
  -- as true, and a counter somebody can run up is a way to brigade a channel.
  PRIMARY KEY (channel_id, account_id)
);

CREATE INDEX channel_reports_channel_idx ON channel_reports (channel_id);
