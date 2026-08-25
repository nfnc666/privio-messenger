# Privio

A privacy-first secure messenger for iOS and Android.

Privio is built around one rule: **the server never holds a key that can open a
message.** It routes sealed envelopes and stores ciphertext. Everything else —
the design, the API, the database schema — follows from that.

No phone number. No email. No address-book upload. You are a username.

## Repository layout

| Path | What it is |
| --- | --- |
| `app/` | The Flutter client for iOS and Android |
| `server/` | The Node.js + TypeScript API |
| `design/` | Brand assets and the source mockups |
| `docs/` | Architecture, security model, design system |

Read these in order: [`docs/architecture.md`](docs/architecture.md) for how the
pieces fit, [`docs/security-model.md`](docs/security-model.md) for what is
protected and what is **not yet** protected, and
[`docs/design-system.md`](docs/design-system.md) for the visual rules.

## Status

The server implements the V1 API and is covered by 33 tests against a real
PostgreSQL database. The client implements the V1 screens against the design
system, verified with `flutter analyze`, widget tests, and rendered screenshots
compared to the mockups.

**Not yet done, and it matters:** the Signal Protocol layer is not wired into the
client, so messages are not end-to-end encrypted today. The server contract for
it — prekey bundles, per-device envelopes, opaque ciphertext — is complete and
tested, and the client transport already speaks it. Until `libsignal` lands in
the client, no build should go to users. See the known-gaps list in
[`docs/security-model.md`](docs/security-model.md#known-gaps-in-the-current-implementation);
it is deliberately blunt.

## Running the server

Requirements: Node.js 22+, PostgreSQL 14+. Redis is optional and only needed
once a second API instance exists.

```bash
cd server
cp .env.example .env          # then edit DATABASE_URL
npm install
npm run migrate               # migrations also run automatically on boot
npm run dev                   # http://localhost:8080
```

Check it is up:

```bash
curl http://localhost:8080/health
```

### Tests

The suite runs against a real PostgreSQL database — no mocks, because the parts
worth testing are the queries.

```bash
createdb privio_test
cd server
TEST_DATABASE_URL=postgres://you@localhost:5432/privio_test npm test
```

## Running the app

Requirements: Flutter 3.22+.

```bash
cd app
flutter pub get
flutter run                   # or: flutter analyze && flutter test
```

The client points at `http://localhost:8080` by default; pass a different API
base URL when constructing `PrivioApiClient`.

## API at a glance

| Endpoint | Purpose |
| --- | --- |
| `POST /v1/accounts` | Register a username and its first device |
| `POST /v1/sessions` | Log in, registering the calling device |
| `GET /v1/keys/:username` | One prekey bundle per device of that user |
| `POST /v1/messages` | Send one sealed copy per recipient device |
| `GET /v1/messages` | Drain this device's queue |
| `DELETE /v1/messages?upTo=` | Acknowledge, which deletes server-side |
| `GET /v1/ws` | Realtime delivery socket |
| `POST /v1/media` | Upload an already-encrypted attachment |
| `PUT /v1/backup` | Upload an already-encrypted backup |

Full route list in [`docs/architecture.md`](docs/architecture.md).

## Roadmap

**V1** — Authentication · Accounts · Contacts · E2EE 1:1 messaging · Groups ·
Media · Notifications · Backup

**V2** — Channels · Voice and video calls · Multi-device · Advanced privacy ·
Disguise mode · Wipe code

## Contributing rules that are not negotiable

1. **No custom cryptography.** Use audited implementations of established
   protocols. If you find yourself writing a cipher, stop.
2. **No plaintext to the server.** If a new field could carry user content, it
   is a `bytea` the server cannot interpret.
3. **Say what is not done.** An overstated privacy claim is worse than a missing
   feature.
