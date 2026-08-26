-- Signal addresses a device as (account, small integer), not as a UUID. The
-- routing id stays the UUID; this adds the stable per-account index the
-- protocol layer needs to name a session.

ALTER TABLE devices ADD COLUMN device_index integer;

UPDATE devices d
SET device_index = numbered.idx
FROM (
  SELECT id, row_number() OVER (PARTITION BY account_id ORDER BY created_at, id) AS idx
  FROM devices
) AS numbered
WHERE d.id = numbered.id;

ALTER TABLE devices ALTER COLUMN device_index SET NOT NULL;

-- Revoked devices keep their index so an old session can never be silently
-- reassigned to a different device.
ALTER TABLE devices ADD CONSTRAINT devices_account_index_unique UNIQUE (account_id, device_index);
