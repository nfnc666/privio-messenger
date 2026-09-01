-- How many devices one license is worth.
--
-- Until now the cap was a constant in the code, the same for everyone. It
-- belongs to the license instead: what someone bought is an entitlement, and
-- an entitlement that cannot differ per purchase cannot be sold in tiers, nor
-- raised for one customer without redeploying the server.
--
-- The default matches the constant it replaces, so every license issued before
-- this migration keeps exactly the limit it already had.
ALTER TABLE licenses
  ADD COLUMN max_devices integer NOT NULL DEFAULT 5 CHECK (max_devices > 0);

COMMENT ON COLUMN licenses.max_devices IS
  'Active devices this license permits. Enforced when a device registers, not when it sends.';
