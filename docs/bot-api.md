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
| `POST /v1/bot/send` | `{to, text, groupId?, buttons?}` → `{messageId}` |
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

* **Message types.** Text and buttons. No images, files or polls over the bot
  API yet; those message types exist in Privio but the bot routes do not carry
  them.
* **Channels.** A bot cannot post to a channel yet.
* **Moderation.** `may_moderate`, `may_restrict_members` and `may_manage_invites`
  are stored per group and enforced, but no route uses them, so a bot holding
  them still cannot act. They refuse rather than pretending.
* **Membership events.** A bot is not told when it is added to or removed from a
  group; it finds out by receiving, or not receiving, messages.
* **End-to-end encrypted bots.** A bot as its own cryptographic endpoint, with
  local key management, is designed but not implemented — see
  [bots.md](bots.md#what-it-would-take-to-do-better). Until then the warning at
  the top of this file stands: a bot chat is not end-to-end encrypted, and no
  wording here should be read as softening that.
