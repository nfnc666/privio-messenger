# The official Privio channel

One channel carries a blue verification mark, and every account is subscribed to
it once. This is how it is designated, and why it is designated the way it is.

## The badge is a uuid, never a name

`privio_official` and `privio_officia1` are one character apart. A verification
mark keyed on a **handle** or a **title** would decorate whichever of them
happened to match — including one somebody else registered specifically because
it matches.

So the designation is a row holding the channel's **id**. Every check compares
ids. The handle and the owner are stored beside it as *evidence of what was
designated*, and nothing reads them to decide anything; the operator route shows
what the handle is now against what it was, so a rename is visible rather than
silently carried.

There is no way for a client to ask for the badge. A channel created with
`"verified": true` in the body is created unverified, and a test asserts it.

## Designating it

**This cannot be done from a checkout.** The channel exists in the production
database; the id has to come from there. Two calls, both against the running
server, both as an operator with the `operators` capability:

**1. Find the candidates.**

```
GET /v1/admin/official-channel/candidates?handle=privio_official
```

Answers with every public channel whose handle or title looks like that, each
with its **id**, its **owner**, its member count, how many posts it has, and
when it was created. This route decides nothing. It is the list a human reads.

**Check the owner before going further.** That is the step the brief asks for
and it is the one a name cannot give you: the channel in the screenshot is the
right one because it is owned by the account you expect, not because it is
called what you expect.

**2. Designate it, by id.**

```
PUT /v1/admin/official-channel
{ "channelId": "<uuid from step 1>",
  "expectedHandle": "privio_official",
  "expectedOwner": "<the owner's username>" }
```

The two `expected` fields are not how the channel is found — the id is. They are
how an operator who pasted the wrong uuid finds out *before* the badge moves.
Either one wrong is a refusal that names what it actually found.

Refused as well: a channel that is private (nobody could be subscribed to it
without its key, so a badge on it says nothing to anybody), and a channel that
does not exist.

Both calls are written to the admin audit log as `official_channel.designate`,
with the handle and the owner in the detail. "Who moved the badge, and when" has
to be answerable.

### What designating does not do

Nothing to the channel. Not its picture, not its description, not its title, not
one of its posts, not one row of its membership. A test reads the whole channel
row and the whole member list before and after and asserts they are identical.
The designation is a single row in a different table.

## Subscribing everybody, once

`ensureSubscribed` runs at registration and at sign-in. It:

- writes an **offer row** for the account, and does nothing at all if one is
  already there;
- inserts a membership with `ON CONFLICT DO NOTHING`, role `subscriber`, every
  permission at its default of false;
- increments `member_count` only when a membership was actually created.

Four consequences, each of them the point:

| | |
| --- | --- |
| Existing accounts | Reached on their next sign-in. No migration touches anybody's rows. |
| The channel's owner and admins | Untouched. `ON CONFLICT DO NOTHING` means an auto-subscribe cannot demote the operator of the channel to a subscriber of it. |
| Ordinary subscribers | Gain nothing. The role is `subscriber` and no permission is set. |
| Somebody who leaves | Stays gone. The offer row is what the next sign-in looks at, and it is still there. |

## Leaving, and coming back

Leaving uses the ordinary leave route; there is no special case for the official
channel beyond recording that it was deliberate. The **offer row** is what stops
the re-add, not the opt-out timestamp — the timestamp exists because "left on
purpose" and "was offered and stayed" are different facts, and a support
question about a missing channel is answered by which one it is.

Joining again is the ordinary join route. It clears the opt-out so the record
matches what is true, and it does not re-arm anything: the one-time subscribe
has already run and looks only at whether the row exists.

## The cache

The designated id is read on nearly every channel response — a list of forty
channels asks forty times — and it changes approximately never, so it is held in
memory and refreshed when it is written.

**A deployment running several processes sees a change after each has been
through a refresh**, which in practice means after a restart. For a value set
once in the product's life that is the right trade, but it is a real property
and not an accident.

`refresh()` is awaited at start-up rather than left to the first request,
because the cache answers `verified: false` until it is filled and the one
channel that must never be answered that way is the official one.

## Where the badge appears

The channel list, the feed header, the channel profile, and the empty-feed card
— which is also what search results are, since search filters the same rows.
All four go through `ChannelName`, so "the badge sits directly after the name"
is true in one place rather than four.

The colour is a fixed blue, deliberately **not** the account's accent. The
accent is the user's choice and differs per account; a badge drawn in it would
be a different colour on every phone and would mean nothing consistent.

## What is tested

`server/test/official_channel.test.ts`, 19 tests: designation by id with the
owner confirmed, refusal on a wrong owner and on a wrong handle, that
designating changes nothing about the channel, that the badge does not follow a
name, that it cannot be claimed by asking, automatic subscribe for new and
existing accounts, that the owner is not demoted, that the member count moves
once, that leaving survives a sign-in, that rejoining works, and that leaving
again is still permanent.

Confirmed load-bearing by keying the badge on presence rather than id, and by
removing the offer-row guard: four of the nineteen go red.

`app/test/verified_badge_test.dart`, 6 tests, including that a channel with an
identical title and no designation shows nothing.
