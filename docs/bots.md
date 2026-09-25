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
| Open a conversation | **No.** A bot may only reply to somebody who wrote to it first. |
| Read past history | **No.** It receives messages sent to it after contact, and nothing from before. |
| Be blocked | **Yes.** Blocking removes the licence to reply; the bot is refused again. |
| Send rate | 30 messages a minute, per bot, across every conversation. |
| Groups and channels | Only explicit commands, mentions and replies are delivered — not the whole conversation. Adding a bot needs the matching admin right. |

The "may not open a conversation" rule is enforced in one place,
`bots.mayWriteTo`, so it cannot be true on one route and false on another. The
row in `bot_contacts` is the record of the human having written first.

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

### What is still missing here

Bots cannot yet moderate, restrict or manage invites *through the API* — the
rights exist, are stored, are enforced on every call and are shown in the UI,
but the routes a bot would call to use them are not written. `may_send` is the
one that is wired end to end. The others refuse rather than pretending, which
is the correct failure direction, and they are the next piece of work rather
than a finished feature.

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
