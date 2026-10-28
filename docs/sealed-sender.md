# Sealed sender

**Status:** phases 1 to 3 implemented: server, native library built from
source, and the app (see "Phases" below). One-to-one messages go sealed where
the server has its sealed-sender keys configured and the recipient's access key
is known. Without the keys on the server, nothing is sealed and the privacy
dashboard says so. Not yet confirmed on real devices.

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
| Sender IP address at send time | seen on the connection, not logged | seen on the connection, not logged, nor is the request at all |

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

In the app (`ConversationController.rotateProfileKey`):

* The key is rotated only where this device can open sealed messages. Without
  sealed sender there is no door to shut, and a new key would only cost
  contacts the profile picture until they hear from this account again.
* The profile picture is sealed under the profile key, so it is re-uploaded
  under the **new** key first. If that fails, the key stays as it is and the
  device still drops what the blocked account seals.
* The new access key is published right after. Offline, the next start
  publishes it.
* The blocked list the device drops by is read at sign-in, again after every
  block and unblock, and before the first sealed envelope is opened if it has
  not arrived yet.

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

## The app

`app/lib/services/sealed_sender_service.dart` holds this device's side,
`app/lib/crypto/privio_crypto.dart` (`sealSealedForDevices`, `openSealed`) the
two library calls.

**Trust root.** A release can carry it in the build
(`--dart-define=PRIVIO_SEALED_TRUST_ROOT=<base64>`); then it is the only one
accepted and the server is never asked. Without that, the first answer of
`GET /v1/certificate/trust-root` is pinned in the secure store, as a contact's
key is on first use, and every later answer has to match it. A different one
stops sealed sender on this device, sending and opening, and the privacy
dashboard says it stopped. Nothing is learned from a server that offers a new
root. The build pin is the stronger choice for a release, because trust on
first use trusts whatever server answers first.

**Certificate.** Fetched at sign-in, kept, and fetched again an hour before it
runs out, so no message leaves with one that expires on the way. No license or
no answer: the device still opens sealed messages, sends the usual way, and the
dashboard says "receive only".

**Access key.** Derived from this account's profile key with HKDF-SHA256 (info
`Privio unidentified access key`, 16 bytes) and published at every start and
after every rotation. A reference vector in
`app/test/sealed_sender_crypto_test.dart` keeps the derivation from drifting
between versions, because sender and recipient have to agree on it.

**Sending.** A one-to-one send goes sealed when sealed sender is on, the
recipient's profile key is known on this device, the recipient is not this
account, and the recipient's door has not refused this key in the last hour.
Receipts, typing notices, edits and deletions are one-to-one sends too, so they
go sealed under the same conditions. Otherwise, and when the server answers
`401 unidentified_access_denied` or `503 sealed_sender_unavailable`, the
message goes the way it always has. Any other failure (`409 device_mismatch`
among them) is reported exactly as for an unsealed send, never quietly sent
unsealed instead. The sealed route takes no idempotency key, because a key
that repeats across retries would tie them together; a repeated sealed
message is recognised on the receiving device by the client id inside it.

**Opening.** The sender comes out of the certificate, checked against the
pinned trust root and the time the server received the envelope. One decision
differs from libsignal's own default and is deliberate: the library would
refuse a sender whose identity key differs from the one stored on this
device, and the message would be lost without even a name to show. Privio
hands the library no stored identity for that check. Instead, before anything
is decrypted, it requires the key in the certificate to be the key of the
message inside (the pre-key message's identity key, or the stored identity
for an ordinary message). A message that passes is opened through the same
code as every unsealed one, so a changed key is accepted and reported exactly
as it is today, with the key-change notice in the chat. A sealed envelope that does not open is reported without a
sender, because nothing that could be trusted named one.

## What stays visible, said plainly

* **Recipient, time and padded size.** Delivery needs the first; the rest is
  inherent to a store-and-forward server.
* **The sender's IP address on the connection**, as for any request. No
  request writes it to the log any more, and this route logs nothing at all,
  but a server operator recording traffic at the network
  layer could correlate a sealed send with the same address's authenticated
  requests. Using a proxy (`docs/custom-proxy.md`) breaks that link.
* **Group messages** are fanned out by the server per member, so group
  membership stays known (`docs/metadata-privacy-review.md` §7). Sealing them
  hides *which member* wrote, which is the part sealed sender can do. That is a
  later phase.
* **First contact.** Someone who has never received this account's profile key
  holds no access key and sends unsealed. The first message of a conversation
  is therefore attributable; replies and everything after are not.
* **Copies to this account's own devices** are sent the usual way: the server
  knows the account anyway, since it is the recipient.
* **The access key** is a fixed value per profile key. The server sees the same
  one on every sealed send to an account until the profile key rotates. It
  learns from that only what it already knows, the recipient.

## Phases

1. **Server** (this change): keys and certificates, access keys, the sealed
   route, sealed envelopes on the drain, wipe clears the access key. Tested.
2. **Native library from source** (done): the Dart binding is vendored in
   `app/third_party/libsignal_dart` with its provenance and review written down
   in `PRIVIO_VENDORING.md`; its download hook is replaced by one that only
   accepts a library compiled by `app/scripts/build_libsignal.sh` and fails the
   build otherwise; every workflow that builds or tests the app compiles
   libsignal first (`.github/actions/build-libsignal`), release and TestFlight
   builds without a cache. `app/test/sealed_sender_library_test.dart` seals a
   message from the app's existing Signal sessions and opens it again through
   that library, on every CI run.
3. **App** (done, see "The app" above): fetch and cache the certificate, pin
   the trust root, derive and upload the access key, seal one-to-one messages
   when the recipient's access key is known, fall back to unsealed when not,
   open sealed envelopes, drop blocked senders, rotate the profile key on
   block. Shown in the privacy dashboard as what it is: on, receive only,
   stopped, or off, with the note on which messages still name the sender.
   Tested in `app/test/sealed_sender_crypto_test.dart`,
   `sealed_sender_service_test.dart`, `sealed_sender_block_test.dart` and
   `privacy_dashboard_test.dart`; each rule there was broken once on purpose
   and its test went red.
4. **Groups**: sealing hides which member wrote. Membership stays known.

Anything in the app or in a store listing may say that Privio hides who sent a
message only for what is sealed, and only once the server has its keys
configured: one-to-one messages after the first, not groups, not first
contact. The dashboard row is the place that says it, and it says it only when
it is on.
