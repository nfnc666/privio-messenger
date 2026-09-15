-- An optional phone number, so contacts can find each other.
--
-- Read this before the schema, because it decides the shape of everything
-- below: **the phone number is not an identity.** The PRIVIO ID is. A number
-- here is a lookup key somebody may attach, detach and change, and it is
-- deliberately not a way to sign in, not a way to recover an account, and not
-- something that merges two accounts. An account with no row in this table is a
-- complete account and always will be.
--
-- What the server holds, and what it does not:
--
--   * **Not the number.** The column is a keyed hash under a secret this
--     database does not contain (`CONTACT_DISCOVERY_PEPPER`). A dump of this
--     table on its own does not say whose numbers these are.
--   * **Not an address book.** Nothing anybody submits for matching is written
--     here, or anywhere. A lookup is answered and forgotten.
--   * **Not a claim of anonymity.** The phone-number space is small enough to
--     enumerate, so anyone holding *both* the pepper and this table can recover
--     every number in it by brute force. That is a real limit and it is written
--     down in `docs/phone-contacts.md` rather than glossed.

-- The verified link between an account and a number.
--
-- One row per account at most: changing a number replaces the row and requires
-- a fresh verification, because a number nobody proved is a number that belongs
-- to whoever used to have it.
CREATE TABLE phone_links (
  account_id      uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,

  -- HMAC-SHA256(pepper, HMAC-SHA256(discovery-context, E.164)). The inner hash
  -- is what the client sends, so an address book never reaches this server as
  -- plaintext; the outer one is what makes a stolen table useless without the
  -- server's secret. Neither is reversible on its own and both are deterministic,
  -- which is what allows a match at all.
  discovery_hash  bytea NOT NULL,

  -- The last two digits and the calling code, and nothing else: enough for a
  -- settings screen to say "+49 … 87" so somebody recognises which of their
  -- numbers is attached, and not enough to identify anybody. Never shown to
  -- another account.
  hint            text NOT NULL CHECK (char_length(hint) <= 16),

  verified_at     timestamptz NOT NULL DEFAULT now(),

  -- **Off until asked for.** Attaching a number and being findable by it are
  -- two decisions, and the second one is the one that publishes something.
  discoverable    boolean NOT NULL DEFAULT false,

  created_at      timestamptz NOT NULL DEFAULT now()
);

-- What a lookup actually queries. Partial, because a number nobody chose to be
-- findable by is never a match and does not belong in the index.
CREATE INDEX phone_links_discovery_idx
  ON phone_links (discovery_hash)
  WHERE discoverable;

-- Two accounts may not share a verified number.
--
-- Not to merge them — merging is explicitly not a thing this does — but because
-- a number that matched two accounts would make discovery ambiguous and would
-- let somebody keep a claim on a number they no longer own. The newer
-- verification wins and the older row is deleted, which is the behaviour
-- somebody who changed their SIM expects.
CREATE UNIQUE INDEX phone_links_unique_number ON phone_links (discovery_hash);

-- A verification in flight.
--
-- Separate from `phone_links` because it is the *unproven* state: a row here
-- says somebody asked for a code, not that they own the number. It carries no
-- number, only the same keyed hash, plus the hint to show while they type.
CREATE TABLE phone_verifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  discovery_hash bytea NOT NULL,
  hint          text NOT NULL CHECK (char_length(hint) <= 16),

  -- Argon2id, like every other credential digest here. A six-digit code is a
  -- weak secret by construction, so the cost of checking one is what stands
  -- between a leaked table and every code in it.
  code_hash     text NOT NULL,

  expires_at    timestamptz NOT NULL,
  attempts      integer NOT NULL DEFAULT 0,
  sends         integer NOT NULL DEFAULT 1,
  last_sent_at  timestamptz NOT NULL DEFAULT now(),
  consumed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- One live verification per account: asking again replaces it rather than
-- opening a second window with its own attempt budget.
CREATE UNIQUE INDEX phone_verifications_live
  ON phone_verifications (account_id)
  WHERE consumed_at IS NULL;

CREATE INDEX phone_verifications_expiry ON phone_verifications (expires_at);

-- How much lookup a single account may do.
--
-- Discovery is the one route here that answers questions about *other* people,
-- so it is the one that has to be budgeted: without this, an account could walk
-- the number space a batch at a time and learn who is on Privio. A row per
-- account per day, reset by the date rather than by a job.
CREATE TABLE contact_lookup_budget (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day        date NOT NULL,
  looked_up  integer NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, day)
);

-- Whether this account syncs its device contacts at all.
--
-- Its own column rather than a key inside `accounts.privacy`, because it is not
-- a privacy *preference* about what others see — it is consent to read
-- something off this device, and it is the flag the app checks before it asks
-- the operating system for permission.
ALTER TABLE accounts ADD COLUMN contact_sync_enabled boolean NOT NULL DEFAULT false;
