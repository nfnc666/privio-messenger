-- An expiry on an undelivered envelope.
--
-- Disappearing messages have always been enforced on the devices: the timer
-- rides inside the sealed payload, both sides adopt it, and each deletes on its
-- own clock. That is the part that matters, because it is the part that works
-- without trusting anybody.
--
-- It leaves one gap. An envelope for a device that never comes back sits here
-- until the ordinary retention sweep takes it — thirty days by default — which
-- means a message set to vanish in thirty seconds can outlive its timer by a
-- month on the server, as ciphertext nobody will ever open. This column closes
-- that: the sender says when the envelope stops being worth keeping, and the
-- sweep honours it.
--
-- **What it discloses.** The server learns roughly how long a message was meant
-- to live. It already sees when the envelope arrived and when it was collected,
-- so this adds the interval, not the content or the participants beyond what
-- delivery already requires. That is a real disclosure and it is the price of
-- the server enforcing anything at all; the alternative — the server holding
-- expired ciphertext for a month — was judged worse.
--
-- Null means "no timer", which is every message sent by a client that predates
-- this column, and they keep falling to ENVELOPE_TTL_DAYS as before.
ALTER TABLE envelopes ADD COLUMN expires_at timestamptz;

-- The sweep deletes by this, so it is the column it searches on. Partial,
-- because most envelopes carry no expiry and an index over those is dead weight.
CREATE INDEX envelopes_expiry_idx ON envelopes (expires_at)
  WHERE expires_at IS NOT NULL;
