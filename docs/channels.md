# Channels

What a channel is in Privio, what its four screens do, and — at the end, in
detail — what is plumbed but not finished, and why.

## The screens

Built from four supplied designs and sharing the existing channel system: one
controller, one service, one set of server routes. There is no second channel
implementation anywhere in the app.

**Profile.** The channel's front page, reached by tapping the header in its feed
or from the overflow menu. A 96-point picture, the name, the audience, four
equal actions (livestream, mute, search, more), the share link with its QR, the
management rows, and a Media/Links segment over what the channel holds. Media is
a three-column grid — each tile fetches and decrypts its own file, because a
post carries an attachment's *size*, not its bytes. Links are every URL anybody
posted, each one a way back to the post it was written in.

It deliberately does not re-implement the sheets that live on the feed. Asking
for invites, statistics, reporting, reactions or an ownership transfer pops back
with a name and the feed opens the one that already exists. Two copies of a
confirmation dialog are two chances for them to say different things.

**Edit.** Cancel and Done, not save-as-you-type: a name, a welcome message and
whether posts carry a signature all change what other people see. Nothing
reaches the server until Done, the picture included, so Cancel really is a
cancel.

**Admins.** Eight permissions, one row each. The two rules the server enforces
are shown rather than hidden — a switch for something the actor does not hold is
drawn off and disabled with *"you do not hold this yourself"*, and somebody who
outranks you cannot be edited at all. The list shows who appointed each admin.
The owner's badge is a different colour because it is a different thing: an
admin can be dismissed and the owner cannot.

**Subscribers.** Contacts first, everybody else after, paged as you scroll and
searched on the server. A subscriber is told plainly that what they see is not
the whole list.

## Permissions

Eight flags, checked on the server on every route. None of them is granted by a
migration: everything added in 025 defaults to false, so an existing admin kept
exactly what they had.

| Flag | What it decides |
|---|---|
| `canPost` | Publishing, editing and scheduling their own posts |
| `canEditChannel` | Name, picture, description, settings |
| `canDeletePosts` | Removing posts, including other people's |
| `canModerateDiscussion` | Removing comments and silencing people in a thread |
| `canManageMembers` | Adding, removing and silencing subscribers |
| `canManageInvites` | The link, its limits, and who is waiting |
| `canManageLivestreams` | Starting and ending them |
| `canAppointAdmins` | Making somebody else an admin |
| `canDeleteChannel` | Deleting it |

Three of these were split out of flags that bundled decisions which are not the
same decision. `canAppointAdmins` was inside `canManageMembers`, which meant an
admin brought in to remove a spammer could appoint a second admin who could
remove *them*. `canModerateDiscussion` fell out of `canDeletePosts` — a
different act on different content. `canManageInvites` was also inside managing
members, and setting a link's limits is not the same as removing somebody.

**Nobody may grant a permission they do not hold**, and nobody may rewrite
somebody who holds more than they do. Both are enforced in one transaction under
the channel's row lock, so two admins demoting each other at the same moment
cannot leave the channel with neither able to manage anybody. `withinAuthority`
iterates over whatever keys exist, so adding a flag does not need another line
of code to be covered by the rule.

`canAppointAdmins` is never in the default set for a new admin. It is the one
permission that multiplies itself.

## What the server can and cannot see

A **public** channel's title, handle and description are plaintext columns,
because a public channel is searchable by name and search cannot run over
ciphertext. Its picture is stored unsealed for the same reason: it is drawn on
the invite page and in link previews, where nobody holds a key.

A **private** channel's name is sealed with the channel key and lives in
`encrypted_metadata`, re-sealed on every rotation. Its picture is withheld from
non-members rather than encrypted — an authorisation rule, which is a weaker
promise than encryption and is written down as such. Posts, comments and
attachments are end-to-end encrypted in both.

Three columns added for these screens are readable, and `schema.test.ts` — which
fails on any new readable column — carries each with its reason:
`welcome_message` (public channels only; the route refuses to write it for a
private one), `accent_name` and `background_name` (token names from a fixed
list, held to it by a check constraint), and `live_room` (a random id on the
media server, not derived from the channel).

## Muting

Per account and per channel, not per device: somebody who silenced a channel on
their phone did not mean "until I pick up my laptop". A row with `until` null is
muted with no end; a row whose `until` has passed is not muted and is left for
the sweep rather than deleted on read, so a read path never writes.

**What it governs today is the app, not a push.** Channel posts do not generate
server push notifications at all yet — the bus is used for key requests and
nothing else — so there is no fan-out for the mute to suppress. The setting is
stored, synced across devices, and honoured by the app; wiring it into a push
path is part of the unread/notification work that is still outstanding.

## Adding subscribers

Only where the person's **own** `whoCanAddMeToGroups` allows it. `contacts`
means *their* address book, not yours — being added by a stranger to something
you have never heard of is exactly what the setting exists to stop. Somebody who
has blocked the person adding them is never added whatever their setting says,
and is not told it was tried.

The call answers two lists, `added` and `invite`, and the screen reports both.
It never says "added" when half of them were not.

## Presence

`lastSeenAt` on a member is decided by the **target's** privacy setting, never
by the viewer's rank: running a channel is deliberately not a reason to see
more. Null is the ordinary answer rather than an error, and the row shows
nothing at all rather than guessing — not knowing is not the same as knowing it
was a long time ago. The rule lives in `services/presence.ts` and is read by the
profile lookup, the contacts list and the channel member list, because a privacy
rule with three implementations has two that are wrong.

---

# Not finished, and why

Three things on these screens are honest rather than complete. Each says so on
screen; none of them is a button that quietly does nothing.

## Livestreams — needs a media server

**What works.** The permission, the start/end routes, the room, the token, and
the state on the channel. `GET /v1/channels/:id/live` answers what this account
may do, `POST` starts one under the channel's row lock (so two admins pressing
start cannot make two rooms and split the audience), `DELETE` ends it. Tokens
are LiveKit access tokens — plain HS256 JWTs, scoped to one room and one
identity, written out rather than pulled from a vendor SDK so there is no
dependency in the signing path.

**What is missing, concretely:**

1. **An SFU.** A 1:1 call is two devices and a TURN relay. A channel broadcast
   is one publisher and every subscriber, and a publisher cannot upload the same
   stream three hundred times — it needs a server that takes one stream in and
   forwards it. No amount of client code substitutes for one.

   To enable: set `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`.
   Half-configured is refused at start-up, because half-configured is worse than
   unconfigured: it looks like it works. With none set, every route answers
   `available: false` or `livestream_unconfigured`, and the app's control opens
   a note explaining why rather than an empty screen.

2. **A client.** Privio has no SFU client. The app can obtain a room and a token
   and does; it cannot yet send or render video, and the dialog says exactly
   that instead of showing a black rectangle. This is its own piece of work.

3. **It would not be end-to-end encrypted.** The media passes through the SFU,
   which can see it. That is a real step down from everything else in this
   codebase, which is why starting a stream is a deliberate act by an admin
   rather than a setting — and why it is stated here rather than glossed.

**Nothing has been provisioned, purchased or deployed.**

## Auto-translation — needs a decision, not just a key

Translating a post means sending what it says to a translation service. Privio's
server holds ciphertext and no key, so it *cannot* do that even if configured —
which is the point. It would have to happen on the device, and the text would
leave it in the clear.

So the row is not a switch. It says auto-translation is not set up, explains
that translating means sending the text to a third party, and states that no
post has been sent anywhere. `TRANSLATION_URL` exists in the config for a
deployment that wants to offer one, and reaching a working feature needs all
three of:

1. the operator to configure an endpoint;
2. per-channel opt-in by an admin;
3. **per-reader consent**, because it is the reader's device that would send the
   text, and a channel admin cannot consent on their behalf.

Showing the original alongside a translation is trivial once there is one — the
original is what the device already holds. It is not built, because there is
nothing to translate with.

## The channel inbox — server done, screen not

`POST/GET/PUT /v1/channels/:id/inbox` exist and are tested: messages are sealed
by the sender before they arrive, the server stores bytes and who sent them,
only an admin who may manage members can read them, the inbox is closed until an
admin opens it, and somebody silenced in the channel is silenced in its inbox
too — or the inbox is the way around being silenced.

The **Direct messages** switch on the edit screen opens and closes it, which is
real. What is missing is the admin-facing screen that reads the inbox and
replies under the channel's identity. Until that exists, an admin can accept
messages and has nowhere in the app to read them, so leaving the switch off is
the sensible default and is the default.

## Other known gaps

- **Public ↔ private cannot be switched.** The edit screen says so rather than
  offering a toggle. Making a private channel public would publish a name that
  has been sealed for everyone in it; making a public one private cannot unsay a
  name and description that have been readable. Creating the other kind is the
  honest path.
- **There is no translation structure in the app.** All strings on these screens
  are English literals, like the other ~35 screens. The brief asked for the
  existing localisation structure to be used; there is not one, and inventing a
  half-layer for four screens would be worse than not having it. Localising the
  app is its own project.
- **Media and Links are built from the posts already loaded**, so they cover the
  history this device has fetched rather than the channel's whole archive.
- **The mute has no push to suppress yet**, as above.
