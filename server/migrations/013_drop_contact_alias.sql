-- The one column in this schema that held something a person typed and that
-- nothing ever used.
--
-- `contacts.alias` was a private nickname for a contact — "Anwalt", "Mama" —
-- stored in the clear, readable by the server, and named as such in the
-- security model. It was also never written: the API accepted it, the client
-- read it back as a display name, and no screen ever offered a field for one.
-- Forty contacts in the development database, none with an alias.
--
-- So the choice was between sealing something nobody could set, and removing
-- it. A nickname is a good feature and belongs on the device, where the
-- archive already keeps everything else about a contact and a backup carries
-- it to the next phone. What it does not need is a copy the server can read.

ALTER TABLE contacts DROP COLUMN alias;
