# Opening somebody's profile from a chat

Before this, there was nowhere to go. A one-to-one chat showed a picture and a
name in its header and neither did anything; a group message showed a sender's
name above it and that name was not a link to anything. The only place a person
could be looked at was the contacts list, which lists people you have already
added and offers a name, a handle and a timestamp with nothing to act on.

This is the screen those taps now lead to, and the rules it follows.

## Getting there

| Where | What a tap opens |
| --- | --- |
| The header of a **one-to-one** chat | That person's profile |
| The header of a **group** chat | The group's own screen, as before |
| A **sender's name** above a message in a group | That sender's profile |
| A **member row** in the group's screen | That member's profile |

The group header deliberately did not change. A group is a thing in its own
right, its screen is where leaving and renaming live, and moving that tap
somewhere else to make room for profiles would have taken a working path away.

### Coming back leaves the chat alone

The profile is **pushed** on top of the chat. Nothing saves the half-written
message, the reply being composed or the scroll position, because nothing has
to: the chat's `State` is never torn down, so it is all still there when the
profile is popped.

This is worth saying plainly because the obvious alternative — replacing the
route, or rebuilding the chat on the way back — loses a draft somebody was
halfway through typing, and does it silently. `contact_profile_test.dart` types
into the composer, opens a profile, comes back and expects the text; swapping
the push for a `pushReplacement` turns it red.

The same reasoning decides what **Message** does on the profile. Opened from
that person's own chat, it pops back to the chat that is already underneath.
Opened from anywhere else, it resolves the conversation **by account id** —
which is the conversation's identity in the message store — so two routes into
the same person land in one chat rather than stacking a second.

## What it shows, and what it refuses to show

Everything on the screen comes from `GET /v1/users/id/:accountId`, and **the
server decides what is in that answer**. The client does not receive a status or
a last-seen time it is then trusted to hide.

* **Always**: the display name, the `@username`, the Privio ID, and the picture
  when this device can open it.
* **Only if the owner published it and this viewer may see it**: the status
  line, and when they were last online. `services/status.ts` and
  `services/presence.ts` make those two decisions separately — see the note in
  `status.ts` for why one switch must not cover both.

Where a value was withheld, it arrives as `null` and **nothing is drawn**. There
is no greyed-out row and no "hidden" label, and that is a decision rather than
an omission: telling somebody that there is something they are not being shown
publishes the one thing the owner chose not to publish.

**A phone number is never on this screen.** A number linked for contact
discovery is used to *find* people; `publicProfile` on the server does not
select the column, so there is nothing here to leave out by accident, and a
server test asserts no key matching `/phone/i` appears in the payload.

### Addressed by id, never by name

A profile is fetched by account id. A display name is chosen by the person it
names, is not unique, and can be changed to somebody else's — looking a profile
up by name would be a way for somebody to be shown the wrong person on purpose.
The id comes from the conversation or from the message that was tapped.

A message filed before senders were recorded has a name and no account id
behind it. Its name is **not** tappable, for the same reason.

## What it offers

Four actions across the top — message, call, video, verify — and rows
underneath. `ProfileActionButton` is the button the channel profile already
used; it moved into `widgets/` rather than being copied, so the two screens
cannot drift apart.

The fourth is deliberately **verification** rather than an overflow menu.
Everything an overflow would have held is a labelled row below, and two ways to
reach one thing is one way too many; the safety-number screen is the action with
nowhere else to be, and on a screen about who somebody is it earns the space.
The screen it opens is the existing one, unchanged.

* **Add to / remove from contacts.** Removing a contact does **not** delete the
  chat or its messages: an address-book entry and a conversation are different
  things.
* **Block / unblock.** Blocking uses the same words and the same confirmation
  the chat's menu uses, and drops the conversation from this device, as it
  always has — so the profile leaves too, because what is underneath it may be
  the chat that has just gone.
* **Report.** See below.

Every one of these re-reads the profile from the server afterwards. The buttons
state what the server thinks, not what the tap hoped; a failed add leaves the
row saying "Add to contacts", which is the truth.

### Your own profile

Reached by tapping your own name in a group. It shows what everybody else would
see and offers none of the actions that only make sense against somebody else —
you do not add, block, report or call yourself. It offers no **editing** either:
that lives on the Account screen, and two places to change one picture is one
place too many.

The server decides this too, with `isSelf`, rather than the client comparing
ids in one more place.

### Blocked, deleted, unreachable

Three states with three different answers:

* **Blocked** — a banner saying so, an explanation that they are not told, and
  "Unblock". Blocking is not offered a second time.
* **Deleted** — "This account no longer exists". `404` covers the deleted
  account and the never-existed account alike and the server deliberately does
  not tell them apart, because telling them apart would answer "did this id ever
  exist" for anybody who asked.
* **Unreachable** — the failure in words, and "Try again". Distinct from the
  one above: one is a fact, the other is a suggestion.

## Reporting a person

`POST /v1/users/:id/report`, one of five fixed reasons, one standing report per
reporter per target — `account_reports`, migration 033, mirroring the channel
table from migration 022.

**A report about a person carries no evidence, and the screen says so before the
reasons are offered.** The server has never held a plaintext message, so there
is nothing to attach and no way to produce it that would not mean abandoning the
encryption this app exists for. Somebody about to report a person generally
expects the messages to go with it; being told otherwise afterwards would be
worse than being told first.

This is also why the reason is an enum rather than a text box. A free field is
where somebody pastes the content they are reporting, which would put exactly
the thing the encryption protects into a column the server can read, written by
a person with every reason to put it there. `schema.test.ts` holds both report
columns to that rule.

**Reporting does not block, and blocking does not report.** The two sit next to
each other and a user may well want both, but a report that silently blocked
would turn an accusation into a change to your own account, and a block that
silently reported would send your address book to a moderator.

Operators read the queue at `GET /v1/admin/reports/accounts`, grouped per
account with counts per reason. It is read-only: there is no suspend to pair
with it, because what suspending a *person* would mean for conversations the
server cannot read is a design question, not a query. See
[`admin-panel.md`](admin-panel.md).

## Account separation

`ProfileController` holds other people's profiles for **one** signed-in account.
It is bound to that account at sign-in, and rebinding empties the cache in the
same call.

That is not tidiness. The same profile answers differently to two viewers — a
status visible to Alice may be hidden from Carol — so a map that survived a
switch would put Alice's answer on Carol's screen. Every read also captures the
viewer it was made for and drops its answer if the controller has moved on,
which is the case a `mounted` check does not cover: the object is alive and is
simply somebody else's now.

## What is not here

* **A description or bio.** PRIVIO has no such field: there is no column, no
  editor and no API for one. Rather than invent a place to show nothing, the
  screen omits it. Adding one is a feature of its own — a column, a privacy
  setting, an editor on the Account screen — and is not something to slip in
  behind a profile screen.
* **An online indicator.** The server reports a *moment*; "online" is a state
  inferred from it. The screen says "Last seen …" and never claims more, the
  same wording the contacts list uses because it is the same fact.

## Not verified on a device

Everything above is covered by `app/test/contact_profile_test.dart` (15 tests)
and by the contacts tests on the server. None of it has been run on a phone.
Rows P1–P6 in [`device-beta-checklist.md`](device-beta-checklist.md) are the
ones only a handset can answer.
