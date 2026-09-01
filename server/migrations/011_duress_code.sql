-- The duress code used to be called a wipe code. The column follows the name
-- everything else now uses; nothing about what it holds changes.
ALTER TABLE accounts RENAME COLUMN wipe_code_hash TO duress_code_hash;
