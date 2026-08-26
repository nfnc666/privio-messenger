-- Join links, and how the key catches up with them.
--
-- An invite link is meant to be shared: posted on a website, sent in another
-- messenger, printed on a poster. That rules out carrying the channel key in
-- the link — a key pasted into a public timeline is not a key any more.
--
-- So the link carries only the code, and the key travels afterwards, sealed
-- device to device over the Signal sessions the two accounts already have. The
-- rows below are the handshake for that: a joiner says "this device of mine has
-- no key yet", and an admin's device answers with an ordinary encrypted
-- message. The server routes the request and the reply without being able to
-- read either.

-- Groups get the same kind of link channels have.
ALTER TABLE groups ADD COLUMN invite_code text UNIQUE;

-- Existing groups predate links; give them one so nothing is link-less.
-- gen_random_uuid() is built in; gen_random_bytes() would need pgcrypto.
UPDATE groups
SET invite_code = translate(encode(uuid_send(gen_random_uuid()), 'base64'), '+/=', '-_')
WHERE invite_code IS NULL;

CREATE TABLE key_requests (
  -- Which kind of thing needs a key: a channel key, or a group's name key.
  scope       text NOT NULL CHECK (scope IN ('channel', 'group')),
  scope_id    uuid NOT NULL,

  -- Who is asking, and for which of their devices. A key is sealed to one
  -- device at a time, so a second device of the same account asks separately.
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_id   uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,

  requested_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (scope, scope_id, device_id)
);

CREATE INDEX key_requests_scope_idx ON key_requests (scope, scope_id);
