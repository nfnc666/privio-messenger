-- Sealed sender: messages whose sender this server does not learn.
--
-- See docs/sealed-sender.md. The construction is Signal's, from Signal's own
-- libsignal; nothing here is cryptography, only the two things the server
-- needs to take part without knowing who is writing.

-- The gate in front of an unauthenticated send.
--
-- Sixteen bytes the account's own device derives from its profile key and
-- stores here. A sender presents the same bytes, which it can only compute if
-- this account has sent it the profile key inside an encrypted message — so
-- "may send me sealed messages" means "is somebody I have been talking to",
-- decided by the recipient and not by this server.
--
-- bytea and never returned by any route: it is compared, in constant time, and
-- that is all. Null means the account accepts no sealed messages, which is
-- every account until its app turns this on.
ALTER TABLE accounts
  ADD COLUMN unidentified_access_key bytea
  CHECK (unidentified_access_key IS NULL OR octet_length(unidentified_access_key) = 16);

-- A sealed envelope. Its sender columns are null — not unknown by accident but
-- never written — and the sender is named only inside the ciphertext, on a
-- certificate only the recipient can read.
--
-- Every existing value is written out again, as migration 040 learned to.
ALTER TABLE envelopes DROP CONSTRAINT envelopes_envelope_type_check;
ALTER TABLE envelopes
  ADD CONSTRAINT envelopes_envelope_type_check CHECK (envelope_type IN (
    'prekey',
    'ciphertext',
    'receipt',
    'typing',
    'key_change',
    'group_update',
    'call_signal',
    'sealed'
  ));

-- A sealed envelope names nobody. Enforced here so that no code path can store
-- a sealed message *and* its sender, which would quietly undo the whole point.
ALTER TABLE envelopes ADD CONSTRAINT envelopes_sealed_names_no_sender
  CHECK (envelope_type <> 'sealed' OR (sender_account_id IS NULL AND sender_device_id IS NULL));
