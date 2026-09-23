# Disappearing messages

What the timer button does, where the account-wide setting fits, where the
deletion actually happens, and what none of it promises. The cryptographic
reasoning lives in
[security-model.md](security-model.md#disappearing-messages); this is the
feature's own account of itself.

## One timer, three states

A chat does not hold a duration. It holds a `ChatTimer`, which is one of three
things:

| State | What it means | `explicit` | `after` |
| --- | --- | :---: | --- |
| Follow the account | Whatever `Settings → Privacy` says, now and later | `false` | — |
| Off | This chat deletes nothing, whatever the account says | `true` | `null` |
| A duration | This chat, this long | `true` | the duration |

The middle row is the reason the type exists. "Off" and "no answer yet" are both
a null `Duration`, and collapsing them means a chat somebody deliberately kept
permanent starts deleting itself the day an account-wide default appears. That
is the one failure this feature cannot apologise its way out of, so the
distinction is in the type rather than in a convention.

`resolve(accountDefault)` is the only way anything reads a timer: explicit
chats answer for themselves, the rest answer with the account's. Every send
path, the composer chip and the sweep all go through
`ConversationController.disappearAfter`, which is that call — so there is one
timer system, not a per-chat one with a global one bolted beside it.

## The options

**Off · 30 seconds · 1 minute · 5 minutes · 15 minutes · 1 hour · 6 hours ·
12 hours · 24 hours**

Twenty-four hours is the ceiling, in the sheet, in the account setting, in
`models.dart` as `maxDisappearSeconds`, and in the server as
`MAX_DISAPPEAR_SECONDS`. The app's list is a convenience; the server's `max` is
what a direct API call meets, and it **refuses** rather than silently shortening
— a caller that believed it set a week and was quietly given a day would be
told nothing, and the difference is the whole promise.
`server/test/disappearing.test.ts` asserts both the acceptance of a day and the
`400` for `86401`.

The old seven-day option is gone. A timer measured in weeks is a different
product: long enough that people stop treating the chat as temporary while the
server still holds ciphertext for it.

**Settings from before the ceiling** are clamped on read, in the archive decoder
and again on any timer arriving from another device, and the chat is told once:
*"A timer longer than 24 hours was shortened to 24 hours. Messages already sent
keep the time they were sent with."* Messages already sent are untouched — each
carries the fixed `expiresAt` it was stamped with.

## In a chat

The timer button sits at the bottom, between the attach button and the text
field. Off, it is an outlined clock in the composer's grey; on, it turns the
accent colour and wears the effective duration beside it: `30s`, `1m`, `5m`,
`1h`, `24h`. That badge is why the button says `24h` where the sheet says
`24 hours` — a label that wraps beside an icon is worse than a short one.

The chooser is reachable from that button, from the chat's overflow menu and
from the group info screen. One widget, so the wording cannot drift.

It offers **Use general setting**, with the current effective value under it,
above the nine options. The tick marks the state the chat is actually in: a
chat following an account default of one hour ticks *Use general setting*, not
*1 hour*, because the two behave differently the next time that default moves.

The same distinction is repeated where somebody reads the setting without
opening the sheet: the chat's menu entry and the group info row show the
effective duration, and say *"Following your general setting"* when that is
where the number comes from.

Above the options the sheet says, in these words:

> New messages are deleted automatically after this time. The timer starts when
> the message is sent.

then what it covers (text, photos, videos, files and voice messages), that it
applies to this chat only, that messages already sent are not affected, that
everybody is told when it changes — and, in a group, that only an admin may
change it. Last, in the quieter grey:

> It cannot undo a screenshot, a photo already saved, or anything written down
> elsewhere.

That sentence is in the chooser rather than only in this file on purpose. It is
the limit of what the feature can do, and the person choosing a timer is the
person who needs to know it.

## The account-wide setting

`Settings → Privacy → Disappearing messages`, the same nine options, stored on
the account as `privacy.disappearAfterSeconds` so it follows a sign-in to
another device. It is what a new chat starts with; a chat that was set by hand
keeps its own answer.

A default that did not reach the account is not shown as saved. If the PATCH
fails the screen goes back to the stored value and says so — the alternative is
a number this device believes in and no other device has.

The screen offers two things beyond the value itself:

**Apply to existing chats.** With a preview before the confirmation: how many
chats follow the general setting and will change, how many have their own
setting and will not. Exceptions are only included if the checkbox is ticked,
and groups where you are not an admin are skipped and counted in the result
rather than failing silently.

**Manage exceptions.** Every chat whose setting differs from the general one,
with a per-chat *Use general setting* and a reset-all. A chat set to the same
thing as the default is not listed: asking somebody to tidy up something already
tidy is noise.

**Saved is excluded**, from the default and from both actions. The timer is a
promise made to somebody else about their copy; in your own notebook there is no
somebody else, and applying a chat timer there would delete the notes.

## Conflicting changes

Each chat's timer carries a version. A change increments it and rides in the
payload as `tv`.

- A higher version wins, whichever arrives second.
- Equal versions are broken by comparing account ids — deterministic, and the
  same answer on both devices, so neither announces back at the other.
- An adopted timer is never re-announced. Two devices agreeing is not an event.

The account-wide setting never overwrites an explicit chat timer on its own:
that only happens when somebody ticks the box on *Apply to existing chats*. A
chat changed after the default was set therefore stays changed.

## Where the deletion happens

**On every device, from its own clock.** The number rides inside the sealed
payload; each device stamps the message with a fixed `expiresAt` and sweeps
every few seconds, after every drain, on restore, and after a backup is adopted.
The stamp is fixed at send, so every device agrees on when a given message goes,
and a later change to the timer moves nothing that was already sent.

**On the server, as a bound.** A send may carry `expiresInSeconds` in the clear,
which becomes `envelopes.expires_at`: the retention sweep deletes the envelope
when the time is up, and a queued envelope past its expiry is never handed out.
An attachment's blob is shortened the same way via
`POST /v1/media?expiresInSeconds=…`. Both are clamped and can only ever shorten
the retention. This is the part a screen countdown alone cannot do — without it
a message set to vanish in thirty seconds sits as ciphertext for the full
retention period, waiting for a device that may never come back. It is also a
deliberate metadata disclosure, and migration 024 says so in as many words.

**What "gone" means locally.** An expired message leaves the history, search
(checked against the clock, not against whether the sweep has run yet), previews
and caches, and takes its decrypted attachment out of the in-memory cache with
it. A reply that quoted it loses the quote, rather than keeping a copy of the
expired text in its preview — which was the one place an expired message
survived.

**Notices survive.** "You set disappearing messages to 1 hour" is written
locally on each device and never expires. A record that deletes itself under the
rule it describes explains nothing afterwards.

## When the clock starts

On a successful send, and on the receiving side when it arrives — the same
moment from each end. Nothing that has not left the device has a timer on it, so
a recording made with no signal can wait in the outbox and a failed send can sit
there with its retry, without either emptying itself first. The sheet says this
where it is asked rather than leaving it to this file.

## Who may change it

One-to-one: both sides. It is their conversation.

A group: admins only, and the role is the server's.

- The device making the change checks it.
- Every device receiving one checks it, asking the server for the group's roles
  before applying.
- And the server refuses to *carry* a `group_update` envelope from a member,
  which is what turns "the menu was greyed out" into a rule. A patched client
  that skips the menu and posts the envelope directly meets a `403`.

A group's timer is not read back off ordinary messages: that handed the setting
to every member one message at a time.

## What is covered by tests

Automated, in `app/test/disappearing_test.dart`,
`app/test/messaging_service_test.dart`, `server/test/disappearing.test.ts` and
`server/test/storage.test.ts`:

- the exact list of durations, the ceiling, and the badge strings
- a new chat following the account, and saying so rather than reading as "Off"
- "Off" surviving an account default appearing afterwards
- a hand-set chat untouched by *Apply to existing chats* until it is included
- a chat set to the value of the default not being listed as an exception
- the account default clamped to a day — asserted on the request body, not only
  on what the screen reads back
- a default the account refused not being shown as saved
- Saved never taking a timer from the account default
- the higher version winning whichever arrives second, and equal versions
  resolved the same way on both sides without announcing back
- a quote losing its preview when the message it quoted expires
- a change going out in its own payload, on being set and on being turned off
- a change arriving: the timer moves, a notice is written, no bubble appears
- a group member's change ignored on arrival; an admin's applied
- an ordinary group message not drifting the group's timer
- an expired message never reaching search, swept or not
- an app restart not resurrecting what expired while it was closed
- a restored backup not bringing expired messages back
- a second device receiving a copy of *every* message, not only the first
- a failed send carrying no timer, and a successful one starting it
- **server**: a day accepted, `86401` and a week refused, `expires_at` set from
  the request, an expired envelope swept, the account default bounded and
  clearable, a member's `group_update` refused while their ciphertext goes
  through

None of this has been confirmed on real devices; it is what the suites assert.

## Remaining limitations

1. **Screenshots, cameras and patched clients.** A recipient who wants to keep
   a message can. This is stated in the chooser, not only here.
2. **A device that never comes back.** A message already delivered to a device
   that then goes offline forever is deleted when that device next runs, and not
   before. Nothing on the server can reach it.
3. **The announcement can be missed.** If the payload cannot be delivered — the
   recipient has no active device, or the envelope outlives the retention period
   — the other side learns the new timer from the next message instead. Their
   messages in the meantime are not covered; yours are, because the number rides
   in yours.
4. **The server learns a retention hint.** `expires_at` on an envelope and on a
   media object is metadata the server did not have before. It does not reveal a
   chat's timer for anything the server did not carry, and it buys the deletion
   in point 2's other half — but it is not nothing, and is named here rather
   than only in the migration.
5. **The account default is not a protocol field.** It is *your* setting,
   synced between *your* devices. The other side never sees it; what they see is
   the effective number inside each message you send.
6. **Older clients show an empty bubble.** A build that predates the `t:
   "timer"` payload does not recognise it and falls through to its text handler,
   which draws an empty message. There is no protocol version negotiation to
   hide this behind. Both sides need this build.
7. **No per-message timer.** The setting is per chat. A single message cannot be
   given a different one.
8. **Media deletion is by retention, not by reference count.** A blob whose
   message expired is removed when its `expires_at` passes, which the client
   sets to twice the timer plus a day. The server does not count how many
   messages point at a blob — it cannot, since it does not know which envelope
   carries which media id. In practice a blob is uploaded per send, so this is
   one message per blob; a client that chose to reuse an id would shorten the
   life of both.
9. **Clock skew.** Each device runs its own clock. A device whose clock is badly
   wrong deletes early or late by the same amount. The server's own sweep uses
   `now()` on the database.
