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
The recipient adopts it, both sides compute an `expiresAt` from their own clock,
and `MessageStore.pruneExpired` removes what has run out — on a five-second
sweep, after every drain, and on restore. The server is not told and is not
trusted with it.

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

**The state machine is ours; the media is not.** `CallService` decides what a
signal means — whose call it belongs to, whether the line is busy, what a
goodbye for a call that already ended does — and drives `CallPeer`, an
interface. `WebRtcCallPeer` is the one implementation that touches hardware;
the tests use a fake and drive both ends over real Signal sessions.

**Signals leave in order.** They are sealed to a ratchet, which is stateful, so
`CallService` serialises its sends rather than starting a second seal before
the first has finished.

**Not yet:** no STUN or TURN server runs, so the two devices try only the
addresses they can see for themselves — same network and simple NATs work,
strict ones do not. `--dart-define=PRIVIO_ICE_SERVERS=...` points a build at
one. No TURN also means no fallback relay; when one exists it will see
encrypted media only. And a call reaches a closed app only once the client
registers for push.

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

Sealed sender, which removes the sender identifier from the routing metadata, is
tracked in `docs/security-model.md` under known limitations.

## Running it

See `README.md` for setup. The short version:

```bash
cd server && npm install && npm run migrate && npm run dev
cd app && flutter pub get && flutter run
```
