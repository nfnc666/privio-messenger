# Saved

A place of your own for notes, pictures, files and voice messages. It behaves
like the chat people expect from other messengers, and it is built out of the
one this app already has.

## It is a conversation with yourself

**Saved is the conversation whose id is your own account id.** That single
decision is most of the feature, and it is what this document is really about.

The alternative — a notes table, a notes sync, a notes archive — would have
been a second message system living beside the first, with its own bugs in the
same places: its own idempotency, its own offline queue, its own encryption at
rest, its own restore path. Everything Saved needs, a conversation already has:

| What Saved needs | Where it comes from |
| --- | --- |
| Encrypted at rest, per account | The sealed archive, unchanged |
| Surviving a restart | The same archive |
| Text, photos, video, files, voice, stickers | The same composer and the same send path |
| Offline entries, no duplicates on reconnect | The outbox, keyed on the client id the server uses as its idempotency key |
| Sync between your own devices | See below |
| Search, delete, retry | The same code every chat uses |

The server already treats a key request for your **own** account as "my other
devices" — `routes/devices.ts` has done this since multi-device existed. So
writing to yourself seals a copy for each of your other devices and they file
it. On an account with a single device there is nobody to seal for, and
`MessagingService.sendPayload` reports that as delivered to nobody rather than
as a failure: a note on your only device has arrived — it is on the device.
Without that one rule every saved entry on a single-device account would sit
marked failed with a retry button that could never succeed.

A message arriving **from this account** is a saved entry written on another of
your devices. It is filed into Saved and drawn as yours, deduplicated on the
client id like the sync path beside it, so a redelivery or a queue drained
after a reconnect cannot become a second note.

## What it looks like

Two ways in, one place:

* **Account → Saved**, with a bookmark.
* **A row in the chat list**, with a bookmark instead of an avatar and the word
  "Saved" instead of your own username — which would otherwise read as a chat
  with somebody who happens to share your name.

Both open the same conversation by the same id, so they cannot become two
areas. The row is added by `ConversationController.chats` when the store leaves
it out: the store deliberately hides an empty direct conversation, because an
empty chat with somebody is just a contact — Saved is the one direct
conversation that is not a contact, and a place has to be reachable before
anything is in it.

Inside, it is the chat screen with the things that only make sense against
somebody else removed: no call, no video, no safety number, no blocking, and
**no disappearing timer**. It gains a search box, a media overview, pinning,
and a selection mode for deleting several entries at once.

## What it keeps, and for how long

**Permanently, until you delete it.** The disappearing-messages timer of your
chats is not applied here and cannot be set here:
`mayChangeDisappearAfter` refuses for Saved, and `_adoptTimer` ignores anything
arriving with a timer on it. The guard is at the door every timer change goes
through rather than only in the menu that no longer offers one — a rule that
lives in a widget is a rule the next call site does not have.

A timer **for** Saved is deliberately not offered. The brief allowed one if it
were set and confirmed separately; a notebook that deletes itself is a feature
with one correct default and no obvious second one, so it is not there rather
than there and off.

### Saved media outlives ordinary retention

An attachment is swept after `MEDIA_TTL_DAYS` because the message has been
delivered and every device has its own copy. A saved item is the opposite: the
server's copy is what a *second* device fetches, possibly months later.

So migration 034 adds `media_objects.retained_at`, the sweep skips retained
rows, and the download route stops hiding them once their ordinary expiry has
passed — keeping the row while the route hid it would be the worst of both.
`POST /v1/media/:id/retain` is owner-only and idempotent; deleting a saved
entry releases it with `DELETE /v1/media/:id/retain`, which is deliberately not
a delete: the same blob may still be the attachment of an ordinary message in a
real conversation, and removing a saved copy must not reach into that chat.

Retained objects count against the media quota. They occupy exactly as much
storage as anything else, and leaving them out would make Saved a way to hold
an unbounded amount of it.

## Saving a message from a chat

Long-press → **Save to Saved**. The text, the attachment pointer and the caption
are copied.

**A message under a disappearing timer is refused, with the reason.** Copying it
would undo the one guarantee its sender was given. The action is still offered
on such a message rather than hidden, because a row that silently vanished
would leave somebody wondering where it went; pressing it says why, which is the
honest version of the same thing. A deleted message and a system notice are
refused too — there is nothing in them to keep.

**The confirmation follows the entry, not the tap.** `saveToSaved` files the
entry before it returns, and only then does the screen say "Saved". An entry
that is on this device but has not reached the others says *that* instead —
a different sentence, and a true one.

## Privacy

* Entries are sealed by the same archive key as the rest of the history, per
  account. There is no separate notes store, so there is no second thing to
  encrypt, forget to encrypt, or leave out of a wipe.
* The server routes copies to **your own devices only**. It has no key for any
  of it, and `retained_at` says only that an owner asked for a blob to be kept.
* Nothing about a saved entry is written to a log, and Saved produces no push
  notification, so there is no preview to leak.
* Signing out clears it with everything else. On a new device it comes back
  through the existing recovery path and no other — **if the keys are gone, the
  notes are gone**, and nothing here claims otherwise.

## What is tested

`app/test/saved_test.dart` (13) and four server tests in `storage.test.ts`:
that Saved is the account's own conversation and only ever one of them, that a
second account gets its own and cannot read the first one's, that a
disappearing message is refused, that a timer cannot be set on Saved at all,
pinning, the media overview, and the screen — its name, its missing call
buttons, its empty state, its menu, and multi-select.

Falsified: removing the disappearing-message refusal, the chat-list row, and
the timer guard each turn their own test red.

On the server: a retained attachment survives the sweep **and is still
downloadable**, releasing it hands it back to the ordinary retention, retaining
twice is retaining once, and **another account's direct API call is 404** — for
both retain and release, asserted against the route rather than against the
client, because the client is not what an attacker would use.

## Not verified on a device

Everything above is widget and API tests. What they cannot answer is in rows
V1–V6 of [`device-beta-checklist.md`](device-beta-checklist.md): a note written
on one phone appearing on another, a saved photo still opening weeks later, and
what a Saved area with a few hundred entries feels like to scroll.
