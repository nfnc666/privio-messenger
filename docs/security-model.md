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
| Message encryption | Signal Protocol (X3DH + Double Ratchet) | `libsignal` on the client |
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

Each device has a long-term identity key, a rotating signed prekey, and a pool
of one-time prekeys. The server stores public halves only and hands out one
bundle per device on request, deleting the one-time prekey atomically so it is
never reused. An exhausted pool still yields a usable bundle from the signed
prekey — weaker forward secrecy for those sessions until the client tops up,
which clients do well before the pool empties.

Adding a device produces a `key_change` envelope so peers can surface a safety
number change rather than silently trusting a new key.

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

1. **The Signal Protocol layer is not yet wired in.** The server's contract —
   prekey bundles, per-device envelopes, opaque ciphertext — is complete and
   tested, and the client's transport speaks it. What is not yet in the client
   is `libsignal` performing X3DH and the Double Ratchet, so V1 messaging is not
   end-to-end encrypted *until that lands*. It is the next milestone and no
   build should be shipped to users before it.
2. **The local database is not yet encrypted.** SQLCipher integration is a V1
   milestone. The Keychain already protects the session token.
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
