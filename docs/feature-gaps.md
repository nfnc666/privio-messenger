# Feature gaps against established secure messengers

What Privio does not do yet that people moving from other privacy-focused
messengers will look for. Each row was checked against the code on
2026-10-27, not inferred from the README.

Privio's own decisions stay as they are and are not gaps: a username instead of
a random ID, no address-book upload, no plaintext exception for bots.

| feature | state in Privio | plan |
| --- | --- | --- |
| Edit a sent message in a chat or group | **done on this branch** (was: channels only) | sealed `edit` control payload, see below |
| Polls in a chat or group | **done on this branch** (was: channels only, tallied by the server) | sealed poll, votes tallied on each device, see below |
| Distribution list (one message to many 1:1 chats, recipients do not see each other) | missing | client-side fan-out over the existing 1:1 sessions; no server change |
| Share a location | missing | static coordinates in the sealed payload, map tile rendered on device; no live tracking |
| Hide a chat behind its own PIN / biometrics | missing (only the whole-app lock) | per-conversation flag in the encrypted archive; content kept out of notifications and previews |
| Trust level visible in the chat and contact lists | safety number per device, shown in the chat header only | small mark in list rows derived from the existing `VerificationState` |
| Mark a chat as unread | **done on this branch** | local flag, never sent, see below |
| Group calls | 1:1 calls only | needs an SFU and end-to-end media keys; separate design document first |

## Editing a message

- **Wire:** `MessagePayload.edit(editTo: <client id>, body: <whole new text>)`,
  type tag `edit`, field `et`. A control payload like a deletion: never a bubble,
  sealed per device over the existing Signal session, and synced to this
  account's own devices so they do not show two versions of one line.
- **Who may edit:** only the sender, only an ordinary text message that has left
  the outbox, not in Saved. Checked when sending *and* when receiving: an
  incoming correction may only change a message its own sender wrote, and from
  this account's own devices only this account's own messages.
- **What changes:** the text is replaced and `editedAt` is set; the bubble shows
  "edited" next to the time and that mark is never hidden. The old text is not
  kept. Replies that quoted it keep their own copy. An empty correction is
  refused, so an edit can never act as a silent deletion; a tombstone cannot be
  edited back into a message.
- **Failure:** the text changes here first and the correction is sent after. A
  send that fails says so (`editedHereOnly`): the other side still has the old
  text.
- **Server:** unchanged. It relays bytes it cannot read and learns that something
  was sent, as for any message.
- **Tests:** `app/test/edit_test.dart`. Every rule above was broken on purpose
  once and the matching test went red.

## Polls in chats and groups

- **Different from a channel poll on purpose.** A channel poll is counted by the
  server, which knows its shape. A chat poll is not: the question and answers
  travel sealed in the message that asks (`poll`, field `pl`), every vote is a
  sealed control payload sent to everyone in the chat (`vote`: `pt` target,
  `pc` the whole choice), and so is the end (`pollend`). Each device keeps its
  own tally. The server relays bytes it cannot read and never learns that a
  poll exists, how many answers it has, or who voted for what.
- **Rules, checked on every device that receives them:** a vote counts for the
  account the Signal session says sent it, never for a name in the payload; it
  must fit the poll (in range, no repeats, not more picks than allowed); one
  vote per person, replaced when they change it, removed when empty; an ended
  poll takes no more votes; only the person who asked may end it. A poll
  outside the limits (2–12 answers, 100 characters per answer, 300 for the
  question) is filed as its question rather than as a poll.
- **Shown:** results only after this account has voted or the poll has ended,
  so the first voters are not steered by the count. A one-answer poll is
  answered by the tap; a several-answer poll gathers the picks and sends them
  with a button, because a vote is always sent whole. The chat list reads
  "Poll: question".
- **The dialog** for writing a poll is now shared with channels
  (`widgets/new_poll_dialog.dart`); only its note differs.
- **Tests:** `app/test/chat_poll_test.dart`, including group polls. Every rule
  above was broken on purpose once and the matching test went red.

## Marking a chat unread

- **Where:** a long press on a row in the chat list. A read chat offers "Mark
  as unread"; a chat that is marked, or has messages waiting, offers "Mark as
  read".
- **Local only.** The mark lives on the conversation in the encrypted archive,
  next to the pin, and is never sent. No receipt goes out and none is taken
  back, so the other side's ticks stay as they were. A refresh of the contact
  list or of a group listing keeps it.
- **Shown:** a dot where the count would be, because a number would claim
  messages that are not there. A real count wins over the dot. The "Unread"
  filter shows marked chats too.
- **Gone** when the chat is opened, from the list or any other way in, and when
  it is marked read.
- **Marking read with messages waiting** is the same as opening the chat: read
  receipts go out if they are switched on. The sheet says so in that case, and
  says "nothing is sent" in every other one, so the note is never wrong about
  what leaves the device.
- **Server:** unchanged, and never told.
- **Tests:** `app/test/mark_unread_test.dart`. Every rule above was broken on
  purpose once and the matching test went red.

## Compatibility with older builds

Editing and polls add new payload types. A build from before this branch does
not know them and falls back to reading the payload as plain text: a
correction shows up there as a new message with the corrected text, a poll as
its question, and a vote or a poll's end as an empty line. Nothing is lost or
exposed, but it reads wrong, so every device in a conversation should be on a
build with these features before they are used. A future payload type should
carry a flag that tells older clients to drop it rather than show it; that is
not part of this branch.

Marking a chat unread sends nothing, so it needs nothing from anyone else's
build. An older build reading an archive that holds the mark ignores it.

