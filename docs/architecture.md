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
conversation, in a local database encrypted at rest, unlocked by the PIN or
biometrics.

Layers, outermost first:

| Layer | Location | Responsibility |
| --- | --- | --- |
| Screens | `lib/screens/` | One file per mockup screen |
| Messaging | `lib/services/` | The only place plaintext meets the transport |
| Conversations | `lib/core/conversation_controller.dart` | Drives the screens; polls the queue every 3s |
| Crypto | `lib/crypto/` | X3DH, the Double Ratchet, and the key store |
| Archive | `lib/data/` | The decrypted history, sealed at rest with AES-256-GCM |
| Widgets | `lib/widgets/` | Shared components: rows, bubbles, avatars, the mark |
| Theme | `lib/theme/` | The design tokens from `docs/design-system.md` |
| State | `lib/core/app_state.dart` | Session and lock stage, via `ChangeNotifier` |
| Transport | `lib/core/api_client.dart` | HTTP to the API; sealed bytes only |
| Storage | `lib/core/secure_store.dart` | Keychain / Keystore |
| Biometrics | `lib/core/biometric_gate.dart` | Face ID / Touch ID, behind an interface |

There is no state-management package: `InheritedNotifier` covers what the app
needs, and every dependency in a security product is a dependency to audit.

### Server (`server/`)

Fastify on Node.js 22. Stateless — everything durable is in PostgreSQL or the
blob store, so instances scale horizontally behind a load balancer.

| Module | Responsibility |
| --- | --- |
| `routes/accounts.ts` | Registration, login, 2FA, wipe code, recovery blob |
| `routes/devices.ts` | Connected devices, remote logout, prekey distribution |
| `routes/contacts.ts` | Username lookup, contacts, blocking, invites |
| `routes/messages.ts` | Per-device envelope send, fetch and acknowledge |
| `routes/groups.ts` | Membership, roles, fan-out device lists |
| `routes/media.ts` | Encrypted attachment upload and download |
| `routes/backup.ts` | Encrypted backup upload and restore |
| `routes/ws.ts` | Realtime delivery socket |
| `services/delivery.ts` | Queueing, fan-out, push wake-ups |
| `services/bus.ts` | In-process or Redis pub/sub between instances |

### Data

**PostgreSQL** holds accounts, devices, public key material, contacts, group
membership, the envelope queue, and pointers to blobs. Read `migrations/001_init.sql`
top to bottom: every column that could carry content is a `bytea` the server
cannot interpret.

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
2. **Sender** runs X3DH per device, then seals the message once *per device*
   with the Double Ratchet. Five devices means five ciphertexts.
3. **Sender** posts all copies in one request (`POST /v1/messages`). If the
   device list has changed since the bundles were fetched, the server rejects
   the whole send with `device_mismatch` and names the missing devices — better
   a retry than a phone that silently never receives the message.
4. **Server** writes one envelope row per recipient device, publishes a wake-up
   on the bus, and sends a contentless push to devices without a live socket.
5. **Recipient** drains its queue with `GET /v1/messages` (the client polls
   every three seconds today; the WebSocket the server already serves replaces
   that poll next).
   Each envelope names the sender's device index, which is what identifies the
   session to decrypt with. The recipient decrypts locally, writes to its local database, and only then acknowledges
   with `DELETE /v1/messages?upTo=`. Delivery is at-least-once until that ack,
   so a crash mid-decrypt costs a duplicate, never a lost message.

Groups work the same way, with the fan-out list coming from
`GET /v1/groups/:id/devices`.

## Notifications

Push payloads are empty. They say "something arrived", nothing else — not the
sender, not a preview, not a count. The device wakes, connects, and decrypts
locally. APNs and FCM therefore see traffic, not content or social graph.
`PushSender` is the interface; `LoggingPushSender` is the development default.

## Calls (V2)

WebRTC peer-to-peer with DTLS-SRTP, keyed through the same Signal sessions that
protect messages. The server relays signalling as `call_signal` envelopes and
provides a TURN relay for networks that cannot connect directly — TURN sees
encrypted media only. Call history stays on the device.

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
