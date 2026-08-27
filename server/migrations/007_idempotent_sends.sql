-- Sending the same message twice.
--
-- A send that times out has not necessarily failed: the envelopes may already
-- be queued, and the client cannot tell the difference from the outside. Retry
-- is the right behaviour — a voice message that vanished because the train went
-- into a tunnel is worse than one that arrives late — but a naive retry
-- delivers the recording twice.
--
-- So a sending device stamps each send with an id of its own, and the server
-- remembers it. The second attempt is answered with the first attempt's result
-- instead of being queued again. The id is opaque to the server, scoped to the
-- device that made it, and says nothing about the message.

CREATE TABLE sent_message_keys (
  device_id        uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  idempotency_key  text NOT NULL,

  -- Enough to answer the retry the same way as the original.
  delivered_to     integer NOT NULL,

  created_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (device_id, idempotency_key)
);

-- Retries happen within minutes; the row is only useful for that window. The
-- cleanup sweep drops the rest.
CREATE INDEX sent_message_keys_created_idx ON sent_message_keys (created_at);
