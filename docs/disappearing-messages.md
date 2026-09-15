# Disappearing messages

What the button in the composer does, where the deletion actually happens, and
what it does not promise. The cryptographic reasoning lives in
[security-model.md](security-model.md#disappearing-messages); this is the
feature's own account of itself.

## The control

A timer button sits at the bottom of the chat, between the attach button and the
text field, on the same 48-point baseline as both so it crowds neither. Off, it
is an outlined clock in the composer's own grey, the same weight as the
attachment button beside it. On, it turns green — the same
accent as the send button — and wears the duration beside it: `30s`, `1m`, `5m`,
`1h`, `1d`, `7d`. That badge is why the button says `1d` where the sheet says
`24 hours`: a label that wraps or elides next to an icon is worse than a short
one.

Tapping it opens the chooser, which offers exactly:

**Off · 30 seconds · 1 minute · 5 minutes · 1 hour · 24 hours · 7 days**

`Off` is first because turning it off is the one choice somebody may be in a
hurry to make. The sheet says, in these words:

> New messages are deleted automatically after this long. The timer starts when
> the message is sent.

and then what it covers (text, photos, files and voice messages), that it
applies to this chat only, that messages already sent are not affected, that
everybody is told when it changes — and, in a group, that only an admin can
change it. Last, in the quieter grey:

> It cannot undo a screenshot, a photo already saved, or anything written down
> elsewhere.

That sentence is in the chooser rather than only in this file on purpose. It is
the limit of what the feature can do, and the person choosing a timer is the
person who needs to know it.

The same chooser is reachable from the group info screen and from the chat's
overflow menu. One widget, so the wording cannot drift between them.

## Where the deletion happens

**On every device, from its own clock.** The number rides inside the sealed
payload; each device stamps the message with a fixed `expiresAt` and sweeps
every few seconds, after every drain, on restore, and after a backup is
adopted. Nothing is asked of the server.

**On the server, as a bound.** A send may carry `expiresInSeconds` in the clear,
which becomes `envelopes.expires_at`: the retention sweep deletes the envelope
when the time is up, and a queued envelope past its expiry is never handed out.
An attachment's blob is shortened the same way via
`POST /v1/media?expiresInSeconds=…`. Both are clamped and can only ever shorten
the retention. This is the part that a screen timer alone cannot do — without
it, a message set to vanish in thirty seconds sits as ciphertext for the full
retention period, waiting for a device that may never come back. It is also a
deliberate metadata disclosure, and migration 024 says so in as many words.

**What "gone" means locally.** An expired message leaves the history, search
(checked against the clock, not against whether the sweep has run yet), quotes
and previews, and takes its decrypted attachment out of the in-memory cache with
it. The bubble disappearing while the photo stays one tap away in the gallery is
the version of this that does not work.

**Notices survive.** "You set disappearing messages to 1 hour" is written
locally on each device and never expires. A record that deletes itself under the
rule it describes explains nothing afterwards.

## When the clock starts

When the message reaches the server, and on the receiving side when it arrives —
the same moment seen from each end. Nothing that has not left the device has a
timer on it, so a recording made with no signal can wait in the outbox and a
failed send can sit there with its retry, without either emptying itself first.

## Who may change it

One-to-one: both sides. It is their conversation.

A group: admins only, and the role is the server's. It is checked on the device
making the change *and* on every device that receives one, which asks the server
for the group's members before applying it. A patched client can send the
payload; nobody acts on it. For the same reason a group's timer is no longer
read back off ordinary messages — that handed the setting to every member one
message at a time.

## What is covered by tests

Automated, in `app/test/disappearing_test.dart`,
`app/test/messaging_service_test.dart` and `server/test/storage.test.ts`:

- the exact list of durations, and the badge strings
- a change going out in its own payload, on being set and on being turned off
- a change arriving: the timer moves, a notice is written, no bubble appears
- a group member's change ignored on arrival; an admin's applied
- an ordinary group message not drifting the group's timer
- an expired message never reaching search, swept or not
- an app restart not resurrecting what expired while it was closed
- a restored backup not bringing expired messages back
- a second device receiving a copy of *every* message, not only the first
- the announcement not being bounded by the timer it announces
- an attachment's server-side retention shortened, clamped, and left alone for
  avatars
- a failed send carrying no timer, and a successful one starting it

None of this has been confirmed on real devices; it is what the suites assert.

## Remaining limitations

1. **Screenshots, cameras and patched clients.** A recipient who wants to keep
   a message can. This is stated in the chooser, not only here.
2. **A device that never comes back.** A message already delivered to a device
   that then goes offline forever is deleted when that device next runs, and not
   before. Nothing on the server can reach it.
3. **The announcement can be missed.** If the payload cannot be delivered — the
   recipient has no active device, or the envelope outlives the retention period
   — the other side learns the new timer from the next message instead, which is
   the old behaviour. Their messages in the meantime are not covered; yours are,
   because the number rides in yours.
4. **The server learns a retention hint.** `expires_at` on an envelope and on a
   media object is metadata the server did not have before. It does not reveal a
   chat's timer for anything the server did not carry, and it buys the deletion
   in point 2's other half — but it is not nothing, and is named here rather
   than only in the migration.
5. **Older clients show an empty bubble.** A build that predates the `t:
   "timer"` payload does not recognise it and falls through to its text handler,
   which draws an empty message. There is no protocol version negotiation to
   hide this behind. Both sides need this build.
6. **No per-message timer.** The setting is per chat. A single message cannot be
   given a different one.
7. **Media deletion is by retention, not by reference count.** A blob whose
   message expired is removed when its `expires_at` passes, which the client
   sets to twice the timer plus a day. The server does not count how many
   messages point at a blob — it cannot, since it does not know which envelope
   carries which media id. In practice a blob is uploaded per send, so this is
   one message per blob; a client that chose to reuse an id would shorten the
   life of both.
8. **Clock skew.** Each device runs its own clock. A device whose clock is badly
   wrong deletes early or late by the same amount. The server's own sweep uses
   `now()` on the database.
