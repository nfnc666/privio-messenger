-- Where a bot wants its updates posted, instead of polling for them.
--
-- Long polling stays and remains the default. A webhook is the other half of
-- the same delivery, never a second copy of it: an update is taken from
-- `bot_messages` exactly once, by whichever path is in use, so a bot that
-- registers a webhook and also polls cannot receive the same message twice.
--
-- **The URL is a server-side request forgery waiting to happen.** A bot owner
-- chooses it and this server then fetches it, from inside whatever network the
-- server runs in. `https://10.0.0.5/admin` and the cloud metadata address at
-- `169.254.169.254` are the obvious ones. So the URL must be HTTPS, must carry
-- no credentials, and must resolve to a public address — checked when it is
-- registered and **again before every delivery**, because a name that resolved
-- publicly last week may not today. `util/outbound.ts` already did this for
-- UnifiedPush endpoints and is reused rather than reimplemented.
--
-- What is deliberately *not* stored here: the bot's API token. A delivery is
-- signed with a secret of its own, so a webhook receiver learns nothing that
-- would let it act as the bot, and a token never appears in a URL, a header of
-- an outbound request, or a log line.

CREATE TABLE bot_webhooks (
  -- One per bot. A second endpoint would be a second copy of every update and
  -- a second thing to get wrong; a bot that needs fan-out can do it itself.
  bot_id      uuid PRIMARY KEY REFERENCES bots(account_id) ON DELETE CASCADE,

  url         text NOT NULL CHECK (url ~ '^https://'),

  -- Signs each delivery, as `X-Privio-Signature: sha256=<hmac>` over the
  -- timestamp and the body. Held as a digest would be useless — the server has
  -- to compute the HMAC — so this is one of the few secrets stored as bytes it
  -- can read. It is shown to the owner once, at registration.
  --
  -- It is not the bot's token and cannot be used as one. That separation is
  -- the point: a receiver that is compromised leaks the ability to verify
  -- deliveries, not the ability to act as the bot.
  secret      bytea NOT NULL,

  created_at  timestamptz NOT NULL DEFAULT now(),

  -- What happened last time, so an owner can see a webhook that is quietly
  -- failing rather than wondering why the bot went silent.
  last_attempt_at  timestamptz,
  last_status      integer,
  last_error       text CHECK (last_error IS NULL OR char_length(last_error) <= 200),

  -- Consecutive failures. Deliveries back off on this, and past the ceiling
  -- the webhook is disabled and the bot falls back to polling — which still
  -- works, because nothing was consumed by a delivery that never arrived.
  failures    integer NOT NULL DEFAULT 0,
  disabled_at timestamptz
);

CREATE INDEX bot_webhooks_live_idx ON bot_webhooks (bot_id) WHERE disabled_at IS NULL;
