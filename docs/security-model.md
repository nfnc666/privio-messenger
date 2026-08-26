# Privio Security Model

This document says plainly what Privio protects, what it does not, and where the
current implementation is not yet where it needs to be. A privacy product that
overstates itself is worse than one that says nothing.

## The rule that governs every decision

**No custom cryptography.** Privio composes audited implementations and writes
none of its own primitives. Where this document names an algorithm, it names a
library that implements it.

| Purpose | Choice | Where |
| --- | --- | --- |
| Message encryption | Signal Protocol (X3DH + Double Ratchet) | `libsignal_protocol_dart` on the client — see gap 1 |
| Password hashing | Argon2id, 64 MiB, t=3, p=1 | `@node-rs/argon2` (RustCrypto) |
| Session tokens | 256-bit random, stored as SHA-256 | `node:crypto` |
| Transport | TLS 1.3 | Platform TLS |
| Local database | SQLCipher (AES-256) | Client, V1 milestone |
| Attachments | AES-256-GCM with a per-file random key | Client |
| Backups | AES-256-GCM under a key from a recovery phrase | Client |
| Two-factor | TOTP, RFC 6238 | `otplib` |

## Threat model

### Defended against

**A compromised or hostile server.** The server holds ciphertext and public
keys. An attacker with full database access reads no messages. This is the
central claim and everything else is subordinate to it.

**A network attacker.** TLS 1.3 in transit, and the message layer is encrypted
independently of it — breaking TLS yields ciphertext.

**A stolen, locked phone.** The local database is encrypted at rest and the app
is locked by PIN or biometrics. Keys live in the Keychain or Android Keystore,
hardware-backed where the device offers it.

**Coerced unlock.** The wipe code destroys devices, sessions, queued messages,
contacts, group membership and backups, and returns the same error a mistyped
password returns. Someone watching cannot tell the wipe happened.

**Account takeover by password alone.** Optional TOTP. Changing the password
revokes every other session.

**Enumeration of the user base.** Lookup is by exact username only. There is no
prefix search, no directory, and no address-book upload.

**Learning that you blocked someone.** A blocked sender's messages return an
ordinary success and are dropped.

### Not defended against

**A compromised endpoint.** Malware with your unlocked device reads your
messages. No messenger solves this.

**Traffic analysis.** The server sees who exchanges envelopes and when. Sealed
sender narrows this; a global passive adversary correlating timing is out of
scope.

**A malicious recipient.** Anyone you message can screenshot, copy or forward
it. "Restrict content saving" raises the effort; it is not a security control
and is not presented as one.

**A lost recovery key.** Backups cannot be recovered without it. This is the
cost of the server not holding a key, and it is the right trade.

**Targeted platform compromise.** A zero-day in iOS or Android, or a malicious
OS update, defeats any app on it.

## Authentication

Registration takes a username and a password — no phone number, no email, so
there is no identifier to correlate against other services and nothing to leak
in a breach.

- Passwords: minimum 10 characters, hashed with Argon2id server-side.
- Login failures answer identically for a wrong password and an unknown user,
  and an unknown user still pays an Argon2 verification so the timing matches.
- Sessions are opaque 256-bit tokens; the database stores only SHA-256. A
  database leak yields no usable session.
- Rate limits: 10 attempts per 5 minutes per address on the auth endpoints, 300
  per minute per device elsewhere.

The PIN is a **local** lock on an already-encrypted database, not the account
password. It never leaves the device.

## Key management

Each device has a stable per-account index, a long-term identity key, a
rotating signed prekey, and a pool of one-time prekeys. The index is what the
protocol addresses a session by; it is never reused, even after a device is
revoked, so an old session can never be pointed at a new device. The server stores public halves only and hands out one
bundle per device on request, deleting the one-time prekey atomically so it is
never reused. An exhausted pool still yields a usable bundle from the signed
prekey — weaker forward secrecy for those sessions until the client tops up,
which clients do well before the pool empties.

Peer identity keys are trusted on first use and pinned thereafter. A key that
changes afterwards is **refused on send** — a server that swaps in its own key
cannot silently read the conversation, because the user has to accept the new
safety number first. Incoming messages from a changed key are still accepted, so
a peer who reinstalled can reach you, and the change is surfaced rather than
hidden. This is tested: see `a swapped identity key is refused on send` in
`app/test/crypto_test.dart`.

## Data retention

| Data | Retention |
| --- | --- |
| Delivered envelopes | Deleted the moment the device acknowledges |
| Undelivered envelopes | 30 days, then purged |
| Attachments | 30 days from upload, unconditionally |
| Backups | One per account, replaced on each upload |
| Sessions | 365 days, or until revoked |
| Deleted accounts | Tombstoned; all content deleted immediately |

## Known gaps in the current implementation

These are real and tracked. Nothing here is hand-waved as "future work" without
naming what is missing today.

1. **The protocol implementation is a port, not the audited original.**
   Messages *are* end-to-end encrypted: `app/lib/crypto/` performs X3DH and the
   Double Ratchet, and the round trip is covered by tests that assert a third
   party holding the ciphertext cannot open it. But it runs on
   `libsignal_protocol_dart`, a pure-Dart port of libsignal rather than the
   official audited Rust build. A port can diverge from the original in ways
   that matter, and this one has not been audited.

   The pre-launch target is the official `libsignal` behind FFI. Every call site
   goes through `PrivioCrypto`, so that swap is contained to one file — but
   until it happens, this is the single largest caveat on Privio's central
   claim, and it should be stated to users rather than glossed.
2. **Decrypted messages are held in memory only.** There is no local database
   yet, so history does not survive a restart — and when one lands it must be
   encrypted (SQLCipher) from the first commit, because that store holds the
   only readable copy of a conversation. The keystore already protects the
   session token and all key material.
3. **The PIN is compared, not stretched.** It is stored in the platform
   keystore, which is the security boundary; V2 moves it into the native crypto
   layer where it derives a key-encryption key with Argon2id.
4. **No sealed sender.** Envelopes carry a sender account id, which the server
   uses for blocking and rate limiting. Removing it needs delivery tokens.
5. **TOTP secrets are stored in plaintext in the database.** They should be
   encrypted with a server-held key so a database leak alone does not defeat the
   second factor.
6. **Attachment ids are the download capability.** Any authenticated user who
   learns an id can fetch the (encrypted) bytes. Ids are unguessable and objects
   expire, but per-recipient authorisation would be stronger.
7. **No independent audit.** Before any public release, the crypto integration
   needs review by someone who was not involved in writing it.

## Reporting a vulnerability

Set up `security@privio.app` with a published PGP key before launch, commit to a
response window, and say so in the app's About screen. A privacy product without
a disclosure channel is not credible.
