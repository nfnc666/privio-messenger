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
| Distribution list (one message to many 1:1 chats, recipients do not see each other) | **done on this branch** (text) | client-side fan-out over the existing 1:1 sessions; no server change, see below |
| Share a location | **done on this branch**, switchable off | static coordinates in the sealed payload; no map is loaded, no live tracking, see below |
| Hide a chat behind its own PIN / biometrics | **done on this branch** with a code (was: whole-app lock only); no biometrics | per-conversation flag in the encrypted archive, see below |
| Trust level visible in the chat and contact lists | **done on this branch** (was: chat header only) | small mark in list rows derived from the existing `VerificationState`, see below |
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

## Trust mark in the chat and contact lists

- **Two marks, no third.** A shield beside the name when the safety number was
  compared and every key still matches; a warning when a number changed. For
  a number nobody compared there is no mark, because that is where every
  conversation starts, and a mark on every row would teach people to look past
  the one that matters.
- **Changed** means either of two things: the keys pinned now are not the
  ones that were verified (a key was replaced, or a device joined the
  account), or a key changed under a message and the new number has not been
  looked at yet. The second shows even for somebody never verified, as the
  chat header already does. Looking at the new number clears that alert, but
  a verified person stays "changed" until the number is compared again.
- **Same answer as the safety number screen,** without its cost. A safety
  number is 5200 hash rounds per device; the list only needs to know whether
  what was verified is still what is pinned, which is a comparison
  (`PrivioCrypto.verificationState`). The controller keeps the answers for
  the lists and reads them again at sign-in once the archive is read back
  (from the keystore, so it works offline), after the contact list loads, after a key changes, after a
  changed key is accepted, and when somebody is verified or the verification
  is withdrawn.
- **Groups and Saved** carry no mark: a group has several people with several
  numbers, and Saved is this account.
- **Read out** in the words the chat header and the safety number screen use
  ("Verified", "Safety number changed"); no new strings.
- **Server:** unchanged. Everything this reads is on the device.
- **Tests:** `app/test/trust_mark_test.dart`. Every rule above was broken on
  purpose once and the matching test went red.

## Private chats

- **Where:** a long press on a chat offers "Make private"; the first time, it
  sets up the code first. Settings → Privacy → Private chats changes or
  removes the code. A lock at the top of the chat list shows and hides the
  private chats once a code exists.
- **Hidden** from the chat list, the message search and the disappearing-timer
  exceptions; the chat screen shows a lock instead of the chat however it is
  reached. Shown for one visit with the code, hidden again whenever the app is
  left. Saved cannot be made private.
- **Honest about what it is:** protection against somebody holding the
  unlocked phone, not a second encryption. The settings screen says so.
- **The code** is at least four characters, not the screen-lock passcode, and
  kept as an Argon2id hash per account. Removing it makes every private chat
  ordinary again; a forgotten code deletes the private chats, after asking.
- **Not done:** biometrics. The person stays in Contacts, and calls are not
  hidden. Details in `docs/security-model.md`, "Private chats".
- **Server:** unchanged, and never told.
- **Tests:** `app/test/private_chats_test.dart`. Every rule above was broken
  on purpose once and the matching test went red.

## Sharing a location

- **Where:** "Location" in a chat's attach menu. The phone is asked for one
  position at that moment, the place is shown with its accuracy, and it is
  sent only after "Send".
- **Switchable off:** Settings → Privacy → Share location, on by default.
  Off, the entry is gone from the attach menu, Privio never asks the system
  where the phone is, and a send is refused even if something asked for one.
  Places other people send are still shown.
- **What travels:** a `loc` payload with the two numbers rounded to six
  decimals (about 10 cm, more than a phone measures) and the accuracy, sealed
  like any message. Its text is the same two numbers, which is what an older
  build shows and what a reply quotes. The chat list says "Location", never
  the coordinates.
- **No map.** A map is pictures fetched from a map server for the spot on
  screen, which tells that server the place. The card shows the coordinates
  instead, with "Open in maps", which asks first and says the maps app and
  its service will see the place, and "Copy", which tells nobody anything.
  The original plan of a map tile rendered on the device is dropped for that
  reason.
- **Native halves without Google:** `LocationReader.kt` on the framework's
  `LocationManager`, not the fused provider from Play services, so the Libre
  build can carry it; `LocationReader.swift` on CoreLocation. Permission is
  asked for when "Location" is picked, while the app is in use only, one
  position, no background, no stream.
- **Not done:** live location, a place name or address, a map preview.
- **Server:** unchanged. It relays a sealed envelope like any other.
- **Tests:** `app/test/location_test.dart`. Every rule above was broken on
  purpose once and the matching test went red. The two native halves are
  not compiled here (no Android SDK, no Xcode in this environment); the
  mobile build workflow compiles them on a pull request.

## Distribution lists

- **Where:** the megaphone in the chat list's top bar. A list is a name and
  up to 256 people this device has a one-to-one chat with.
- **Sending** writes the text once and sends it to each person as an
  ordinary message in their chat with this account, through the same path as
  typing it there: its own client id, that chat's disappearing timer, its own
  place in the offline queue and its own retry. Somebody blocked since the
  list was made has no chat any more and is skipped.
- **Nothing about the list is in any payload.** Each person gets a plain text
  message and cannot tell that anybody else got the same one, or that a list
  exists. The test checks the exact keys of every payload.
- **Local only:** the list lives in the encrypted archive and is never sent.
  Deleting it leaves what was sent through it in each chat.
- **What the server sees,** said on the list's screen: one envelope to each
  person at the same moment, which is what sending them one by one quickly
  would look like too.
- **Not done:** photos, files, voice and polls through a list (text only),
  and a history on the list itself; what was sent is in each chat, under
  that chat's own timer.
- **Server:** unchanged.
- **Tests:** `app/test/distribution_list_test.dart`. Every rule above was
  broken on purpose once and the matching test went red.

## Compatibility with older builds

Editing, polls and places add new payload types. A build from before this
branch does not know them and falls back to reading the payload as plain
text: a correction shows up there as a new message with the corrected text, a
poll as its question, a place as its coordinates, and a vote or a poll's end
as an empty line. Nothing is lost or
exposed, but it reads wrong, so every device in a conversation should be on a
build with these features before they are used. A future payload type should
carry a flag that tells older clients to drop it rather than show it; that is
not part of this branch.

Marking a chat unread sends nothing, and a distribution list sends ordinary
text messages, so neither needs anything from anyone else's build. An older build reading an archive that holds the mark ignores it.

