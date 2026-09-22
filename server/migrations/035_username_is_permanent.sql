-- A username is chosen once and never changes.
--
-- The rule is in the database rather than only in the route, because "no
-- endpoint updates this column" is a fact about today's routes and this is
-- meant to be a fact about the account. A future handler, a migration script
-- or somebody at a psql prompt all pass through here.
--
-- There is exactly one exception, and it is the reason this is a trigger
-- rather than a column-level grant: deleting an account renames it to
-- `deleted.<id>` so the name it held can be used again by somebody else. That
-- rename happens in the same statement that sets `deleted_at`, so the
-- exception can be stated precisely — a row may change its username only on
-- the way to being a tombstone, and a tombstone may not change it again.
CREATE OR REPLACE FUNCTION accounts_username_is_permanent() RETURNS trigger AS $$
BEGIN
  IF NEW.username IS DISTINCT FROM OLD.username THEN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'username is permanent'
      USING ERRCODE = 'check_violation',
            DETAIL = format('account %s tried to change @%s to @%s', OLD.id, OLD.username, NEW.username);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER accounts_username_is_permanent
  BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION accounts_username_is_permanent();
