-- Per-admin permissions.
--
-- A single "admin" role is too blunt for a channel: someone who should be able
-- to publish is not necessarily someone who should be able to hand out
-- permissions or delete the whole thing. Each capability is therefore its own
-- flag, and an admin can only ever grant what they already hold — otherwise
-- "promote to admin" is just a slower way to take a channel over.

ALTER TABLE channel_members
  ADD COLUMN can_post            boolean NOT NULL DEFAULT false,
  ADD COLUMN can_edit_channel    boolean NOT NULL DEFAULT false,
  ADD COLUMN can_delete_posts    boolean NOT NULL DEFAULT false,
  ADD COLUMN can_manage_members  boolean NOT NULL DEFAULT false,
  -- Deleting the channel is the one action nothing undoes, so it is off unless
  -- the owner deliberately grants it.
  ADD COLUMN can_delete_channel  boolean NOT NULL DEFAULT false;

-- Existing owners and admins keep what their role implied.
UPDATE channel_members
SET can_post = true,
    can_edit_channel = true,
    can_delete_posts = true,
    can_manage_members = (role = 'owner'),
    can_delete_channel = (role = 'owner')
WHERE role IN ('owner', 'admin');
