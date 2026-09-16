# Key transparency — design study

**Status: design only. Nothing in this document is implemented, and nothing in
it should be half-implemented.** A key-transparency system that is partly built
is worse than none: it produces a green tick nobody has earned, and the green
tick is the whole product.

## The gap this is about

Privio's end-to-end encryption rests on a step it cannot check for itself.
`GET /v1/keys/:username` asks the server for a contact's device bundles, and the
server answers with `devices.identity_key` — the long-term public key each of
that account's devices registered. Every guarantee after that point is a
guarantee about *that key*.

Nothing in the protocol establishes that the key the server handed over is the
key the account registered. A server that wanted to read a conversation would
answer Alice with a key it holds the private half of, relay to Bob under his
real key, and sit in the middle. Signal's protocol is not broken by this; it is
simply answering a different question than the one the user is asking.

Two things already narrow it, and they are the reason this is a study rather
than an emergency:

* **Pinning.** The first key seen for a device is stored (`pinnedIdentities`)
  and a later different one is refused for sending — `IdentityChangedException`
  — and reported for receiving. A server that substitutes a key for an existing
  conversation is caught by every client that has one.
* **Safety numbers.** Two people who compare sixty digits over a channel the
  server does not control settle the question outright, per device, and can now
  do it by QR as well (`docs/` — see `crypto/safety_number.dart`).

## Threat model

**In scope.** A Privio server — operator, compromised host, or anyone with
write access to the `devices` table — that presents **different identity keys
for the same account to different users, or at different times**, in order to
read or inject messages. This includes:

* a targeted substitution against one contact of one account;
* a silent extra device added to an account, whose key then receives a copy of
  everything (the `devices` table is server-controlled, so this needs no client
  cooperation);
* a substitution against a *new* conversation, where there is no pin to break
  and nothing to warn about. **This is the hole pinning does not cover and the
  one key transparency is actually for.**

**Out of scope, and not claimed.** Key transparency does not encrypt anything,
does not hide who talks to whom, does not protect a device that is compromised,
and does not help against a contact who is simply not who they say they are.
It answers exactly one question: *is everyone being shown the same key for this
account?*

## What it does not prevent

Stated plainly, because the failure mode of every transparency system is people
believing it did more:

* It does not stop the server from lying **once**. It makes the lie *detectable
  afterwards*, by a client that checks, if the server signed it into a log.
* It does not stop a server that simply declines to serve a proof. That has to
  be a visible, refusable state in the client, or the whole scheme degrades to
  nothing the moment the server stops answering.
* It does not protect the very first fetch if the client has no way to reach an
  auditor independent of the server. A log the server both writes and audits is
  a log the server can rewrite.
* It does not remove the need for safety numbers. Two people in a room comparing
  digits is still the only check with no third party in it at all.
* It does not cover anything but identity keys — not group membership, not
  channel keys, not the phone-number discovery mapping.

## Possible architecture

Do not invent this. Three published designs solve it and each has been reviewed
by people who do this for a living:

| Design | Shape | Cost |
| --- | --- | --- |
| **CONIKS** | Per-epoch signed tree of `username → key`, privacy-preserving lookups via VRF | Client must check its *own* entry each epoch |
| **Key Transparency (Google) / Parakeet** | Append-only verifiable log + auditors | Needs an auditor ecosystem to mean anything |
| **SEEMless / Signal's KT** | Append-only log of key changes, compact proofs, VRF-blinded labels | Closest fit; Signal ships it |

For Privio the realistic target is **Signal's**: it is designed for exactly this
data shape (an account with several devices, keys that change on reinstall), it
is deployed at scale, and there is a specification to implement rather than a
paper to interpret. The work is an implementation project with a published
answer at the end of it, which is the only kind of cryptographic work this
project should take on.

### Append-only log requirements

Whatever is chosen has to hold these, and each of them is a place a rushed
implementation fails:

1. **Append-only, verifiably.** Consistency proofs between any two tree heads,
   so a client can check that the log it sees today contains the log it saw last
   week. Without this the server can rewrite history and every proof still
   verifies.
2. **Signed tree heads, with an epoch and a timestamp**, signed by a key that is
   *not* the server's TLS key and is distributed with the app.
3. **Blinded labels.** The log must not be a downloadable list of who has a
   Privio account. A VRF over the account id, with the proof, is the standard
   answer; publishing `username → key` in the clear would trade one privacy
   problem for a worse one.
4. **Gossip or auditors.** A client that only ever asks one server whether that
   server is lying has learned nothing. At minimum: tree heads carried in
   messages between clients, so two contacts comparing them detect a split view.
5. **Non-repudiation of absence.** "This account has no key" must be provable,
   or the server can disappear an account's real key and substitute at will.

### Client verification flow

```
fetch bundle for @bob
  ├─ server returns devices + identity keys + KT proof (inclusion, epoch N)
  ├─ client verifies inclusion proof against signed tree head for epoch N
  ├─ client verifies consistency between its stored head (epoch M) and N
  ├─ client checks the returned keys equal the keys in the proof
  └─ any failure  → refuse to send, surface as a security state, never a retry
own account, each launch
  ├─ fetch proof for my own account
  ├─ compare the device keys in it against the devices I actually have
  └─ a key I do not hold  → "a device you do not recognise is receiving your
     messages", which is the event this whole system exists to surface
```

The self-audit in the second half is the part people forget and the part that
catches the silent-extra-device case.

### Privacy considerations

* The log is a record of *when each account changed keys*. Epoch granularity
  leaks reinstall timing; coarse epochs cost detection latency. This is a real
  trade and should be decided deliberately, not by whatever the library
  defaults to.
* Lookups tell the server who is looking up whom, exactly as `GET /v1/keys`
  already does. Key transparency does not make this worse, and does not make it
  better. See `docs/metadata-privacy-review.md`.
* Auditors see the tree heads, not the labels, if the VRF is used properly.
  Getting that wrong publishes the account list.

### Multi-device

Privio pins and verifies **per device** — each device has its own identity key
and its own safety number (`SafetyNumbers`, one per device). The log must
therefore map an account to a *set* of device keys with their own add and revoke
events, not to a single key. Consequences:

* A revoked device must appear in the log as revoked, not vanish; otherwise
  removal and substitution look the same to a client.
* Adding a device is a normal, frequent event. The client's own self-audit is
  what separates "I added a laptop" from "somebody added a laptop", and that
  needs the new-device-transfer flow to be the thing that adds devices, so the
  user has a moment they can recognise.
* The existing per-device safety numbers survive unchanged. Key transparency
  sits underneath them; it does not replace them.

## Migration strategy

1. **Publish without enforcing.** The server starts writing key changes to the
   log. Clients ignore it. This exposes the operational cost — epoch rate, log
   size, the code that backfills existing devices — with nothing to break.
2. **Verify without refusing.** Clients fetch and check proofs, and report a
   failure to the local security log (`SecurityEventKind`) and nowhere else.
   Run long enough to learn the real false-positive rate, which will not be zero.
3. **Surface.** Failures become a visible state on the chat and the safety
   number screen, alongside the existing key-change warning.
4. **Refuse.** A bundle with no valid proof stops being usable. This is the step
   that can lock people out of their own conversations, and it needs a
   deliberate, announced cut-over with a supported client floor.
5. **Self-audit on.** Clients check their own account each launch.

Steps 1–2 are safe to do incrementally. **Step 4 is not reversible in practice**
and should not be taken without external review of the implementation.

## What should happen before any of this is built

* An external cryptographic review of the chosen design as applied to Privio's
  per-device model, before step 1.
* A decision about auditors. Without an answer to "who, other than the Privio
  server, sees these tree heads", steps 3 and 4 are theatre.
* The metadata review (`docs/metadata-privacy-review.md`) settled, since the
  lookup pattern is shared.

Until then Privio's honest position is the one it already states on screen: keys
are pinned, a change is reported, and the number two people compare is the only
check that involves nobody else. **Privio does not claim key transparency, and
must not until it has one that someone outside this project has looked at.**
