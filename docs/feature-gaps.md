# Feature gaps against established secure messengers

What Privio does not do yet that people moving from other privacy-focused
messengers will look for. Each row was checked against the code on
2026-10-27, not inferred from the README.

Privio's own decisions stay as they are and are not gaps: a username instead of
a random ID, no address-book upload, no plaintext exception for bots.

| feature | state in Privio | plan |
| --- | --- | --- |
| Edit a sent message in a chat or group | **done on this branch** (was: channels only) | sealed `edit` control payload, see below |
| Polls in a chat or group | channels only, tallied by the server | sealed poll, votes tallied on each device; next on this branch |
| Distribution list (one message to many 1:1 chats, recipients do not see each other) | missing | client-side fan-out over the existing 1:1 sessions; no server change |
| Share a location | missing | static coordinates in the sealed payload, map tile rendered on device; no live tracking |
| Hide a chat behind its own PIN / biometrics | missing (only the whole-app lock) | per-conversation flag in the encrypted archive; content kept out of notifications and previews |
| Trust level visible in the chat and contact lists | safety number per device, shown in the chat header only | small mark in list rows derived from the existing `VerificationState` |
| Mark a chat as unread | missing | local flag, never sent |
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
