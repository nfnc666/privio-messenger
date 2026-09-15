# Anrufverschlüsselung / Call encryption

What a Privio call guarantees, how it is enforced, and what it still does not
cover. Written so the claims can be checked against the code rather than taken
on trust — every rule below names the file it lives in and the test that holds
it.

## The short version

* The media of every call is **DTLS-SRTP**. There is no unencrypted mode, no
  downgrade, and no fallback. A negotiation that could end in plain RTP is
  refused before it reaches the media stack.
* A TURN server relays **ciphertext only**. It never holds the SRTP keys: those
  come out of a DTLS handshake between the two devices, and the relay is not a
  party to it.
* Who is at the far end is decided by the **identity key that opened the
  envelope**, never by the account id the server wrote beside it.
* Any check that fails **ends the call** and tells the user which one, in their
  language.
* The call screen says "end-to-end encrypted · verified" only where a person
  actually compared a safety number.

No cryptography is written in this repository for any of this. The media
encryption is libwebrtc's DTLS-SRTP; the signalling encryption is libsignal's
Double Ratchet, through `libsignal_protocol_dart`. What Privio adds is policy:
which negotiations it will accept, and whom it will accept them from.

## The chain, end to end

A call is secure because each link below is fastened to the next. Break any one
and the rest is worth nothing, which is why all of them are checked.

```
the other person's PRIVIO identity key   (pinned on this device; safety number)
        │  authenticates
        ▼
the Signal session with their device     (libsignal Double Ratchet)
        │  seals
        ▼
the SDP offer / answer                   (the server relays, cannot read)
        │  commits to
        ▼
a=fingerprint: sha-256 …                 (the far end's DTLS certificate)
        │  is verified against
        ▼
the DTLS handshake                       (libwebrtc; certificate must match)
        │  derives
        ▼
the SRTP keys                            (the audio and video; TURN sees this)
```

The signalling server can see that two accounts exchanged envelopes. It cannot
read the SDP, does not learn the fingerprint, and is not in the DTLS handshake.

## What is enforced, and where

### 1. The negotiation can only end in encrypted media

`app/lib/calls/sdp_policy.dart`. Every session description — incoming *and* the
ones this device produces — is read before it is used, and refused unless:

| Rule | Why |
| --- | --- |
| Every `m=` line names a DTLS-protected profile | `RTP/AVP` and `RTP/AVPF` are plaintext audio and are legal SDP |
| The profile is on an allow-list, not a deny-list | A profile nobody thought of is refused rather than assumed safe |
| No `a=crypto:` anywhere | SDES puts the media key in the document instead of in a handshake |
| An `a=fingerprint:` covers every section | Without it nothing binds the sealed description to the far end |
| The hash is sha-256, sha-384 or sha-512 | sha-1 is still offered by some stacks and is the wrong place to be lenient |
| All sections name **one** certificate | Two certificates is one stream to one place and one to another |

This device applies the same policy to its own offer and answer before sending
them: if this stack ever produced something downgradeable, sending it would be
offering the other side the downgrade.

### 2. The far end is a key, not a label

`app/lib/crypto/privio_crypto.dart` → `openEnvelope` returns an
`OpenedEnvelope`: the plaintext, **the identity key that actually opened it**,
and how that key stood (`PeerTrust.pinned`, `firstContact`, `replaced`).

This matters because `senderAccountId` on an envelope is written by the server.
A relay can put any name on any envelope. What it cannot do is make a message
open under a key it does not have — and if it supplies its own key under a name
this device already knows, the pin is *replaced*, and that is visible.

`app/lib/calls/call_security.dart` → `CallGuard` decides:

| Situation | Calls |
| --- | --- |
| Key pinned, unchanged | Yes — "end-to-end encrypted" |
| Key pinned and the user compared the safety number | Yes — "end-to-end encrypted · verified" |
| **Key replaced under this very envelope** | **No — `callIdentityChanged`** |
| Safety number was confirmed and no longer matches | **No — `callIdentityChanged`** |
| No key at all opened the envelope | **No — `callIdentityChanged`** |
| First contact, nothing pinned before | Yes, and never called verified |
| Strict mode on, not verified | **No — `callNotVerified`** |

Once a call is admitted, the key is fixed for its lifetime. Every later signal —
the answer, each ICE candidate, the hang-up — must come from the same account
**and** the same key. Checking only the account would leave the substitution
open on the answer; checking only the key would let one person's second device
step into somebody else's call.

A replayed offer with the same call id but a different certificate is refused
rather than silently dropped as a duplicate.

### 3. First contact, and why it is not refused

A call from an account whose key this device has never seen is allowed, pinned,
and never labelled verified. That is the same trust-on-first-use the whole app
runs on: refusing would mean nobody could call you before writing to you, and
would not close the hole — on first contact there is by definition nothing to
compare against.

Whoever wants the stronger guarantee can turn on **Settings → Privacy → Calls →
"Only calls from verified contacts"** (off by default, stored per account). With
it on, a call happens only with somebody whose safety number this device has
confirmed; every other call ends with an explanation naming the person.

### 4. A failed check ends the call, out loud

There is no branch that downgrades, retries, or connects-and-warns. Every
refusal goes through `CallService._refuse` / `_refuseIncoming`, which:

* ends the call as `CallEnding.failed`,
* files it in the call log — a refused call is a thing that happened to the
  user, and a log that hides it hides exactly the events worth noticing,
* sets a `Failure` the screen renders in the reader's language (all five), and
* tells the other side the call is over, **without** saying which check fired —
  a relay that learns which check to avoid is a relay that avoids it.

A call refused before it rings never gets a call screen, so the reason is shown
as a banner over whatever is open, and it stays until dismissed rather than
timing out like a snackbar.

## Tests

| File | Holds |
| --- | --- |
| `test/sdp_policy_test.dart` | 18 tests: plain RTP, SDES, missing fingerprint, sha-1, md5, mismatched certificates, no media — each refused, and the valid shapes accepted |
| `test/call_security_test.dart` | 25 tests: every refusal above driven through `CallService`, plus the padlock states and the strict-mode switch |
| `test/call_security_test.dart` → "a relay with the label in its hands" | **The actual substitution**, with real libsignal: Alice writes to Bob (her key is pinned), then Mallory's sealed call offer is relabelled `account-alice`. It decrypts — and comes back as `PeerTrust.replaced`, and Bob's phone does not ring. Its control case shows a stranger can still call under their own name |
| `test/call_test.dart` | The call machinery, now driving the real SDP policy: the fake peer emits fingerprinted descriptions, and the identity is threaded exactly as the app threads it |

The guard was checked by removing it: deleting the `PeerTrust.replaced` branch
in `CallGuard.admit` turns the substitution test and two others red.

## What this does not cover

* **Traffic analysis.** A call is a continuous stream of a recognisable shape.
  The server learns that two accounts exchanged envelopes and, if it is also
  the TURN server, that a relayed flow existed, how long it lasted and roughly
  how much data moved. Encryption does not hide any of that.
* **Addresses.** Once media flows peer to peer, each side learns the other's IP.
  A TURN relay is what hides it, at the cost of the relay seeing the flow.
* **First contact.** Trust on first use is trust on first use. The safety-number
  screen and the strict-mode switch are what turn it into something checked.
* **A compromised device.** Everything here is about the network and the server.
  It says nothing about a phone somebody else is holding.
* **Group calls.** Privio has none. When it gets them, the guarantee above is
  pairwise and does not extend to a mixer by itself.
* **Not yet confirmed on real hardware.** The rules above are held by automated
  tests against a stand-in media peer. That a real libwebrtc build negotiates
  exactly these descriptions on a real network is not something this repository
  has measured.
