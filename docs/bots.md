# Bots

A bot is an account somebody else operates over an HTTP API. It has a username,
a display name, a picture and a chat, and it is marked **BOT** everywhere it
appears.

## Read this first: a bot chat is not end-to-end encrypted

This is the one thing about the feature that cannot be left to be inferred.

An ordinary Privio message is sealed for a device holding Signal keys. The
server relays ciphertext and can read none of it. A bot is a program on
somebody else's server, reached over HTTP — it holds no Signal keys, and for it
to receive a sealed message **this server would have to hold the bot's identity
key and open the envelope on its behalf**. That is precisely the capability the
whole design exists to deny itself.

So bots do not get a weaker version of the encrypted path. They get a different
path:

- Bot messages live in `bot_messages`. They are plaintext. This server can read
  them, and so can whoever runs the bot.
- They **never touch `envelopes`**, which continues to hold only ciphertext.
  That separation is asserted by a test: if `/v1/bot/send` ever starts writing
  an envelope, the two paths have been merged and the guarantee that
  `envelopes` is opaque is gone.
- The app says so, in plain words, before the first message to a bot is sent.
  Not in a settings screen somewhere — in front of the person, at the moment it
  becomes true for them.

Ordinary chats, groups and channels are completely unchanged by any of this.

### What it would take to do better

End-to-end encrypted bots are possible and this is what they need:

1. The bot runs a Signal client of its own, holding its identity key on the
   operator's infrastructure — not here.
2. It registers as a device of its account through the ordinary prekey flow, so
   the server only ever sees ciphertext addressed to it.
3. The API stops being "send me the text" and becomes "here is a sealed
   envelope", which means a Signal implementation in whatever language the
   operator writes bots in.

That is a real piece of work and it is not in this change. Until it exists, the
honest position is the one above: bot conversations are readable, and they say
so.

## What a bot may and may not do

| | |
| --- | --- |
| Open a conversation | **No.** A bot may only reply to somebody who wrote to it first, or pressed **Start**. |
| Read past history | **No.** It receives messages sent to it after contact, and nothing from before. |
| Be stopped | **Yes.** Stopping withdraws the licence to reply *and* stops delivery, including anything that was already queued. Writing to it again starts it over. |
| Be blocked | **Yes.** Blocking removes the licence to reply; the bot is refused again. |
| Send rate | 30 messages a minute, per bot, across every conversation. |
| Message types | Text, up to eight buttons per message, pictures and files up to 8 MB, and polls. A poll is **not anonymous to the bot**: it is told who picked what, and the card says so. A person can send a bot only **text**, a button press or a poll answer. |
| When an account is deleted | Its conversations with bots, its button presses, its poll answers and its licence for bots to write go with it. What a bot's operator already received is theirs and out of reach either way; the copy on this server is not. |
| Groups and channels | Only explicit commands, mentions and replies are delivered — not the whole conversation. Adding a bot needs the matching admin right. |

The "may not open a conversation" rule is enforced in one place,
`bots.mayWriteTo`, so it cannot be true on one route and false on another. The
row in `bot_contacts` is the record of the human having written first.

## Using a bot

A bot is opened by its **exact** `@username` — from *Settings → Bots → Open a
bot*, or by tapping a bot's profile, where *Message* leads here rather than to an
encrypted chat. There is no prefix search and no directory, for the same reason
there is none for people: a browsable list of every bot on a deployment is a
browsable list of every operator on it.

What the screen shows before anything is sent: the name with the **BOT** label,
the `@username`, the description the owner wrote, the commands the bot published,
and one sentence saying that whoever runs it can read what is sent to it. Then a
**Start** button — and *no text field*, because a bot cannot write before it is
started and a screen that looked ready to chat would be inviting somebody to
decide before they had read anything.

**Start** delivers `/start` as an ordinary message, which is how a bot knows to
introduce itself. **Stop** withdraws the licence to reply and stops delivery,
including messages that were waiting undelivered — a stop that let the queue
drain afterwards would be a stop the operator still hears through. Writing to a
stopped bot starts it again, which is the right way round: somebody typing to a
bot has decided to talk to it. Blocking is the stronger thing and goes through
the account block list, which no message can undo.

### Pictures and files

A bot uploads the bytes, then sends a message pointing at them. **The bytes are
not encrypted** — everything on the bot path is plaintext this server can read,
and a file is no different; sealing it to look like the rest of Privio while the
bot holds the key would be the dishonest option. Migration 040 says so where the
column is defined.

What *is* narrow is who may fetch it. The id is not the capability: the rule in
`mayDownload` is a `bot_messages` row saying this bot sent this object to this
account. So an upload nobody has been sent is the bot's own, a stranger holding
the id gets a 404, and so does the bot's owner — they are a person like any
other here.

When the blob ages out, the message stays in the conversation as a message whose
file is gone. That is deliberate: hiding the message would hide that the bot
sent something.

### Buttons

A bot's message can carry up to eight buttons. The requirement is attribution,
and it comes from the primary key of `bot_button_presses` rather than from a
check in a route: **one message, one account, one button id**.

* A button id that the message does not carry is refused. A caller cannot invent
  an action by naming one.
* A direct message's buttons are pressable only by the person it was addressed
  to; in a group, by a member of that group.
* A second press by the same person is answered `already` and delivers nothing.
  Two *different* people pressing the same button in a group are two presses.
* Somebody who stopped or blocked the bot cannot press their way back in.

A press is delivered through the same `bot_messages` row and the same take-once
delivery as a typed message, so a bot sees presses and messages in the order they
happened. It is not drawn as a line in the conversation — the person did not
write the button id, and a bubble saying `yes` would be the app putting words in
their mouth. The bot's answer is what shows. A pressed button is drawn as pressed
and disabled, because the server refuses a second press and a live-looking button
that does nothing is worse than one that looks spent.

Writing a bot that uses them: [bot-api.md §5a](bot-api.md#5a-buttons).

## Bots in groups

A bot in a group is a different problem from a bot in a private chat, and the
difference is not a policy choice:

**This server cannot hand a bot a group message.** Not "does not" — cannot. A
group's messages are Signal ciphertext addressed to member devices, and the
group key seals only the name and the description. A bot reached over HTTP is
not a device and holds neither. There is no key here that opens a group
message.

So the only party that can give a bot a group message is the **device that
wrote it**, which had the plaintext. That is where the filter lives:
`addressesBot` in `app/lib/models/group_bot.dart` runs on the sender's phone,
before anything leaves it.

### Delivery filter or cryptographic restriction

The brief this was built to asks not to blur these, and they are genuinely
different things:

| | |
| --- | --- |
| **Delivery filter** | A server choosing what to pass on. The bot holds the keys either way, and whoever runs the server can change their mind. This is the usual arrangement elsewhere. |
| **Cryptographic restriction** | The bot holds nothing that opens the rest. Changing the filter cannot retroactively give it anything. |

What Privio has here is the second one. A bot receives a group message because
somebody's device handed that one message over, and it receives nothing else
because nothing else was ever offered to it.

`reads_all_messages` does not change that. It widens what the members' devices
forward — every new message instead of only the addressed ones — and the app
says so in those words, twice, before an admin turns it on. It is not a key.

**Past messages are never forwarded by any setting**, because forwarding
happens at send time: a message sent before the bot arrived was never offered
to it and there is no path that goes back for it.

### What addresses a bot

Three things, and they are the three anybody would expect:

1. a command — a message starting with `/`. `/help@name` picks one bot; a bare
   `/help` goes to every bot in the group, because guessing which one it was
   for would send somebody's command to a bot they were not talking to;
2. a mention of the bot by its exact `@username`, found by the same tokenizer
   the chat draws mentions with — so a name inside a URL or a code span is not
   one here either;
3. a reply to one of the bot's own messages.

### Rights

Five, each its own column and each defaulting to false:

| | |
| --- | --- |
| `may_send` | write in the group |
| `may_moderate` | delete messages |
| `may_restrict_members` | restrict members |
| `may_manage_invites` | manage invite links |
| `reads_all_messages` | receive every new message rather than the addressed ones |

**Adding a bot grants nothing.** Rights are a separate call, and there is
deliberately no shape that grants all of them at once — that is how a bot ends
up with every admin right because somebody needed one of them. Only group
admins may add a bot or change its rights; `groupRightsOf` is the single place
the question is answered and every route asks it on the call that uses it,
never remembering an answer from when the right was granted.

Every member may *see* the list. Somebody writing in a group is entitled to
know who receives it.

### Removing a bot

Delivery stops: the members' devices read the list before they forward, and
every route that acts on the bot's behalf now gets null from `groupRightsOf`.

**No group key is rotated, and none needs to be.** The bot never held one.
What it already received is a copy on somebody else's server, and no re-keying
here reaches it — which the removal dialog says rather than implying otherwise.

### What each right actually does

| Right | |
| --- | --- |
| **Send messages** | `POST /v1/bot/send` with a `groupId`. Checked on every send. |
| **Restrict members** | `GET /v1/bot/group/members` and `POST /v1/bot/group/members/remove`. The member list is behind the *same* right as removing somebody, not readable for merely being present: a list of who is in a group is exactly what a bot should not get for being added to it. |
| **Manage invites** | `POST /v1/bot/group/invite/rotate` — the same renewal an admin has. A moderation bot that notices a link being spammed can close that door immediately rather than at whatever hour an admin reads about it. |
| **Delete messages** | **Refused.** See below. |

Three rules a bot is held to that a human admin is not, because a bot is a
program somebody else runs and a mistake or a compromise in it must not be able
to empty a group:

* it may not remove an **admin** — a bot that could would be a bot that can take
  over a group by removing everybody able to switch it off;
* it may not remove **itself**;
* every call re-reads the right, so an admin who withdraws one breaks the bot's
  *next* action rather than the one after it notices.

No group key rotation on a removal, and that is not an oversight: a group's key
seals the name and the description, the bot was never given it, and the messages
are per-device Signal ciphertext. Removing a member changes who the *members'
devices* will seal to next, which is their decision, made with the member list
that route just changed.

### Why a bot cannot delete other people's messages

`may_moderate` is **refused** when an admin tries to grant it —
`right_not_available` — rather than stored and left inert. A permission somebody
agreed to that quietly does nothing is worse than no permission.

A deletion in Privio is an encrypted protocol message to every member's devices,
and the rule those devices enforce is that **only the author may delete for
everyone**: a protocol that let anyone delete anyone's messages would be a way to
erase a conversation you were losing. A bot holds no group key and no Signal
session with the members, so it cannot send that message at all, and no
server-side flag changes that. The switch is still shown in the app, disabled,
with that sentence under it — leaving it out would leave an admin wondering.

When a bot can be a cryptographic endpoint of its own (see *What it would take
to do better* above), this is the check to revisit. Not before.

## Tokens

- Generated by the owner, shown **once**, and stored only as a SHA-256 digest.
- Never written to a log, and never put in a chat message — including in the
  conversation with @botcreator, which finishes with an instruction to the app
  to open its protected sheet rather than with the token itself.
- A new token **replaces** the old one. Rotating after a leak has to stop the
  leaked one; a "new token" that left the previous one live would be an extra
  key, not a replacement.
- Revoking is immediate: `botForToken` filters on `revoked_at IS NULL` in the
  query rather than checking afterwards, where somebody could forget it.

## @botcreator

A reserved system account, created by migration 029 and **ensured at every
start-up** — a one-time insert is a fragile home for an account the product
depends on, since anything that truncates or restores `accounts` would lose it
with nothing to bring it back.

`reserved_usernames` also holds `privio`, `support`, `admin`, `system`, `help`
and `security`. Registration refuses them with the same "already in use" every
other collision gets: naming the list would confirm it to anybody probing, and
the person signing up needs a different name either way.

The assistant is a state machine in `services/botcreator.ts`, not a model. Given
the same state and the same text it produces the same reply, which is what makes
the whole flow testable without a chat screen. It supports `/start`, `/newbot`,
`/mybots`, `/setname`, `/setdescription`, `/setuserpic`, `/setcommands`,
`/token`, `/revoke`, `/deletebot` and `/cancel`.

A command always wins over whatever step the conversation was in, so somebody
who started `/newbot` and changed their mind is never stuck inside it.

## The API

Authentication is `Authorization: Bearer <token>`. A token is not a session: it
cannot reach the owner's routes, and a session cannot poll for updates.

| Route | |
| --- | --- |
| `GET /v1/bot/me` | who this token belongs to, and its commands |
| `GET /v1/bot/updates?timeout=25&limit=100` | long poll; answers the moment anything arrives, or empty at the deadline |
| `POST /v1/bot/send` | `{to, text, groupId?}`; refused with `not_contacted` until the person has written first |
| `PUT`/`GET`/`DELETE /v1/bot/webhook` | deliver to an HTTPS URL instead of polling |

Updates are delivered **once**: the take is a single `UPDATE … RETURNING` over
`FOR UPDATE SKIP LOCKED`, so two pollers cannot both receive the same row — and
neither can a poller and a webhook.

Polling first, webhooks second, and the reason is the same one either way: the
delivery bus exists and could carry this, but a second path for a feature that
was not yet in use would have been a second thing to get wrong. Polling costs
one query a second per connected bot and needs nothing of the bot's host — no
public address, no certificate, no open port. A webhook is for people who have
a reason to want one.

A webhook URL is a URL this server will fetch from inside its own network, so
`util/outbound.ts` — the same guard the push endpoints use — insists on `https`
and a public address, refuses credentials in the URL, refuses to follow a
redirect, and **re-checks the address before every delivery** rather than only
at registration. Deliveries are signed over `"{timestamp}.{body}"` with a secret
shown once, so a captured delivery cannot be replayed later.

**Writing a bot: [bot-api.md](bot-api.md).** Setup, hosting, the routes, long
polling, webhooks and signature verification, rate limits, what was tested and
what is not built yet. The Python package is `bot-sdk/privio_bot`, with two
runnable examples: `examples/greeter.py` and `examples/webhook_receiver.py`.

## What is tested

`server/test/bots.test.ts`, 23 tests against a real Postgres: the reservation of
@botcreator and the other names, an account nobody can sign into, ownership on
every write, a token that authenticates the bot and cannot reach the owner's
routes, revocation taking effect at once, rotation killing the previous token,
digests rather than plaintext in the table, the may-not-open-a-conversation
rule and blocking closing it again, updates delivered exactly once and never
crossing between bots, the assistant's whole creation walk, a token never
appearing in a message, `/deletebot` requiring the username typed back, and
`/v1/bot/send` leaving `envelopes` untouched.

Confirmed load-bearing by breaking two rules at once — ignoring `revoked_at` and
making `mayWriteTo` return true — and watching four of the 23 go red.
