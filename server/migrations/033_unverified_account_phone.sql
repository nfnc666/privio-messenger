-- Private, unverified account annotation. Deliberately separate from
-- phone_links: no discovery hash, ownership claim or uniqueness by number.
-- The primary key also indexes the account FK for deletion and own-account reads.
CREATE TABLE account_phone_notes (
  account_id uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  phone_number text NOT NULL CHECK (phone_number ~ '^\+[1-9][0-9]{6,14}$'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
