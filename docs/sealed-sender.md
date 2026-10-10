# Sealed sender

**Status:** design accepted. Server side implemented (this change). Client side
not yet, see "Phases" below. Until the client ships, no message is sealed and
`docs/metadata-privacy-review.md` §6 stays true as written.

## The gap this closes

Today every envelope row carries `sender_account_id` and `sender_device_id`.
The server can read neither a message nor its attachment, but it knows **who
wrote to whom, and when**, for as long as the envelope waits. For a messenger
whose stated measure is maximum privacy (see `CLAUDE.md`) that is the largest
remaining leak, and it is the one sealed sender exists to close.

After this change, for a message sent sealed, the server learns:

| | Before | Sealed |
| --- | --- | --- |
| Recipient account and device | yes | yes. It has to deliver it |
| Sender account and device | **yes, stored** | **no**, neither stored nor sent |
| Content, attachment key | no | no |
| Size (padded), time | yes | yes |
| Sender IP address at send time | yes, logged with the request | seen on the connection, **not logged** for this route |

The sender's identity travels *inside* the encryption: the recipient's device
opens the outer layer and finds a certificate, signed by this server, naming
the sender, its device and its identity key. Only the recipient can read it.

## No custom cryptography

The construction is Signal's sealed sender, implemented by Signal's own
**libsignal** (Rust, AGPL-3.0, the library Signal ships), not re-implemented:

* **Server:** `@signalapp/libsignal-client`, Signal's official Node binding,
  published by Signal. It issues `ServerCertificate` and `SenderCertificate`.
* **App:** the `libsignal` Dart package, a flutter_rust_bridge binding over the
  same libsignal (pinned to tag `v0.103.1`). The app uses exactly two calls of
  it: `sealedSenderEncryptFromUsmc` to seal and `sealedSenderDecryptToUsmc` to
  open. The **inner** message stays what it is today: a Signal message from
  `libsignal_protocol_dart`, from the existing sessions. Nothing about the
  sessions, safety numbers or stored keys changes.

Proven before any of this was written, across all three implementations: the
Node binding issued a certificate, the Rust binding sealed a
`libsignal_protocol_dart` pre-key message around it, the recipient opened it,
validated the certificate and decrypted the inner message. A certificate from
another trust root was refused, one flipped byte refused everything, and
neither the sender's id nor its identity key appeared anywhere in the sealed
bytes.

### The supply-chain rule

The Dart package ships a build hook that, for Android and iOS, **downloads
pre-built binaries from its author's GitHub releases**, verified against a
checksum file from the same release. That verifies the download, not the
author. For a messenger that holds itself to this standard, a native library
compiled by one third party and trusted on their word is not acceptable.

So the rule for the client phase: **the native library is built from source by
Privio's own CI**, from a pinned commit with `cargo build --locked`, for every
target (Android arm64/armv7/x86_64, iOS device and simulator), and the hook is
made to use those builds and never download. A build that would download fails
instead. The package source is reviewed when it is vendored; it is small
(the Rust side is a thin binding) and AGPL, so vendoring is allowed.

## Keys

Three key pairs, all Curve25519 as libsignal uses them:

| Key | Where it lives | Used for |
| --- | --- | --- |
| **Trust root** | **Offline.** Generated once, kept off the server | Signs server certificates. The app pins its public half |
| **Server key** | Server secret `SEALED_SENDER_SERVER_KEY` | Signs a sender certificate for each device, each day |
| **Server certificate** | Server config `SEALED_SENDER_SERVER_CERTIFICATE` (public) | The trust root's statement that the server key is genuine |

`server/src/cli/sealed_sender_keys.ts` generates the set. It writes the two
private keys to files with mode `0600` and prints only public values, so no
secret ever lands in a terminal scroll-back or a log. The trust-root private key
is then moved off the machine. With it offline, a stolen server key can be
replaced by issuing a new server certificate without touching the apps.

Without the three values configured, sealed sender is **off**: the routes
answer `503 sealed_sender_unavailable` and the app sends the way it does today.
Tests generate an ephemeral set; development does too, with a warning.

## Sender certificates

`GET /v1/certificate/delivery`, authenticated **and licensed**. It answers a
certificate naming this account, this device's index and **the identity key the
server holds for this device**, not one the caller supplies, valid for 24 hours.

This is where the license is enforced for sealed sending. The send itself
cannot be: a send the server cannot attribute is a send it cannot check a
license for. A device that loses its license keeps a certificate for at most a
day, which is the bound.

## Who may send sealed to whom: the access key

Unauthenticated sending needs a gate, or anyone could fill anyone's queue. The
gate is Signal's: an **unidentified access key**, 16 bytes derived on the
recipient's device from its **profile key** with HKDF-SHA256. The profile key
already reaches exactly the people this account has written to, inside
end-to-end encrypted messages (it is what opens the profile picture). So "may
send me sealed messages" means "is somebody I have been talking to", decided by
the recipient's own key distribution and not by the server.

* The owner stores the derived key with `PUT /v1/accounts/me/unidentified-access`.
  The server keeps it in `accounts.unidentified_access_key` (bytea, never
  returned) and compares in constant time.
* A sender presents it in the `Unidentified-Access-Key` header of
  `POST /v1/messages/sealed`.
* No key stored, wrong key, unknown recipient: **one answer**, `401
  unidentified_access_denied`. Three different answers would turn the route into
  a way to test whether an account exists.

## Blocking

Today the server drops messages from a blocked account. It cannot for a sealed
message, because it does not know who sent it. Blocking therefore moves to where
the knowledge is:

1. **Rotate the profile key** on block. The blocked account's copy no longer
   derives the access key, so its sealed sends are refused at the door.
   Everybody else receives the new key with the next message they get.
2. **The device drops** anything whose certificate names a blocked account.
3. The unsealed path keeps the server-side check it has today.

## The sealed route

`POST /v1/messages/sealed`:

* **No session.** A request carrying `Authorization` is *refused*
  (`400 do_not_identify`): a sealed send that also identifies its sender is a
  bug that would silently undo the point, and failing loudly is how it gets
  noticed.
* **Not logged.** The route runs at log level `silent`, so neither its URL nor
  the caller's address is written down. Rate-limited per address in memory, as
  every anonymous route is.
* Same device reconciliation as an ordinary send (`409 device_mismatch`), same
  envelope size limit, same `expiresInSeconds` bound.
* The envelope is stored with `envelope_type = 'sealed'` and **no sender
  columns**. `GET /v1/messages` returns it with `senderAccountId: null`.

## What stays visible, said plainly

* **Recipient, time and padded size.** Delivery needs the first; the rest is
  inherent to a store-and-forward server.
* **The sender's IP address on the connection**, as for any request. It is not
  logged for this route, but a server operator recording traffic at the network
  layer could correlate a sealed send with the same address's authenticated
  requests. Using a proxy (`docs/custom-proxy.md`) breaks that link.
* **Group messages** are fanned out by the server per member, so group
  membership stays known (`docs/metadata-privacy-review.md` §7). Sealing them
  hides *which member* wrote, which is the part sealed sender can do. That is a
  later phase.
* **First contact.** Someone who has never received this account's profile key
  holds no access key and sends unsealed. The first message of a conversation
  is therefore attributable; replies and everything after are not.

## Phases

1. **Server** (this change): keys and certificates, access keys, the sealed
   route, sealed envelopes on the drain, wipe clears the access key. Tested.
2. **Native library from source:** vendor the Dart binding, CI builds libsignal
   for Android and iOS from the pinned tag, no downloads.
3. **App:** fetch and cache the certificate, pin the trust root, derive and
   upload the access key, seal one-to-one messages when the recipient's access
   key is known, fall back to unsealed when not, open sealed envelopes, drop
   blocked senders, rotate the profile key on block. Shown in the privacy
   dashboard as what it is.
4. **Receipts and typing indicators sealed** the same way. Then **groups**.

Only when phase 3 ships may anything in the app or in a store listing say that
Privio hides who talks to whom, and then only for what is sealed.
