<div align="center">

<img src="design/logo/privio-logo-wordmark.png" alt="Privio" width="180">

### Encrypted. Private. Yours.

A privacy-first secure messenger for iOS and Android.

<img src="https://img.shields.io/badge/client-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
<img src="https://img.shields.io/badge/server-Node.js%2022-339933?style=flat-square&logo=nodedotjs&logoColor=white" alt="Node.js">
<img src="https://img.shields.io/badge/database-PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
<img src="https://img.shields.io/badge/crypto-Signal%20Protocol-22C55E?style=flat-square" alt="Signal Protocol">
<img src="https://img.shields.io/badge/tests-256%20passing-22C55E?style=flat-square" alt="Tests">

</div>

---

## The one rule

**The server never holds a key that can open a message.**

It routes sealed envelopes and stores ciphertext. Everything else — the design,
the API, the database schema — follows from that. Where a decision traded
convenience for keeping the server ignorant, that was deliberate.

No phone number. No email. No address-book upload. You are a username.

---

## The app

<table>
<tr>
<td align="center" width="25%"><img src="docs/screenshots/01-welcome.png" width="200"><br><sub><b>Welcome</b><br>What Privio promises, before anything is asked of you</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/02-chats.png" width="200"><br><sub><b>Chats</b><br>Search and filters run on-device</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/03-chat.png" width="200"><br><sub><b>Chat</b><br>Sealed before it leaves the phone</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/05-contacts.png" width="200"><br><sub><b>Contacts</b><br>Usernames, not phone numbers</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/07-account.png" width="200"><br><sub><b>Account</b><br>Your identity, your storage, your keys</sub></td>
<td align="center"><img src="docs/screenshots/09-invite-qr.png" width="200"><br><sub><b>Invite</b><br>QR generated on-device</sub></td>
<td align="center"><img src="docs/screenshots/10-settings.png" width="200"><br><sub><b>Settings</b><br>Everything in one place</sub></td>
<td align="center"><img src="docs/screenshots/11-privacy.png" width="200"><br><sub><b>Privacy &amp; Security</b><br>Every switch is enforced somewhere real</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/13-devices.png" width="200"><br><sub><b>Devices</b><br>See what is logged in, log it out</sub></td>
<td align="center"><img src="docs/screenshots/backup-01-empty.png" width="200"><br><sub><b>Backup</b><br>Sealed with a key only you hold — and honest when there is none</sub></td>
<td align="center"><img src="docs/screenshots/12-notifications.png" width="200"><br><sub><b>Notifications</b><br>Push carries no content at all</sub></td>
<td align="center"><img src="docs/screenshots/group-03-member.png" width="200"><br><sub><b>Groups</b><br>The name is decrypted by members, never by the server</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/channel-06-list.png" width="200"><br><sub><b>Channels</b><br>What you follow, and what there is to find</sub></td>
<td align="center"><img src="docs/screenshots/channel-02-feed.png" width="200"><br><sub><b>Channel feed</b><br>Posts sealed once, under a key the server never sees</sub></td>
<td align="center"><img src="docs/screenshots/channel-10-discover.png" width="200"><br><sub><b>Discover</b><br>Public channels only — private ones are never listed</sub></td>
<td align="center"><img src="docs/screenshots/channel-09-permissions.png" width="200"><br><sub><b>Permissions</b><br>Greyed out is what you do not hold yourself</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/voice-01-recording.png" width="200"><br><sub><b>Recording</b><br>Hold the mic, slide left to cancel, pause any time</sub></td>
<td align="center"><img src="docs/screenshots/voice-02-preview.png" width="200"><br><sub><b>Preview</b><br>Listen back, or delete it — nothing is sent unheard</sub></td>
<td align="center"><img src="docs/screenshots/voice-03-received.png" width="200"><br><sub><b>Voice message</b><br>Waveform and length come from the sealed payload</sub></td>
<td align="center"><img src="docs/screenshots/voice-04-playing.png" width="200"><br><sub><b>Playing</b><br>Decrypted in memory, 1x · 1.5x · 2x</sub></td>
</tr>
</table>

<details>
<summary><b>More screens</b> — add contact, invite link, new channel, members, appearance, about</summary>
<br>
<table>
<tr>
<td align="center" width="25%"><img src="docs/screenshots/06-add-contact.png" width="200"><br><sub><b>Add contact</b></sub></td>
<td align="center" width="25%"><img src="docs/screenshots/08-invite-link.png" width="200"><br><sub><b>Invite link</b></sub></td>
<td align="center" width="25%"><img src="docs/screenshots/channel-01-new.png" width="200"><br><sub><b>New channel</b></sub></td>
<td align="center" width="25%"><img src="docs/screenshots/channel-08-members.png" width="200"><br><sub><b>Channel members</b></sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/channel-11-promoted.png" width="200"><br><sub><b>After a promotion</b></sub></td>
<td align="center"><img src="docs/screenshots/14-appearance.png" width="200"><br><sub><b>Appearance</b></sub></td>
<td align="center"><img src="docs/screenshots/16-about.png" width="200"><br><sub><b>About</b></sub></td>
<td align="center"></td>
</tr>
</table>
</details>

> These are real screenshots of the running app, captured at 390×844, not mockups.

### It actually works

Two accounts, two devices, one real server. Clara adds Finn by username, sends a
message, Finn's client decrypts it, replies, and Clara's client decrypts the
reply — the Double Ratchet running in both directions.

<table>
<tr>
<td align="center" width="25%"><img src="docs/screenshots/e2e-01-sent.png" width="220"><br><sub><b>1.</b> Clara sends. The server takes bytes it cannot read.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/e2e-02-arrived.png" width="220"><br><sub><b>2.</b> It arrives at Finn, who had never heard of Clara.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/e2e-03-conversation.png" width="220"><br><sub><b>3.</b> His reply comes back decrypted.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/e2e-04-after-restart.png" width="220"><br><sub><b>4.</b> After a relaunch it is still there — read back from the encrypted archive, not re-fetched.</sub></td>
</tr>
</table>

That run found a real bug: the client was declaring a JSON content type on
requests with no body, which a strict server rejects — so the receive loop had
been failing silently every three seconds. It is fixed and covered by a test.

### Ticks that mean what they say

The tick marks used to claim every message had been read — the model's default
said so, and nothing ever measured it. Now a message is sent, then delivered
when the other device has actually decrypted it, then read when the chat is
actually opened. Receipts are sealed envelopes like any other; the server sees
that something was sent and nothing else.

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/receipts-01-delivered.png" width="220"><br><sub><b>1.</b> Delivered: their device decrypted it. Two grey ticks.</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/receipts-02-read.png" width="220"><br><sub><b>2.</b> Read: they opened the chat. Two green ticks.</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/receipts-03-typing.png" width="220"><br><sub><b>3.</b> Typing, which expires on its own — nothing arrives to say "stopped".</sub></td>
</tr>
</table>

The switches are reciprocal: turning read receipts off stops this device sending
them **and** showing other people's. A setting that took without giving would be
a different feature wearing this one's name.

### A backup only you can open

A history sealed on the device, a key that exists nowhere else, and a new
device that gets the conversations back by typing it in. The server holds 451
bytes it cannot read.

<table>
<tr>
<td align="center" width="25%"><img src="docs/screenshots/backup-02-key.png" width="200"><br><sub><b>1.</b> The recovery key, as text and as a QR for the next device.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/backup-03-new-device.png" width="200"><br><sub><b>2.</b> A fresh device: never backed up here, but there is one on the server.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/backup-04-restore.png" width="200"><br><sub><b>3.</b> The key goes in. It never went anywhere near Privio.</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/backup-05-history.png" width="200"><br><sub><b>4.</b> The conversation is back.</sub></td>
</tr>
</table>

That work also removed two invented numbers from the account screen — a storage
figure and a "Security Level: High" — that nothing had measured. A screen about
trust is the last place for decoration.

### A join link, and a key that follows it

The same discipline applied to channels. A reader opens a plain link, joins, and
sees padlocks — because the link carries no key. The key arrives afterwards,
sealed to their device by someone who already holds it, and the feed unlocks
without anyone doing anything further.

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/channel-03-link.png" width="220"><br><sub><b>1.</b> The link is safe to post anywhere: no key in it.</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/channel-05-waiting.png" width="220"><br><sub><b>2.</b> The reader is in, and can read nothing yet.</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/channel-07-unlocked.png" width="220"><br><sub><b>3.</b> The key arrives from a member's device; the posts open.</sub></td>
</tr>
</table>

That run found three more: the channel listing returned a role but no
permissions, so reopening a channel silently stripped its owner's rights; a
group you joined by a link never appeared in the chat list until somebody spoke
in it; and the permission sheet's **Save** button sat below the fold on a
390×844 screen. All three are fixed.

---

## What works today

| Area | Status | Detail |
| --- | :---: | --- |
| **Registration & login** | ✅ | Username + password. No phone number, no email |
| **End-to-end encryption** | ✅ | X3DH + Double Ratchet, one sealed copy per device |
| **Two-factor auth** | ✅ | TOTP (RFC 6238), enforced at login |
| **Wipe code** | ✅ | Duress code that destroys everything and looks like a typo |
| **Contacts & blocking** | ✅ | Exact-username lookup, invisible blocking |
| **Groups** | ✅ | Create, name (encrypted), send and receive — in the app |
| **Media** | ✅ | Client-encrypted attachments with enforced expiry |
| **Backup** | ✅ | Manual and automatic, sealed under a recovery key the server never sees; restore on a new device by key or QR |
| **At-least-once delivery** | ✅ | Envelopes are acknowledged only after they decrypt |
| **Push notifications** | ✅ | Contentless wake-ups; APNs/FCM see no metadata |
| **Device management** | ✅ | List, remote logout, per-device sessions |
| **App lock** | ✅ | PIN and biometrics, re-locks on backgrounding |
| **Chat UI wired to crypto** | ✅ | Real accounts, real sends, real decryption |
| **Encrypted local history** | ✅ | AES-256-GCM under a key in the platform keystore |
| **Metadata stripped from files** | ✅ | GPS, camera, serial numbers, timestamps — automatically, no setting |
| **Attachments in the chat** | 🔧 | 1:1 and groups; send, receive and display work; the OS file dialog is untested (see below) |
| **Profile pictures** | 🔧 | Encrypted end to end; same untested file dialog |
| **Message length hidden** | ✅ | Padded into buckets, so size says nothing |
| **Realtime delivery** | ✅ | WebSocket push — measured at 722 ms end to end, not 3 s |
| **Voice messages** | ✅ | Hold to record, slide to cancel, pause, preview, 1x/1.5x/2x; sealed before upload |
| **Read receipts & typing** | ✅ | Sealed like any message, reciprocal switches, 1:1 |
| **Disappearing messages** | ✅ | Per chat, agreed end to end; the server is never asked |
| **Offline queue** | ✅ | A recording made with no signal waits as ciphertext and goes when there is |
| **Voice & video calls** | 📋 | V2 — WebRTC over the existing Signal sessions |
| **Channels** | ✅ | Public and private, both encrypted; discovery, feed, per-admin permissions, join links |
| **Join links** | ✅ | Shareable links for channels and groups; the key follows device to device, never through the server |
| **Disguise mode** | 📋 | V2 — the calculator skin |

✅ done and tested · 🔧 in progress · 📋 planned

---

## How a message travels

```mermaid
sequenceDiagram
    participant A as Alice's phone
    participant S as Privio server
    participant B as Bob's phones

    A->>S: GET /v1/keys/bob
    S-->>A: one prekey bundle per device<br/>(consumes a one-time prekey)
    Note over A: X3DH per device, then seal<br/>with the Double Ratchet.<br/>2 devices = 2 ciphertexts.
    A->>S: POST /v1/messages (all copies at once)
    Note over S: Stores bytes it has no key for.<br/>Rejects the send if the device<br/>list went stale.
    S->>B: wake-up (WebSocket, or contentless push)
    B->>S: GET /v1/messages
    S-->>B: sealed envelopes
    Note over B: Decrypts locally, writes to<br/>the local database.
    B->>S: DELETE /v1/messages?upTo=…
    Note over S: Only now is it deleted.<br/>A crash costs a duplicate,<br/>never a lost message.
```

---

## Architecture

```
 iOS / Android (Flutter)                     Server (Node.js + TypeScript)
 ┌──────────────────────────┐                ┌──────────────────────────────┐
 │ Screens · dark, minimal  │                │ Fastify HTTP + WebSocket     │
 │ Local encrypted database │                │                              │
 │ Signal Protocol session  │  sealed bytes  │ accounts · devices · keys    │
 │  · X3DH key agreement    │ ─────────────► │ envelopes · groups           │
 │  · Double Ratchet        │ ◄───────────── │ media · backups              │
 │ Keystore / Keychain      │   TLS 1.3      │                              │
 └──────────────────────────┘                └───────────┬──────────────────┘
                                                         │
                                         ┌───────────────┼───────────────┐
                                    PostgreSQL       Redis (opt.)   Blob storage
                                    routing +        fan-out across  ciphertext
                                    ciphertext       API instances   only
```

| Layer | Location | Responsibility |
| --- | --- | --- |
| Screens | `app/lib/screens/` | One file per screen in the design |
| Widgets | `app/lib/widgets/` | Rows, bubbles, avatars, the brand mark |
| Theme | `app/lib/theme/` | The measured design tokens |
| Messaging | `app/lib/services/` | The only place plaintext meets the transport |
| **Archive** | `app/lib/data/` | The decrypted history, sealed at rest |
| **Media** | `app/lib/media/` | Metadata scrubbing, per-file encryption, padding |
| **Crypto** | `app/lib/crypto/` | X3DH, the Double Ratchet, the key store |
| Transport | `app/lib/core/` | HTTP client, keystore, app state |
| API routes | `server/src/routes/` | Accounts, devices, contacts, messages, groups, media, backup |
| Delivery | `server/src/services/` | Queueing, fan-out, push wake-ups |
| Schema | `server/migrations/` | Every content column is a `bytea` the server cannot read |

There is no state-management package in the client. `InheritedNotifier` covers
what the app needs, and every dependency in a security product is a dependency
someone has to audit.

---

## What the server can and cannot see

| It can see | It cannot see |
| --- | --- |
| Usernames and account creation time | Message text, voice notes, media, files |
| Which accounts exchange envelopes, and when | Group names and avatars |
| Device counts, and a padded size bucket | How long a message actually is |
| Group membership | Contact names and aliases you set locally |
| That a file was uploaded, and roughly how big | File names, types, or anything inside them |
| Attachment lifetimes | Search queries — search never leaves the device |

**Push notifications carry nothing.** They say "something arrived" and no more —
not the sender, not a preview, not a count. The device wakes, connects and
decrypts locally, so Apple and Google see traffic, never content.

---

## Metadata

Encryption protects what you write. It does nothing about everything *around*
what you write — and that is often the part that identifies you.

**Files are stripped before they are sent.** A photo out of a phone carries GPS
coordinates, the camera make and model, a serial number and the second it was
taken. Encrypting it delivers all of that intact to the recipient. Privio removes
it on the way out, every time, with no setting to forget:

| Format | Removed |
| --- | --- |
| JPEG | EXIF and XMP (GPS, camera, serial number, timestamps), IPTC, ICC profile, comments |
| PNG | Text and comment chunks, embedded EXIF, modification time, ICC profile |
| MP4 / MOV | User-data boxes (GPS, device make and model), metadata tags, recording timestamps |

Only container structure is touched — the pixels and the audio are passed through
byte for byte, so nothing is re-encoded and nothing degrades. A format Privio
cannot clean is still sent, encrypted, but the app says so rather than letting
you assume otherwise.

**Message length is padded away.** Ciphertext length tracks plaintext length, and
the server sees every ciphertext. Unpadded, "yes" is distinguishable from a
paragraph. Every payload is padded into a doubling bucket before it is sealed, so
the server observes a handful of sizes instead of a continuum — and a text
message is indistinguishable from a photo being sent.

Attachments are padded the same way. Be precise about what that buys: for short
messages it is near-total, since everything under 256 bytes looks identical. For
a large file it means an observer learns the size only to within a factor of two,
which is a real improvement over the exact byte count but is not invisibility.

**Profile pictures are encrypted too.** A messenger that promises the server
cannot read anything, and then stores everyone's face in the clear, has not kept
the promise. An avatar is sealed with a long-lived *profile key* that reaches
contacts inside end-to-end encrypted messages and never reaches the server — so
the server holds a picture it cannot open, and only people you have actually
written to can see it. It is also re-encoded to 512×512 on the way out, which
strips metadata a second time and stops a full-resolution photo of your
surroundings from becoming your avatar.

**Channels are encrypted, public ones included — with a caveat worth stating.**
A post is sealed once under a channel key, so the server stores something it
cannot read, search or hand over. What that does *not* do is keep a public
channel secret from its own audience: if anyone may join, anyone may hold the
key. What matters is that the key never passes through the server. A join link
(`https://privio.channel/c/<code>`, or `https://privio.group/g/<code>` for a
group) is meant to be shared — posted on a website, sent through another
messenger — so it carries no key at all, only the code that names the channel. The key follows
separately: the joining device records a request, and a member who already holds
the key seals it to that device over the Signal session between the two
accounts. The server routes both halves and can read neither, which is what
stops it from simply subscribing to everything. A public channel's handle, title
and description are plaintext, because search cannot run over ciphertext; its
posts are not. Groups have the same kind of link, and their sealed name travels
the same way.

**A voice message is an attachment, and gets the same pipeline.** It is sealed
on the device under its own random key, padded, and uploaded as ciphertext; the
server stores audio it cannot play. The duration and the waveform ride *inside*
the sealed payload, not beside the upload, so the bubble is complete before
anything is downloaded and the server never learns how long anyone spoke. The
encoder's working file is overwritten and deleted the moment its bytes have been
read, and playback runs from memory — a decrypted recording is never written to
disk.

**Disappearing messages are an agreement, not a request to the server.** The
timer travels inside each sealed payload; both devices adopt it and delete on
their own clocks. Asking a server to forget something is trusting it to.

**File names never leave the encrypted envelope.** `passport_scan.pdf` travels
inside the sealed message next to the key, never beside the upload.

---

## Cryptography

Privio writes **no cryptographic primitives of its own.** It composes audited
implementations of established protocols.

| Purpose | Choice |
| --- | --- |
| Message encryption | Signal Protocol — X3DH + Double Ratchet |
| Password hashing | Argon2id, 64 MiB, t=3, p=1 |
| Session tokens | 256-bit random, stored only as SHA-256 |
| Transport | TLS 1.3 |
| Attachments | AES-256-GCM, random key per file |
| Backups | AES-256-GCM under a key derived (HKDF-SHA256) from your recovery key |
| Local history | AES-256-GCM under a key in the platform keystore |
| Profile pictures | AES-256-GCM under a profile key, shared only with contacts |
| Attachments | AES-256-GCM, a fresh random key per file, size padded |
| Two-factor | TOTP, RFC 6238 |

### The caveats, stated plainly

A privacy product that overstates itself is worse than one that says nothing.

1. **The protocol implementation is a port, not the audited original.** Messages
   are genuinely end-to-end encrypted, and the tests prove a third party holding
   the ciphertext cannot open it. But it runs on `libsignal_protocol_dart`, a
   pure-Dart port rather than the official audited Rust `libsignal`. Moving to
   the official library behind FFI is a **pre-launch requirement**.
2. **The local history is one sealed blob, not a database.** It is encrypted
   correctly, but rewritten whole on every change, so it will not scale to a
   long history. Moving it to SQLCipher is planned; the storage port exists so
   that swap touches one file.
3. **No sealed sender.** Envelopes name the sender, which the server uses for
   blocking and rate limiting.
4. **The link domains are not registered.** Links are generated against
   `privio.channel` and `privio.group`, neither of which this project owns, so
   nothing on the open internet answers them. It costs nothing in security —
   the app reads the invite code out of the link's *path* and never fetches the
   URL, so a link works between Privio users either way, and the parser accepts
   a link that has been shortened or re-hosted for the same reason. But a link
   a recipient cannot click is a worse link. Registering the domains (and
   confirming both TLDs are actually available) and shipping a `privio://` deep
   link beside them is a launch task; each host is one constant,
   `ChannelService.channelLinkHost` and `groupLinkHost`.
5. **No independent audit.** Before any public release the crypto integration
   needs review by someone who did not write it.

The full list, with the reasoning, is in
[`docs/security-model.md`](docs/security-model.md#known-gaps-in-the-current-implementation).

---

## Quick start

### Server

Requirements: Node.js 22+, PostgreSQL 14+. Redis is optional — it is only needed
once a second API instance exists.

```bash
cd server
cp .env.example .env          # then edit DATABASE_URL
npm install
npm run migrate               # migrations also run automatically on boot
npm run dev                   # http://localhost:8080
```

```bash
curl http://localhost:8080/health
# {"status":"ok","version":"0.1.0"}
```

### App

Requirements: Flutter 3.22+.

```bash
cd app
flutter pub get
flutter run
```

### Tests

The server suite runs against a **real PostgreSQL database** — no mocks, because
the parts worth testing are the queries.

```bash
createdb privio_test
cd server && TEST_DATABASE_URL=postgres://you@localhost:5432/privio_test npm test
#  73 passing

cd app && flutter analyze && flutter test
#  183 passing
```

Among the things those tests assert:

- a third party holding the exact bytes the server stores **cannot** open them
- changing **one byte** of a message makes it undecryptable rather than wrong
- the same plaintext **never** produces the same ciphertext twice
- a used one-time prekey is **deleted**, so forward secrecy holds
- a **swapped identity key is refused on send** — the attack this all exists to stop
- the history at rest is **ciphertext** — not the messages, not even the contact names
- a different key **cannot** read that archive, and a tampered one is discarded
- a photo's **GPS, camera model and serial number** are gone from what the recipient receives
- an avatar on the server is **not a picture** — a stranger's key opens nothing
- a group's **name is ciphertext** to the server; only members with the key read it
- a **private channel** answers a stranger exactly as it answers about one that does not exist
- a deleted post's ciphertext is **overwritten**, not left waiting for a key
- an admin **cannot grant a permission they lack**, so delegation is not takeover
- a **join link carries no key** — not in the path, not in a fragment, nowhere
- a device that joins with only a link reads **padlocks**, until a member sends the key
- a key request from someone who has **left** is deleted rather than answered
- a second group message **reuses the session** instead of draining prekeys
- "yes" and a full paragraph produce **exactly the same ciphertext length**
- a 40-byte, a 100-byte and a 200-byte file all **upload at the same size**
- a photo sent through the real send path arrives **stripped**, and the server's copy gives nothing away
- a photo sent to a **group** is uploaded **once**, not once per member, and scrubbed just the same
- a voice message's bytes on the server are **not the recording** — and a tampered one refuses to play
- a **retry** after a lost connection delivers the recording **once**, not twice
- a recording queued with no network sits at rest as **ciphertext**, and goes out when the network returns
- a chat's disappearing timer is **never sent to the server** and is applied by both sides
- a backup on the server is **ciphertext** — no names, no messages, no attachment keys
- the **wrong recovery key** opens nothing, and a failed restore leaves the device's history alone
- a recovery key survives being **written down and typed back in**, including O for 0
- a receipt is **never** filed as a message, and carries no readable word on the wire
- delivery state **never walks backwards**, however receipts are ordered
- a receipt names **specific messages**, not "everything up to now"
- a session token in a socket URL is **redacted** before it reaches the logs
- a duress wipe is **indistinguishable** from a mistyped password
- blocking is **invisible** to the blocked sender

---

## API at a glance

| Endpoint | Purpose |
| --- | --- |
| `POST /v1/accounts` | Register a username and its first device |
| `POST /v1/sessions` | Log in, registering the calling device |
| `GET /v1/keys/:username` | One prekey bundle per device of that user |
| `POST /v1/keys/one-time` | Top up the published prekey pool |
| `POST /v1/messages` | Send one sealed copy per recipient device |
| `GET /v1/messages` | Drain this device's queue |
| `DELETE /v1/messages?upTo=` | Acknowledge, which deletes server-side |
| `GET /v1/ws` | Realtime delivery socket |
| `POST /v1/groups` | Create a group with encrypted metadata |
| `POST /v1/media` | Upload an already-encrypted attachment |
| `PUT /v1/backup` | Upload an already-encrypted backup |
| `POST /v1/licenses/redeem` | Bind a license key to this account |

Full route list in [`docs/architecture.md`](docs/architecture.md).

---

## Project layout

```
privio-messenger/
├── app/                    Flutter client (iOS + Android)
│   ├── lib/crypto/           X3DH, Double Ratchet, key store, padding
│   ├── lib/media/            Metadata scrubbing and attachment encryption
│   ├── lib/services/         Messaging: the plaintext boundary
│   ├── lib/screens/          One file per screen
│   ├── lib/widgets/          Shared components
│   ├── lib/theme/            Design tokens
│   └── test/                 22 tests, incl. the crypto round trip
├── server/                 Node.js + TypeScript API
│   ├── src/routes/           HTTP endpoints
│   ├── src/services/         Delivery, storage, sessions
│   ├── migrations/           SQL schema
│   └── test/                 35 tests against real PostgreSQL
├── design/                 Brand assets and the source mockups
└── docs/                   Architecture, security model, design system
```

---

## Design

Dark-first, because it is the brand and because true black costs nothing on the
OLED panels most phones ship with.

| Token | Value | Use |
| --- | --- | --- |
| `accent` | `#22C55E` | Primary actions, active tab, read ticks, online dots |
| `background` | `#000000` | App background |
| `surface` | `#0B0B0B` | Cards and list rows |
| `bubbleOutgoing` | `#0B3B21` | Your messages |
| `danger` | `#EF4444` | Wipe code, missed calls, destructive actions |

The full system — typography, spacing, every screen and component — is in
[`docs/design-system.md`](docs/design-system.md), measured from the mockups in
`design/mockups/`.

---

## Roadmap

**V1** — Authentication · Accounts · Contacts · E2EE 1:1 messaging · Groups ·
Media · Notifications · Backup

**V2** — Channels · Voice and video calls · Multi-device · Advanced privacy ·
Disguise mode · Wipe code

---

## Contributing rules that are not negotiable

1. **No custom cryptography.** Use audited implementations of established
   protocols. If you find yourself writing a cipher, stop.
2. **No plaintext to the server.** If a new field could carry user content, it
   is a `bytea` the server cannot interpret.
3. **Say what is not done.** An overstated privacy claim is worse than a missing
   feature.

---

## Documentation

| Document | What it covers |
| --- | --- |
| [Architecture](docs/architecture.md) | How the pieces fit, and how a message travels |
| [Security model](docs/security-model.md) | What is protected, what is not, and what is still missing |
| [Design system](docs/design-system.md) | Colours, typography, every screen and component |
| [Licensing](docs/licensing.md) | How a license key is issued, redeemed and enforced |

<div align="center">
<br>
<sub>Built with privacy in mind. No tracking. No ads. Just you.</sub>
</div>
