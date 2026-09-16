-- Reporting a person, as opposed to reporting a channel.
--
-- `channel_reports` (migration 022) has existed since public channels did, and
-- the profile screen needed the same thing for an account. It is a separate
-- table rather than a column bolted onto that one: the two are reviewed
-- differently and a shared table would need a nullable channel id and a
-- nullable account id, which is a table that cannot state its own rule.
--
-- **What a report can and cannot carry here is the whole design.** The server
-- holds no plaintext message, so a report about a person cannot be accompanied
-- by what they said — there is nothing to attach and no way to produce it
-- without breaking the encryption this app exists for. So a report is a reason
-- and the fact that somebody filed it, and `docs/moderation.md` says so plainly
-- rather than letting a reviewer assume evidence they will never get.
CREATE TABLE account_reports (
  -- Who is being reported.
  account_id    uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- Who reported them. Kept so a report can be withdrawn and so one account
  -- cannot file the same complaint repeatedly, never shown to the reported.
  reporter_id   uuid        NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reason        text        NOT NULL CHECK (
    reason IN ('spam', 'abuse', 'illegal', 'impersonation', 'other')
  ),
  reported_at   timestamptz NOT NULL DEFAULT now(),
  reviewed_at   timestamptz,

  -- One standing report per person per target, exactly as for channels:
  -- reporting twice is not twice as true, and a counter somebody can run up is
  -- a way to brigade an account.
  PRIMARY KEY (account_id, reporter_id),

  -- Reporting yourself is not a thing. Cheaper to forbid here than to rely on
  -- every future caller remembering.
  CONSTRAINT account_reports_not_self CHECK (account_id <> reporter_id)
);

CREATE INDEX account_reports_account_idx ON account_reports (account_id);
