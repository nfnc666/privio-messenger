-- Enforce the 512-member group limit at the database boundary.
--
-- The HTTP routes already check the count before inserting, but COUNT -> INSERT
-- is not atomic: two concurrent joins can both observe slot 512 as free. A
-- transaction-scoped advisory lock serialises inserts for the same group, and
-- the trigger refuses an insert once the group is full. Returning NULL from a
-- BEFORE INSERT trigger makes the insert a no-op, which lets the existing route
-- return its normal result instead of turning a harmless race into a 500.

CREATE OR REPLACE FUNCTION privio_enforce_group_member_capacity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Stable 64-bit key derived only from the group id. Different groups remain
  -- independent while every insert into one group is serialised until commit.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.group_id::text, 0));

  -- Existing membership is handled by the table's uniqueness / ON CONFLICT
  -- rules and must not be rejected merely because the group is currently full.
  IF EXISTS (
    SELECT 1 FROM group_members
     WHERE group_id = NEW.group_id AND account_id = NEW.account_id
  ) THEN
    RETURN NEW;
  END IF;

  IF (SELECT count(*) FROM group_members WHERE group_id = NEW.group_id) >= 512 THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS group_member_capacity_guard ON group_members;
CREATE TRIGGER group_member_capacity_guard
BEFORE INSERT ON group_members
FOR EACH ROW
EXECUTE FUNCTION privio_enforce_group_member_capacity();
