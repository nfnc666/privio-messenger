# Privio Architecture

## The one rule

The server is a router for sealed envelopes. It learns who is talking to whom
and when, because it has to deliver the bytes; it never learns *what* was said,
because it never holds a key that could open them.

Everything below follows from that. Where a design choice was made to keep the
server ignorant at the cost of some convenience, that is deliberate.

## Shape of the system

```
 iOS / Android (Flutter)                     Server (Node.js + TypeScript)
 ┌──────────────────────────┐                ┌──────────────────────────────┐
 │ UI (Material, dark)      │                │ Fastify HTTP + WebSocket     │
 │ Local encrypted DB       │                │                              │
 │ Signal Protocol session  │  sealed bytes  │ accounts · devices · keys    │
 │  · X3DH key agreement    │ ─────────────► │ envelopes · groups           │
 │  · Double Ratchet        │ ◄───────────── │ media · backups              │
 │ Keystore / Keychain      │   TLS 1.3      │                              │
 └──────────────────────────┘                └───────────┬──────────────────┘
                                                         │
                                         ┌───────────────┼───────────────┐
                                         │               │               │
                                    PostgreSQL       Redis (opt.)   Blob storage
                                    routing +        fan-out across  ciphertext
                                    ciphertext       API instances   only
```

## Components

### Client (`app/`)

Flutter, one codebase for iOS and Android. The client owns every key and does
every encryption and decryption. It holds the only readable copy of a
conversation, in a local database encrypted at rest, behind an app-lock passcode
— four digits, six digits or a passphrase, and deliberately never a fingerprint
or a face.

Layers, outermost first:

| Layer | Location | Responsibility |
| --- | --- | --- |
| Screens | `lib/screens/` | One file per mockup screen |
| Messaging | `lib/services/` | The only place plaintext meets the transport |
| Conversations | `lib/core/conversation_controller.dart` | Drives the screens and files what arrives |
| Realtime | `lib/services/realtime_connection.dart` | The delivery socket, with reconnect and backoff |
| Crypto | `lib/crypto/` | X3DH, the Double Ratchet, and the key store |
| Archive | `lib/data/` | The decrypted history, sealed at rest with AES-256-GCM |
| Media | `lib/media/` | Metadata scrubbing, per-file encryption, size padding |
| Widgets | `lib/widgets/` | Shared components: rows, bubbles, avatars, the mark |
| Theme | `lib/theme/` | The design tokens from `docs/design-system.md` |
| State | `lib/core/app_state.dart` | Session and lock stage, via `ChangeNotifier` |
| Transport | `lib/core/api_client.dart` | HTTP to the API; sealed bytes only |
| Storage | `lib/core/secure_store.dart` | Keychain / Keystore |

There is no state-management package: `InheritedNotifier` covers what the app
needs, and every dependency in a security product is a dependency to audit.

### Server (`server/`)

Fastify on Node.js 22. Stateless — everything durable is in PostgreSQL or the
blob store, so instances scale horizontally behind a load balancer.

| Module | Responsibility |
| --- | --- |
| `routes/accounts.ts` | Registration, login, 2FA, duress code, recovery blob |
| `routes/devices.ts` | Connected devices, remote logout, prekey distribution |
| `routes/contacts.ts` | Username lookup, contacts, blocking, invites |
| `routes/messages.ts` | Per-device envelope send, fetch and acknowledge |
| `routes/groups.ts` | Membership, roles, fan-out device lists |
| `routes/channels.ts` | Channels, discovery, posts, roles |
| `routes/media.ts` | Encrypted attachment upload and download |
| `routes/backup.ts` | Encrypted backup upload and restore |
| `routes/licenses.ts` | License redemption, status and issuing (see [licensing](licensing.md)) |
| `routes/ws.ts` | Realtime delivery socket |
| `services/delivery.ts` | Queueing, fan-out, push wake-ups |
| `services/bus.ts` | In-process or Redis pub/sub between instances |

### Data

**PostgreSQL** holds accounts, devices, public key material, contacts, group
membership, the envelope queue, and pointers to blobs. Read `migrations/001_init.sql`
top to bottom: every column that could carry content is a `bytea` the server
cannot interpret.

The socket authenticates with the session token in the query string, because a
browser cannot set a header on a WebSocket handshake. The server redacts that
parameter from its request logs, so a token cannot outlive its request by being
written down.

**Redis** is optional. Without it the delivery bus runs in-process, which is
correct for a single instance. Add it when the second instance goes up.

**Blob storage** keeps encrypted attachments and backups. `LocalFileStorage`
writes to disk; the `BlobStorage` interface is what an S3-compatible adapter
implements.

## How a message travels

1. **Sender** looks up the recipient's devices and fetches a prekey bundle for
   each (`GET /v1/keys/:username`). A one-time prekey is consumed per fetch.
   Each bundle carries the device's stable per-account index, which is how a
   Signal session is addressed — the UUID is only for routing.
2. **Sender** pads the payload to a size bucket, then runs X3DH per device and
   seals it once *per device* with the Double Ratchet. Five devices means five
   ciphertexts, all the same length whatever was written.
3. **Sender** posts all copies in one request (`POST /v1/messages`). If the
   device list has changed since the bundles were fetched, the server rejects
   the whole send with `device_mismatch` and names the missing devices — better
   a retry than a phone that silently never receives the message.
4. **Server** writes one envelope row per recipient device, publishes a wake-up
   on the bus, and sends a contentless push to devices without a live socket.
5. **Recipient** receives the envelopes pushed down its WebSocket, and
   acknowledges on that same socket once they are decrypted and filed. A slow
   poll (every two minutes) stays as a safety net for a socket that is connected
   but not delivering, and to cover the gap before the handshake completes.
   Each envelope names the sender's device index, which is what identifies the
   session to decrypt with. The recipient decrypts locally, writes to its local database, and only then acknowledges
   with `DELETE /v1/messages?upTo=`. Delivery is at-least-once until that ack,
   so a crash mid-decrypt costs a duplicate, never a lost message.

Because delivery is at-least-once and there are two channels, the same envelope
does arrive twice in normal operation: the socket pushes it while the fallback
poll is fetching everything not yet acknowledged. The ratchet refuses the second
copy — it cannot tell a redelivery from a replay, and refusing is the right
answer — so `MessagingService` drops it first: every batch queues behind the one
currently in the ratchet, and an envelope whose id has already been opened is
counted as handled without being decrypted again. Without that, a message the
user could plainly read was reported as one that would not decrypt. Both halves
are covered by tests in `app/test/messaging_service_test.dart`.

**When an envelope genuinely will not open.** Retrying cannot help — the same
bytes fail the same way — so it is acknowledged rather than left to block the
queue, and two things follow. The conversation gets a
`MessageKind.undelivered` line saying a message could not be read: the sender's
screen says delivered, and a silent gap in a transcript reads as an answer
nobody gave. Then `_repairSession` deletes the session with that device and
sends `MessagePayload.sessionReset()`. The reset carries nothing; sending it
*is* the repair. With no session left it goes out as a prekey message from a
fresh bundle, and `SessionBuilder` archives the old state on the other side the
moment it arrives — so one payload puts both directions back on a working
ratchet. Rate-limited to one per device per hour, because a reset consumes one
of the other side's one-time prekeys and a batch of twenty failed envelopes must
not become twenty handshakes.

Note what this is *not* for: the Double Ratchet already tolerates reordering,
skipped messages and a rolled-back store — a device restored from an older copy
of its own storage goes on decrypting. What it cannot survive is key material
that is gone: a peer whose identity was replaced behind the same device row.
That case is staged and repaired in `app/test/session_repair_test.dart` against
the real library.

Groups work the same way, with the fan-out list coming from
`GET /v1/groups/:id/devices`.

A **channel** post takes a different route, because a channel is one author and
many readers: it is sealed once under a channel key and stored once, rather than
sealed per recipient device. Readers pull the feed. The server never holds the
channel key, so it stores posts it cannot read. What it does hold in the clear,
for a public channel only, is the handle, title, description and category,
because discovery cannot search ciphertext.

**Join links and how the key follows.** A link
(`https://privio.channel/c/<code>` for a channel,
`https://privio.group/g/<code>` for a group) is meant to be shared publicly, so
it carries no key. Each host lives in one place —
`ChannelService.channelLinkHost` and `groupLinkHost` — because it appears in the
links it generates, in a dialog and in the tests. The parser keys off the `/c/`
or `/g/` path segment rather than the host, so a shortened or re-hosted link
still resolves to the same thing.
Joining writes a row to `key_requests` for the joining device; any member who
holds the key answers with an ordinary sealed message carrying it, then clears
the row. Client side that is `ChannelService.deliverPendingKeys` on one end and
a `MessagePayload.key` intercepted in `ConversationController` on the other,
which stores the key and shows nothing in the chat.

## Two-factor secrets

`services/totp.ts` seals TOTP secrets with AES-256-GCM under `TOTP_SECRET_KEY`,
stored as `v1.<nonce>.<ciphertext+tag>`. The marker is what tells a sealed
value from one written before sealing existed, which is returned as-is so
already-enrolled accounts keep working.

Setup refuses with 503 when no key is configured — a secret written unsealed
never expires, so it would be a permanent hole nobody was told about. The error
the user sees points them at the operator; the log names the variable.

## More than one device

An account may have several devices, and a message is sealed once per device.
Incoming fan-out is the server's: `/v1/messages` addresses every active device
of the recipient, and the group route addresses every member device except the
one that sent.

Outgoing needed a copy. `MessagePayload.sync` wraps what was sent together with
the conversation it went to, addressed to the sender's *own* username; both
`GET /v1/keys/:username` and `POST /v1/messages` exclude the calling device
when the target account is its own, so "send to myself" means "my other
devices" and a device never opens a session with itself. The receiving device
files the inner payload as outgoing in the named conversation, deduplicated on
the client id so a device that sent it does not file it twice.

Control payloads are not copied — a receipt or typing notice filed on another
device would become a message nobody wrote — and the copy is not retried, so a
device offline for one send has a gap only a backup fills.

## Attachments

The client picks a random key, scrubs the file's metadata, pads it into a size
bucket, seals it, and uploads ciphertext. The key goes inside the E2EE message.

`MetadataScrubber` handles JPEG, PNG, WebP, GIF and MP4/MOV, identifying the
format by magic bytes rather than by the name, which is attacker-controlled.
Container formats are rebuilt rather than patched: WebP's chunk table is walked
and EXIF/XMP/ICCP dropped with their VP8X flags, GIF's block chain is walked and
comments, plain-text and non-loop application extensions dropped. A file whose
structure cannot be walked to the end is returned untouched and reported as
*not* cleaned — a partial walk leaves metadata in the part never read, and a
clean report over that is worse than no scrubber at all.

Downloading is a **capability**. The upload mints an unguessable token, returns
it once, and stores only its SHA-256 — `GET /v1/media/:id` needs the token in
`x-privio-media-token` and compares in constant time. The token travels in the
sealed payload beside the media key, so the server authorises the bytes without
being told who may have them. The id alone used to be the capability, which
meant a read of `media_objects` was a set of capabilities for every blob in it.

The token is issued once, so every place that remembers a blob has to remember
it too: `Attachment` on the stored message, `PendingSend` in the outbox, and
the archive's serialisation of both. A retry that kept the id and dropped the
token would send a message pointing at bytes nobody could fetch — and a copy
that dropped it on the receiving side left the bubble on a spinner, which is
how it was found.

Avatars are marked `kind = 'avatar'` and carry no token: their id is published
to contacts, so a token would be published with it. They are authorised by the
contact list instead.

## Voice messages

A voice message is an attachment with two extra fields, not a second transport.
`VoiceRecording` (bytes, duration, waveform, media type) goes into
`AttachmentCipher.seal` exactly as a photo does — scrubbed, padded, sealed under
a fresh random key — and the pointer plus that key travel inside the same
`MessagePayload.media` the rest of the app already sends. The duration and the
waveform are payload fields, so the bubble can render before anything is
fetched, and the server sees a padded blob with no idea how long it is.

Recording and playback sit behind `VoiceRecorder` and `VoicePlayer`, ports in
the same style as `CryptoStorage` and `SecureStore`. `PluginVoiceRecorder`
picks Opus where the platform supports it and AAC otherwise, polls the level
meter for the waveform, and on a phone overwrites and deletes the encoder's
working file the moment its bytes have been read; in a browser there is no file
at all. `JustAudioVoicePlayer` serves decrypted bytes from memory through a
`StreamAudioSource`, because every other way in takes a path or a URL — and a
decrypted recording in a cache directory would undo the encryption.

**The outbox.** `PendingSend` holds what has not gone out: the *sealed* bytes,
their key, the duration and the waveform. Sealing happens before queueing, so a
recording waiting for a network is ciphertext even in the archive, which is
itself sealed. Each entry carries a client id that is also the send's
idempotency key, and remembers its `mediaId` once uploaded — so a retry after a
failed send does not upload the same recording twice, and the server answers a
repeated key rather than queueing a second copy (`sent_message_keys`, migration
007).

**Disappearing messages.** The timer is a number inside the sealed payload.
The recipient adopts it, both sides compute an `expiresAt` from their own clock
— the sender's from the moment the server takes the message (`_markSent`, and
`_attachDelivered` for anything that went through the outbox), never from the
moment it was written, so a queued or failed message has no expiry at all —
and `MessageStore.pruneExpired` removes what has run out — on a five-second
sweep, after every drain, and on restore. It returns the messages it removed
rather than a count, so the controller can drop their decrypted attachments from
the session cache along with them. The server is not told and is not trusted
with it.

Adopting a timer, or setting one, appends a `MessageKind.notice` to the
conversation — a line the app writes itself, rendered centred rather than as a
bubble, never sent, never unread, never searched, and with no expiry of its own.
`DisappearingTimerSheet` is the one chooser, used by both the 1:1 chat's menu
and the group info screen, so the wording that tells a user what this actually
promises exists once.

**The KDF cost is turned down in tests.** Argon2id is expensive on purpose, and
the suite touches it hundreds of times — every lock set, every unlock, every
wrong code a calculator disguise is fed. At production cost the disguise tests
alone took over ten minutes. `test/flutter_test_config.dart` lowers it for the
whole suite; `passcode_vault_test.dart` puts the real parameters back for
itself, because there the cost is the subject. Blobs carry their own parameters,
so one sealed cheaply still opens.

## Receipts and typing

Both are ordinary sealed envelopes whose payload says what they are —
`MessagePayload.receipt` and `MessagePayload.typing` — and which
`ConversationController` intercepts before anything reaches a conversation.
There is no separate transport: the server relays them exactly as it relays a
sentence, and can read neither.

A receipt names messages by the **sender's** client ids, so it says "these
ones" rather than "everything up to now" — the second is a claim a device
cannot honestly make about messages it has not seen. Delivery state only ever
moves forward, because receipts from a second device can arrive out of order.

In a group the receipt still goes to the author alone, and carries
`receiptGroupId` so the receiving side knows which conversation the ids belong
to — the envelope says only who sent it. Each member's answer is kept
separately in `Message.receipts`, and `Message.state` moves only once all of
them have got that far (`InMemoryMessageStore._groupState`), with the count
drawn on the bubble until then. The member count comes from
`GroupInfo.memberCount`, carried from the group listing; zero means "not known
yet" and holds the ticks where they are rather than reading as "everyone".

A typing notice carries the moment it was sent rather than a duration. One that
was queued while a phone was off says nothing about now, so it is dropped; a
live one is believed for six seconds and re-sent at most every three while
someone writes. Nothing ever arrives to say "stopped", so a timer in the
controller fades the indicator instead.

The server has an `EPHEMERAL` set that would drop `typing` envelopes rather than
queue them. It is unused: the delivery bus publishes only a nudge, and the
client then fetches over HTTP — so an envelope that was never stored could not
be fetched, and a typing notice would simply never arrive. Typing is delivered
durably and expires on the client instead.

Both are 1:1 only. A group receipt needs per-member tracking, and a group typing
notice that says "someone" is worse than none.

## Backup

A backup is the local history, sealed on the device and uploaded as bytes the
server cannot read. `PUT /v1/backup` takes it, `GET /v1/backup` reports size and
version, `GET /v1/backup/content` hands the same ciphertext back.

The key is a **recovery key**: 32 random bytes, generated on the device, shown
in Crockford-style base32 without I, L, O or U so it can be copied onto paper
without ambiguity — and parsed back forgivingly, since someone who writes O for
0 has not made a mistake worth punishing. `BackupCodec` runs it through
HKDF-SHA256 for domain separation and seals with AES-256-GCM.

What a backup holds is conversations, through the same `ArchiveCodec` the local
archive uses — one serialisation, so the two cannot drift. What it deliberately
does **not** hold is key material: no identity key, no ratchet state. Restoring
gives a new device the history; that device then registers an identity of its
own. Copying ratchet state to a second device would break both, and quietly.

Automatic backup runs from `AppState.lock()` — the app going away is when a
backup is both cheap and most likely to matter — and honours an Off/Daily/Weekly
setting kept beside the key in the keystore.

## Notifications

Push payloads are empty. They say "something arrived", nothing else — not the
sender, not a preview, not a count. The device wakes, connects, and decrypts
locally. APNs and FCM therefore see traffic, not content or social graph.
`PushSender` is the interface; `LoggingPushSender` is the development default.

## Disguise mode

The lock screen is replaced by a calculator (`lib/disguise/`, `lib/screens/
calculator_screen.dart`) and the launcher entry by a second one.

`Calculator` is a plain object: keys in, display out, no widgets. The unlock
check compares its *answer* to the passcode, so any sum reaching the code opens
the app and the code itself need not be typed.

`LauncherDisguise` is the port for the home-screen half, over a
`app.privio/launcher` method channel. Android enables one `activity-alias` and
disables the other, then reads the result back. The port reports what the
platform can change — Android icon and name, web neither — and the settings
screen is worded from that answer. The capability is read after start-up rather
than during it: a start-up that awaits a platform channel hangs wherever nothing
answers, which is every widget test and the web build.

The whole feature is withheld on iOS (`AppState.platformSupportsDisguise`),
which cannot rename an app: the setting is absent, the lock screen is the
ordinary one, and a stored disguise is cleared at start-up.

## Calls

WebRTC peer to peer, media encrypted with DTLS-SRTP by libwebrtc through
`flutter_webrtc`. Privio adds no cryptography of its own here.

**Signalling is a message.** The offer, the answer and every ICE candidate are
`MessagePayload.callSignal` payloads, sealed per device over the Signal session
the two already have and queued as ordinary envelopes. The server got no new
endpoint for calls: the envelope queue was already the right shape, and routing
a call therefore tells it exactly what routing a message tells it — that two
accounts exchanged something, and when. It never sees an SDP, which is a list
of the addresses each device can be reached on.

**Video.** `CallPeer` hands out two widgets rather than frames — rendering
video is the one part of a call the platform must do itself, a native texture
on the phones and a composited element on the web, and copying frames through
Dart would buy nothing. The renderers are built and disposed with the
connection: one outliving its stream is a black rectangle, one built per
rebuild leaks textures.

**The state machine is ours; the media is not.** `CallService` decides what a
signal means — whose call it belongs to, whether the line is busy, what a
goodbye for a call that already ended does — and drives `CallPeer`, an
interface. `WebRtcCallPeer` is the one implementation that touches hardware;
the tests use a fake and drive both ends over real Signal sessions.

**Signals leave in order.** They are sealed to a ratchet, which is stateful, so
`CallService` serialises its sends rather than starting a second seal before
the first has finished.

**Finding each other.** `ICE_SERVERS` on the server lists the STUN and TURN
addresses this deployment offers, and `GET /v1/calls/ice` hands them to
authenticated clients — configuration in one place rather than compiled into
every build. With `TURN_SECRET` set, the API mints coturn `use-auth-secret`
credentials: username is the expiry, password is its base64 HMAC-SHA1. No
account id goes in the username, so a relay operator cannot tie relayed calls to
accounts. The endpoint is authenticated because relay capacity published openly
is somebody else's bandwidth.

`IceServerCache` on the client fetches at sign-in and holds until the credential
is near expiry. Not per call: a request at dial time would tell the server that
a call is starting, which is the one thing the sealed signalling otherwise keeps
from it.

A TURN relay carries the media, which stays DTLS-SRTP between the two devices —
the relay holds no key. It does see both addresses and the volume. That is the
trade: a relay hides each party's address from the other and shows both to
whoever runs it.

**Not yet:** a call reaches a closed app only once the client registers for
push.

Call history stays on the device, in the encrypted key store, and is erasable
on its own.

## What the server can and cannot see

| Can see | Cannot see |
| --- | --- |
| Usernames and account creation time | Message text, voice notes, media, files |
| Which accounts exchange envelopes, and when | Group names and avatars |
| Envelope sizes and device counts | Contact names and aliases you set locally |
| Group membership | Anything inside a backup |
| Attachment sizes and lifetimes | Search queries — search is on-device |

That last row used to be true in the way an unimplemented thing is true: search
filtered the chat list and could not reach a message, so no query was sent
because no query existed. It reaches the whole decrypted history now
(`app/lib/core/message_search.dart`), still without a request. There is no
index — the loop walks what is in memory, which is what the archive holds
anyway, and an index would be a second copy of every conversation to keep
encrypted and in step.

### Group and channel keys reach a device that never joined

A group's name and a channel's posts are sealed with a key the server never
sees, so a device that has the membership and not the key can read neither.
Joining records a key request on the server, and any member that holds the key
answers it on its next drain — sealed to the asking account like any other
message.

Signing in on a *second* device joins nothing, so nothing recorded a request
for it. It asks for itself now: the same walk that answers other people's
requests also asks for the groups and channels this device is in without a key.

Recording a request wakes every device of every other member over the same bus
that carries envelope wake-ups. The payload is a device id and a reason —
`envelopes` or `key-request` — and nothing else: the server has never held a
key and does not learn one here. A device with a live socket receives
`{"type":"key-request"}` and runs its key housekeeping at once.

The poll is the fallback for a device that is not connected, not the mechanism.
Measured in the browser, a second device signing in has the group's name within
about three seconds; before the wake existed it waited for the answering
device's next poll, which is two minutes.

Sealed sender, which removes the sender identifier from the routing metadata, is
tracked in `docs/security-model.md` under known limitations.

## Running it

See `README.md` for setup. The short version:

```bash
cd server && npm install && npm run migrate && npm run dev
cd app && flutter pub get && flutter run
```
