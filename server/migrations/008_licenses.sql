-- Privio licenses.
--
-- A license key activates the builds that are not sold through a store —
-- Privio Libre from F-Droid and the direct APK. The key is bought on the
-- website, which never sees an account; it is redeemed here, where accounts
-- exist, and from then on belongs to exactly one of them.
--
-- Only a keyed hash of the key is stored. It has to be deterministic, because
-- a redemption arrives with the key and nothing else to look it up by — so
-- Argon2 is not an option here. HMAC-SHA256 keyed with LICENSE_HASH_SECRET
-- gives the lookup while making a stolen dump useless on its own: without the
-- secret there is nothing to grind 100 bits of entropy against.

CREATE TABLE licenses (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- HMAC-SHA256 of the normalised key. Never the key itself.
  key_hash          bytea NOT NULL UNIQUE,

  -- Where the entitlement came from. Store purchases are validated against
  -- Apple/Google and land here too, so one query answers "is this account
  -- licensed" regardless of how it was paid for.
  source            text NOT NULL DEFAULT 'key' CHECK (source IN ('key', 'apple', 'google')),

  -- 'revoked' covers a chargeback or a refunded order.
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),

  -- Set together, exactly once, by the redemption.
  redeemed_by       uuid REFERENCES accounts(id) ON DELETE SET NULL,
  redeemed_at       timestamptz,

  -- The order this license was issued for. No amount, no customer, no card.
  payment_provider  text,
  payment_reference text,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT licenses_redeemed_consistent CHECK ((redeemed_by IS NULL) = (redeemed_at IS NULL))
);

-- One account holds at most one license. This is also what stops a second key
-- from being burned on an account that is already licensed: the redemption
-- fails on the index before the key is marked used.
CREATE UNIQUE INDEX licenses_account_idx ON licenses (redeemed_by) WHERE redeemed_by IS NOT NULL;

-- Webhook idempotency. A payment provider will retry a delivery it did not see
-- acknowledged, and the same order must not mint a second key.
CREATE UNIQUE INDEX licenses_payment_idx ON licenses (payment_provider, payment_reference)
  WHERE payment_reference IS NOT NULL;
