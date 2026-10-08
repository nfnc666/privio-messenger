# The Privio bot API

For people writing a bot. What a bot *is* in Privio, and what it can and cannot
see, is in [bots.md](bots.md) — read the first section of that file before this
one, because the honest answer about encryption decides whether a bot is the
right thing for your problem at all.

Short version, repeated here so nobody builds on a wrong assumption:

> **A conversation with a bot is not end-to-end encrypted.** The text lives in
> `bot_messages` in plaintext and the Privio server can read it. It never
> touches `envelopes`, the table the encrypted messages go through. In a group,
> a bot receives only what a member's device chose to hand over, and holds no
> group key — see [bots.md](bots.md#delivery-filter-or-cryptographic-restriction).

---

## 1. Setting up

### Create the bot

In the app, write to **@botcreator** and send `/newbot`. It asks for a display
name and a `@username`, and finishes by handing the token to the app's protected
sheet — not into the chat, where it would sit in a message history.

Or, with a session token, over HTTP:

```bash
curl -X POST https://your-server.example/v1/bots \
  -H "authorization: Bearer $SESSION_TOKEN" \
  -H "content-type: application/json" \
  -d '{"name": "Greeter", "username": "greeterbot"}'
# {"id":"…uuid…","username":"greeterbot"}

curl -X POST https://your-server.example/v1/bots/$BOT_ID/token \
  -H "authorization: Bearer $SESSION_TOKEN"
# {"token":"…43 characters…"}   ← shown once
```

### The token

* Shown **once**. The server keeps a SHA-256 digest, so it cannot show it again
  and neither can anybody who reads the database.
* Issuing a new one **replaces** the old one. Rotation that left the previous
  token alive would be an extra key, not a replacement.
* `DELETE /v1/bots/:id/token` revokes immediately.
* Keep it in an environment variable or a secrets manager. **Never** in a URL,
  in a log line, in a commit, or in a chat message — see §6.

### Point the library at it

```bash
cp -r bot-sdk/privio_bot /opt/privio-bots/    # or add bot-sdk to PYTHONPATH
export PRIVIO_BOT_TOKEN=…
export PRIVIO_BASE_URL=https://your-server.example
```

There is no package to install and nothing to pip. `bot-sdk/privio_bot` is a
plain Python package with no dependency beyond the standard library, and that is
deliberate: a bot token is a credential, and a credential handler with a
dependency tree is a credential handler with a supply chain. Tested on Python
3.11.

---

## 2. Hosting a bot

A Privio bot is a program you run. Privio does not run it for you and has no
way to: it holds no code of yours and never will.

Three shapes, in order of how much you need:

| | What you need | When |
| --- | --- | --- |
| **Long polling** | A machine with outbound HTTPS. No public address, no TLS certificate, no open port. | Almost always. Start here. |
| **Webhooks** | A public HTTPS URL with a valid certificate. | Many bots on one host, or a serverless function that should not stay running. |
| **Both** | — | Not supported. A webhook takes the updates; a poller then finds nothing. |

A long-polling bot behind a home router or inside a container with no inbound
route works perfectly well. Reach for webhooks when you have a reason, not by
default.

### As a service

```ini
# /etc/systemd/system/privio-greeter.service
[Unit]
Description=Privio greeter bot
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/privio-bots/examples/greeter.py
# The token is read from here, not from the unit file: `systemctl cat` and
# `systemd-analyze` print the unit to anybody who can read it.
EnvironmentFile=/etc/privio/greeter.env
User=privio-bot
Restart=always
RestartSec=5
# It needs the network and nothing else.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
```

`/etc/privio/greeter.env` holds `PRIVIO_BOT_TOKEN=…` and `PRIVIO_BASE_URL=…`,
owned by the service user and `chmod 600`.

The library re-raises on `401`/`403` rather than looping, so a revoked token
stops the process instead of hammering the server — with `Restart=always` that
becomes a restart loop, which is visible in `systemctl status`. A silent bot
that keeps retrying forever is the failure mode worth avoiding.

---

## 3. The routes

Authentication is `Authorization: Bearer <bot token>`. A bot token is **not** a
session: it cannot reach the owner's routes (`/v1/bots…`), and a session cannot
poll for updates. Both directions are tested.

| Route | |
| --- | --- |
| `GET /v1/bot/me` | who this token belongs to, and its command list |
| `PATCH /v1/bot/me` | publishes the command menu: `{commands: [{command, description}]}` |
| `GET /v1/bot/updates?timeout=25&limit=100` | long poll; answers the moment anything arrives, or empty at the deadline |
| `POST /v1/bot/send` | `{to, text, groupId?, buttons?, mediaId?, mediaKind?, fileName?}` → `{messageId}`; with `poll` or `pollId` instead of buttons and media → `{messageId, pollId}`, and `text` becomes optional |
| `GET /v1/bot/polls/:pollId` | one poll of this bot with its tally: `{question, options, counts, voters, closed, …}` |
| `POST /v1/bot/polls/:pollId/close` | stops it taking answers, for good; closing again is harmless |
| `POST /v1/bot/media?kind=&name=` | raw bytes → `{mediaId, byteSize, …}` |
| `GET /v1/bot/group/members?groupId=` | who is in a group. Needs *Restrict members* |
| `POST /v1/bot/group/members/remove` | `{groupId, accountId}`. Needs *Restrict members* |
| `POST /v1/bot/group/invite/rotate` | `{groupId}` → `{inviteCode}`. Needs *Manage invites* |
| `PUT /v1/bot/webhook` | `{url}` → `{url, secret, note}`; the secret is shown once |
| `GET /v1/bot/webhook` | status: URL, failures, last attempt, last error. Never the secret |
| `DELETE /v1/bot/webhook` | back to polling |

### An update

```json
{
  "updates": [
    {
      "updateId": 41,
      "chat": { "accountId": "…uuid…", "username": "ada" },
      "scope": "group",
      "scopeId": "…uuid…",
      "text": "/weather@greeterbot Berlin",
      "command": { "name": "weather", "addressedTo": "greeterbot", "args": "Berlin" },
      "at": "2026-03-04T10:15:00.000Z"
    }
  ]
}
```

`command` is parsed **server-side** and is `null` unless the text begins with a
slash. It is parsed once, centrally, so that every bot agrees with the app about
what `/help@name` means in a group holding several bots — a parser per bot is a
parser that eventually disagrees with the one that decided whether to forward
the message at all.

In a group, `scope` is `"group"` and `scopeId` names it. `chat.accountId` is
always the person who wrote, and it is what you pass as `to` when replying.

### Replying

```bash
curl -X POST https://your-server.example/v1/bot/send \
  -H "authorization: Bearer $PRIVIO_BOT_TOKEN" \
  -H "content-type: application/json" \
  -d '{"to": "…accountId…", "text": "Hello", "groupId": "…or omitted…"}'
```

| Refusal | Meaning |
| --- | --- |
| `401 unauthenticated` | no token, or a revoked one |
| `403 not_contacted` | the person has not written to this bot, or blocked it. **A bot cannot open a conversation.** |
| `403 not_in_group` | the bot is not a member of that group |
| `403 missing_right` | it is a member, but without *send messages* |
| `429 rate_limited` | over 30 messages a minute, counted per bot across every conversation |

Group rights are checked **on the call**, not remembered from when the bot was
added: an admin who takes a right away breaks the next send, not the one after
the bot happens to notice.

---

## 3a. Moderating a group

Three routes, each behind a right an admin grants separately in the group's bot
screen. Nothing here works by being in the group; every call re-reads the right.

```python
for member in bot.group_members(group_id):          # needs Restrict members
    if member["removable"] and is_spammer(member["username"]):
        bot.remove_member(group_id, member["accountId"])

new_code = bot.rotate_invite(group_id)              # needs Manage invites
```

| Refusal | Meaning |
| --- | --- |
| `403 not_in_group` | the bot is not a member of that group |
| `403 missing_right` | it is a member, but without that right |
| `403 cannot_remove_admin` | the target is an admin. Ask an admin to do it |
| `403 not_itself` | a bot cannot remove itself from a group |
| `404 member_not_found` | not a member — a wrong id is not a silent success |

`removable` is on every member entry so a bot does not have to find out by being
refused. Admins are never removable by a bot, and neither is the bot itself.

**Deleting other people's messages is not available at all** — not as a route
and not as a right. See §9.

## 4. Long polling

```python
import os
from privio_bot import Bot, Update

bot = Bot(os.environ["PRIVIO_BOT_TOKEN"], os.environ["PRIVIO_BASE_URL"])

def handle(bot: Bot, update: Update) -> None:
    if update.command and update.command.name == "start":
        bot.reply(update, "Hello. /help lists what I can do.")

bot.run(handle)
```

`run()` loops forever; `poll()` yields updates if you want the loop yourself.
Both:

* hold the request open for up to `timeout` seconds (max 30) and return the
  moment something arrives;
* treat an empty answer as normal, not as an error;
* back off exponentially on a network failure or a 5xx, and start again when the
  server comes back;
* **re-raise** on 401 and 403 — see §2 for why.

An update is delivered **once**. The take is a single `UPDATE … RETURNING` over
`FOR UPDATE SKIP LOCKED`, so two pollers cannot both receive the same row — and
neither can a poller and a webhook. There is no offset to acknowledge and no
`getUpdates(offset=)` as in some other APIs: what you were handed is yours, and
if your process dies holding a batch, that batch is gone. Write the work down
before you answer if it matters.

`limit` caps a batch at 100; more than that waits for the next call. Two polls
by the same bot inside the same second are collapsed server-side to one query,
so opening several concurrent polls buys nothing.

---

## 5. Webhooks

```python
secret = bot.set_webhook("https://bots.example.com/privio")
print(secret)   # 64 hex characters, shown once
```

### What the server insists on

* **`https://` only.** An `http://` URL is refused outright.
* **A public address.** A URL that resolves to `127.0.0.1`, `10.x`, `192.168.x`,
  `172.16–31.x`, `169.254.169.254` (the cloud metadata address), `::1` or an
  IPv4-mapped IPv6 form of any of those is refused. The check runs again
  **before every delivery**, because a name that resolves publicly today may
  resolve to `10.0.0.5` tomorrow, and that request is the one that would go
  there.
* **No credentials in the URL.** `https://user:pw@host/` is refused.
* **No redirects.** A delivery is `redirect: 'error'`: a receiver that answers
  `302` does not get followed to wherever it points.

The refusal is a flat `400 invalid_webhook` in every case, and it deliberately
does **not** say what the name resolved to. Answering that in detail would turn
the route into a network scanner for whoever holds a bot token.

### What arrives

```
POST /privio HTTP/1.1
content-type: application/json
x-privio-timestamp: 1772620500000
x-privio-signature: sha256=8f3c…

{"updates":[ … same shape as §3 … ]}
```

Up to 50 updates per delivery. The bot's token is **not** in the request: a
receiver learns how to verify a delivery and nothing that would let it act as
the bot.

### Verifying — do this before reading the body as anything but bytes

The signature is HMAC-SHA256 over `"{timestamp}.{body}"`, not over the body
alone. A signature over the body alone is valid forever, so a delivery captured
once can be replayed at leisure; including the timestamp lets you reject
anything old.

```python
from privio_bot.webhook import verify

if not verify(SECRET, timestamp_header, raw_body, signature_header):
    return 401          # no detail: saying *why* helps whoever is guessing
```

`verify` compares with `hmac.compare_digest` and rejects a timestamp more than
five minutes from now. `bot-sdk/examples/webhook_receiver.py` is a complete
receiver using only the standard library — roughly a hundred lines, including
why each refusal is silent.

### Failures and back-off

Anything other than a 2xx — a 500, a timeout after 8 seconds, a TLS failure, a
redirect — counts as a failure. The count is visible on `GET /v1/bot/webhook`
along with the last status and a truncated error.

Retries are **not** per-delivery: a failed batch has already been taken and is
not re-sent. What backs off is the *hook*, which is tried every 2ⁿ ticks after n
consecutive failures, up to once every five minutes, and goes back to every
second on the first success. A receiver that is down for an hour therefore costs
a handful of requests rather than three and a half thousand.

That trade is worth stating plainly: **it means a delivery to a broken receiver
is lost, not queued.** If your bot must not lose anything, use long polling,
where the same "taken once" rule applies but the taking happens when your
process is up and asking.

---

## 5a. Buttons

A message can carry up to eight buttons. They belong to that message and cannot
be changed afterwards — a label that changed under somebody about to press it
would be a button that did something other than what it said.

```python
bot.reply(update, "Pick one:", buttons=[("weather", "The weather"), ("time", "The time")])
```

`id` is yours and comes back on a press; `label` is what the person reads. Two
buttons with the same id are refused when the message is sent, because a press
of either could not be told from the other.

A press arrives as an ordinary update with `button` set and `text` empty:

```python
if update.button:                       # a press, not something typed
    if update.button.id == "time":
        bot.reply(update, "...")
    # update.button.message_id names the message it was under.
```

Three things the server settles before your code sees a press, so that your code
does not have to:

* **Which bot, which message, which person.** The button has to be one that
  message actually carries, the message has to be this bot's, and a direct
  message's buttons are pressable only by the person it was addressed to — in a
  group, by a member of that group. The press names who pressed.
* **Once.** A second press of the same button by the same person is answered
  `already: true` and delivers nothing. Two different people pressing the same
  button in a group are two presses, which is the point of a button on a message
  several people can see.
* **Not after a stop.** Somebody who stopped or blocked the bot cannot press
  their way back in.

What a button is not: a channel back to the bot that bypasses anything. It is
delivered through the same `bot_messages` row and the same take-once delivery as
a typed message, in the order it happened.

## 5b. Pictures and files

Two steps: the bytes go up on their own, then a send points at the object. A
single multipart route would mean holding a file in memory before deciding
whether the bot may write to that person at all.

```python
bot.send_photo(update.account_id, png_bytes, caption="A red dot", name="dot.png")
bot.send_document(update.account_id, csv_bytes, "report.csv", caption="This month")
```

| | |
| --- | --- |
| Largest file | **8 MB.** Much smaller than a person's own attachment: a bot sends to many people at once and nobody is watching it pick a file. The library refuses a bigger one with `attachment_too_large` before uploading, because the server's body limit closes the connection and an author would otherwise see a bare transport error |
| Quota | Counted against the **bot's own account**, like anybody else's upload. `media_quota_exceeded` when it is full; older files free space as they expire |
| Retention | The ordinary media window (`MEDIA_TTL_DAYS`). After that the blob is swept and the message stays in the conversation as a message whose file is gone |
| `kind` | `image` draws it in the chat, `file` draws a row with the name and size. A hint, not a promise — the app falls back to a file row when a declared image does not decode |
| `name` | What the person sees and saves it as. Anything that could be read as a path is **refused**, not cleaned up: a cleaned-up path is one somebody has to be sure got cleaned |

### Who can fetch it, and the part to be honest about

**The bytes are not encrypted.** Everything on the bot path is plaintext this
server can read, and a file is no different — sealing it to look like the rest
of Privio while the bot holds the key would be the dishonest option.

What is narrow is who may fetch it. **The id is not the capability**: a bot
attachment is downloadable by exactly one account more than the uploader — the
one a `bot_messages` row addressed it to. Tested: before a message points at it
nobody can fetch it; afterwards the recipient can; a stranger cannot; **the
bot's owner cannot**, because they are a person like any other here.

A bot naming an upload that is not its own is refused (`media_not_found`), which
is what stops an id from becoming a way to hand a stranger's file to a third
person.

## 5c. Polls

The part to know first: **a bot poll is not anonymous to the bot, and it is not
encrypted.** The question, the answers and each person's choice are plaintext
this server can read, and your bot is told who picked what — that is what a bot
asking a question is for. The app prints it on the card, under the answers, not
in a settings screen. A channel poll is the opposite on purpose: there the
question travels sealed and the server only knows the shape. Here there is
nobody to seal it for, because the bot that wrote the question holds it in the
clear anyway.

```python
sent = bot.send_poll(update.account_id, "Tea or coffee?", ["Tea", "Coffee", "Neither"])
# sent.message_id, sent.poll_id

bot.resend_poll(other_person_id, sent.poll_id)   # the same question, one more person
results = bot.poll_results(sent.poll_id)          # counts, voters, closed
final = bot.close_poll(sent.poll_id)              # no more answers, for good
```

| | |
| --- | --- |
| Answers | 2 to 10, no two the same, up to 100 characters each. The question up to 300 |
| `max_choices` | 1 is a single-choice poll. More lets a person pick up to that many; never more than it offers |
| `show_results` | Off by default. When on, a person sees the tally **once they have answered**, or once it has closed. Off, only the bot sees it, and the card says so |
| `closes_at` | Optional, in the future, with a timezone — the library refuses a naive `datetime` rather than guessing whether it meant UTC |
| With it | Nothing else to answer: a poll cannot carry buttons or an attachment (`poll_alone`). `text`, if given, is a line drawn above the question |

**One poll, many messages.** A poll is its own object so that you can put the
same question to everybody who has started your bot and read one tally back —
that is what makes it a poll rather than a row of buttons. Each send is still a
message to one person, so a bot still cannot open a conversation with a poll
(`not_contacted`), and the person it was addressed to is the only one who may
answer it — in a group too, because a bot's reply is only ever shown to its
addressee, and an answer from somebody who could not see the question would be
a number in your tally that nobody can account for. Answers are per person and
per poll: somebody you sent it to twice has one answer, shown under both.
Another bot's poll id is answered as if it did not exist.

An answer arrives as an ordinary update with `vote` set and `text` empty:

```python
if update.vote:
    if update.vote.retracted:                  # they took their answer back
        ...
    else:
        update.vote.options                    # e.g. (1,) — indices, in order
        update.vote.poll_id
```

`options` is the person's **whole** answer as it now stands, not the change from
the last one, so a bot that keeps the latest per person is right even if it
missed an update. The server settles the rest before your code sees it:

* **In range.** An index the poll does not offer, two picks in a single-choice
  poll, or the same index twice are refused at the person's end and never reach
  you.
* **Once per change.** Answering the same thing again changes nothing and
  delivers nothing, so a double tap is not two votes. Changing the answer is a
  new update; an empty answer takes it back and is one too.
* **In order.** An answer travels through the same `bot_messages` row and the
  same take-once delivery as a typed message and a button press.
* **Not after a stop, not after it closed.** Somebody who stopped the bot cannot
  answer (`not_contacted`); a closed poll is refused (`poll_closed`) and is not
  sent to anybody else either.

`closed_at` is set only when the bot closes the poll. One that ran out at
`closes_at` stays recorded as having run out, so the record says which of the
two happened.

## 6. Idempotency, rate limits, and keeping the token out of things

**Idempotency.** `POST /v1/bots/:id/messages` — the route the *app* uses to
write to a bot — takes an optional `clientId` (8–128 characters) and ignores a
repeat of one it has already seen. That is what makes the app's retry after a
dropped connection safe. `POST /v1/bot/send` has no equivalent: a bot that sends
the same text twice sends it twice. Track your own state if that matters.

**Rate limits.** 30 messages a minute per bot, across every conversation,
answered as `429 rate_limited`. Polls are gated separately, per bot, per server
process. Neither is negotiable per bot, and neither is raised by asking.

**Pagination.** Only `limit` on updates, capped at 100. There is no list of
conversations, no list of group members, and no way to enumerate who has written
to the bot: a bot sees what is sent to it and nothing else. That is a design
decision, not a missing endpoint.

**The token.**

* Send it in the `Authorization` header. There is no `?token=` query parameter
  and there will not be one: URLs end up in access logs, proxy logs, browser
  history and `Referer` headers.
* The server never logs it. Error bodies never contain it.
* `webhook_receiver.py` suppresses the default access log for the same reason —
  for many people the path of a webhook URL is the secret part.
* If it leaks: `DELETE /v1/bots/:id/token`, then issue a new one. Revocation is
  immediate, because `botForToken` filters on `revoked_at IS NULL` in the query
  rather than checking afterwards where somebody could forget it.

---

## 7. A complete bot

`bot-sdk/examples/greeter.py` — runnable, not a sketch:

```bash
export PRIVIO_BOT_TOKEN=…
export PRIVIO_BASE_URL=https://your-server.example
python3 bot-sdk/examples/greeter.py
```

It answers `/start` and `/help` in a private chat, introduces itself in a group
and says plainly what it does and does not receive there, publishes its command
menu on start-up, and nudges anything else towards `/help`.

What it deliberately does **not** do is pretend to moderate. The moderation
rights exist and are enforced, but the routes a bot would call to use them are
not written yet (§9). A button that did nothing would be worse than no button.

---

## 8. What was actually tested

Run: `npm --workspace server test`.

`server/test/bot_webhooks.test.ts`, 18 tests against a real Postgres:

* every refused URL shape in §5, through the route, checked one at a time;
* that the refusal does not disclose what a private name resolved to;
* a session cannot register a webhook and a bot token cannot reach the owner's
  routes;
* the secret is returned once and never readable afterwards;
* re-registering replaces the row rather than adding a second one;
* the signature matches for the right inputs and fails for a wrong secret, a
  changed body and a changed timestamp;
* the address is re-checked **at delivery time**, and a delivery to an address
  that has turned private is not made — with the update still waiting
  afterwards, because nothing was taken;
* an update that went out over the webhook is not then handed to a poller;
* a 500 is counted with its status, and a success clears the count;
* the back-off actually thins out: under ten attempts in a thousand ticks at
  eight failures.

Confirmed load-bearing rather than decorative, by breaking three rules one at a
time and watching the right tests go red: signing the body without the timestamp
(2 red), dropping the delivery-time address check (3 red), and accepting any URL
at registration (2 red). Each was reverted immediately.

`server/test/bot_buttons.test.ts`, 18 tests: opening a bot by exact username
only (a prefix is a 404, and so is a person's name), the profile needing a
session, a bot that cannot write before it is started, **Start** delivering
`/start`, **Stop** taking the licence away *and* leaving what was already queued
undelivered, writing again counting as a restart, a button read back from the
message with what this person already pressed, a press reaching the bot naming
the button and its message, a press not appearing as a line in the conversation,
three taps producing one action, a button id that the message does not carry, a
press by somebody else, a press on another bot's message, a press after a stop,
two buttons with the same id, and nine buttons.

Each of the four rules that carry weight was broken once and the right test went
red: accepting any button id (1 red), delivering a press that was already
recorded (1), letting anybody press a direct message's button (1), and dropping
the stop filter from delivery (1).

On the app's side, `app/test/bot_chat_test.dart` (10 tests) and
`app/test/bot_chat_screen_test.dart` (4 widget tests): no text field before the
bot is started, the not-end-to-end-encrypted warning before the first send, a
pressed button drawn as pressed and disabled, the command menu offering what the
bot published, one bot's messages never appearing under another, and a late
answer for a previous account dropped rather than drawn. Falsified the same way:
drawing the composer before the start (2 red), offering a pressed button again
(1), skipping the disclosure (1).

`server/test/bot_moderation.test.ts`, 15 tests: a bot without the right can
neither remove anybody nor *read the member list*, nor renew the link; with
*Restrict members* it reads the members and is told which are removable, removes
an ordinary member, has their stale key request cleared, is refused on an admin,
on itself and on a non-member, cannot reach into a group it is not in, and loses
the ability the moment the right is withdrawn; with *Manage invites* it renews
the link, the old code stops opening the group, nobody already in it is affected,
and the human route behind it is admin-only. `may_moderate` is refused as a
right, and withdrawing it still works.

Falsified by breaking three guards one at a time: letting a bot remove an admin,
dropping the per-call right check, and storing `may_moderate` instead of
refusing it.

`server/test/bot_attachments.test.ts`, 14 tests: an upload answering with an id
and **no** download token, an empty body refused, three path-like names refused,
a session unable to upload and a bot token unable to use the human media route,
then the download rule from every side — nobody before a message points at the
object, the recipient afterwards, not a stranger, not the bot's owner, not
without signing in. Plus: an id that is not this bot's upload refused, an id
that does not exist refused, the conversation carrying kind, name and size, a
message without a file answering with nulls rather than absent keys, a kind
with no object not stored, and a swept blob leaving the message in place.

Falsified by breaking the two guards: letting anybody with the id fetch a bot
attachment (2 red), and letting a bot send somebody else's upload (5 red).

One design flaw was caught by a test rather than by a reviewer: the first
version of migration 040 required `media_id` and `media_kind` to be null or set
together, which made `ON DELETE SET NULL` violate the constraint — the retention
sweeper could never have deleted a bot attachment, and the bytes would have
stayed forever. The constraint now keeps only the half that survives expiry, and
the leftover kind is what tells the app to say the file is gone.

On the app's side, three widget tests in `app/test/bot_chat_screen_test.dart`: a
file row with its name and size, a swept file saying so with the message still
there, and bytes that are not an image falling back to a file row.

`server/test/bot_polls.test.ts`, 22 tests against a real Postgres: a poll
carried by a message with no copy of the question in its text; five malformed
polls refused (one answer, duplicate answers, more picks than answers, eleven
answers, a closing time in the past); no buttons beside a poll; no message with
neither text nor poll; no poll to somebody who never wrote; another bot unable
to reuse or read a poll. Answering: one update per change with the whole answer,
the same answer twice delivering nothing, a change delivering the new whole
answer, an empty answer taking it back, an out-of-range index, two picks on a
single-choice poll and a duplicate index refused, several picks taken and stored
in order, only the addressee able to answer, no answer on a message without a
poll or on the person's own line, none after a stop. One poll sent to two people
with one tally; the same poll sent twice to one person showing one answer under
both. No tally for the person unless the bot asked for one; with it, the tally
after answering and not before. Closing: answers refused afterwards, closing
again harmless, a closed poll not sent on; a poll past its time refused and not
stamped as closed by the bot. Deleting: an account's answers, bot conversation
and bot licence going with it, the bot's poll staying without them; a deleted
bot taking its polls and every answer along.

Falsified by breaking four rules one at a time, each turning exactly its own
test red: letting anybody answer a poll (1 red), delivering an unchanged answer
again (1), drawing the tally for the person regardless of `showResults` (1), and
leaving the votes behind on account deletion (1).

On the app's side, eight widget tests in `app/test/bot_chat_screen_test.dart`:
the card saying the bot sees who answered what, and that only the bot sees the
results; a tap answering and a second tap taking it back, with no tally drawn —
not even zeros; the tally appearing after answering and not before when the bot
allows it; several answers gathered, a pick past the limit not taken, and sent
together; a closed poll offering nothing to tap; a poll closed in the meantime
saying so; a refused answer of several not left drawn as given; and a screen
reader hearing each answer as a button and being able to choose it. Falsified
the same way: dropping the tap from the semantics (1 red), drawing bars without
a tally (2), dropping the sentence about the bot (1), and keeping a refused
draft — which no test caught until the last test was written for it.

`examples/greeter.py` was run against a live server on a scratch database and
driven the way a person would: `/poll` drew *Tea or coffee?* with three answers,
answering *Coffee* got "Noted: Coffee", answering it again got no second reply,
changing to *Tea* got "Noted: Tea", taking it back got the matching sentence,
and another person answering on that message was refused (403). The library was
then driven directly: `send_poll` with two picks and a closing time,
`resend_poll` to a second person, both answers arriving as updates with the
right indices, `poll_results` reading `(1, 0, 2)` from two voters, `close_poll`,
a closed poll refused on resend, and a naive `datetime`, a single answer and a
duplicate answer each refused with a sentence.

The Python side was run, not just written:

* `examples/webhook_receiver.py` was started for real and sent five deliveries —
  a genuine one (200, update handled and printed), a tampered body, a replayed
  ten-minute-old timestamp, a wrong secret and a missing signature (401, all
  four).
* The client was driven against a live server on a scratch database through the
  whole path: register, create a bot, issue a token, `me()`, a refused send
  before contact (`not_contacted`), a person writing, a poll returning the
  update with its parsed command, a reply, an empty second poll, and a
  deduplicated retry.
* `send_photo` and `send_document` were driven against a live server with a
  real PNG built in the probe and a text file: refused before the bot was
  started (`not_contacted`), then sent, listed in the conversation with the
  right kind, name and size, and fetched back **byte-identical** by the
  recipient — while a stranger and the bot's own owner both got a 404. A
  nine-megabyte upload was refused.
* `examples/greeter.py` itself was run against a live server, not simulated: it
  published its command menu on start-up, answered `/start`, offered two buttons
  on `/menu`, received the press and answered it, answered a second press with
  nothing (the server returned `already: true`), and refused an invented button
  id with `no_such_button`.

**Not tested here, and it should not be read as working:** an end-to-end
delivery from this server to a real public HTTPS receiver. The guard refuses
every address a test in this container could listen on — correctly — so the two
halves are tested separately: the guard through the route and through
`deliverOnce`, and the POST itself through `postDelivery` against a receiver the
test runs. What remains unproven by a test is the combination on a real public
URL with a real certificate, which needs a deployed server and a host outside
it.

---

## 9. What is not built yet

Stated here rather than discovered:

* **Message types.** Text, buttons, pictures, files and polls. Not the other
  direction: a *person* cannot send a bot a picture or a file — only text, a
  button press or a poll answer. Quiz polls (one answer marked correct) and
  anonymous polls are not offered: a poll the bot is told about cannot be
  anonymous to the bot, and a switch saying otherwise would be a false one.
* **Channels.** A bot cannot post to a channel yet.
* **Deleting other people's messages.** Not possible, and `may_moderate` is now
  refused as a right rather than stored and left inert. A deletion is an
  encrypted protocol message to every member's devices and only the author may
  send it — see [bots.md](bots.md#why-a-bot-cannot-delete-other-peoples-messages).
  *Restrict members* and *Manage invites* are wired end to end (§3a).
* **Membership events.** A bot is not told when it is added to or removed from a
  group; it finds out by receiving, or not receiving, messages.
* **End-to-end encrypted bots.** A bot as its own cryptographic endpoint, with
  local key management, is designed but not implemented — see
  [bots.md](bots.md#what-it-would-take-to-do-better). Until then the warning at
  the top of this file stands: a bot chat is not end-to-end encrypted, and no
  wording here should be read as softening that.
