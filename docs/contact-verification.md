# Verifying a contact

The screen that makes end-to-end encryption checkable:
**chat → header → Safety number**.

Everything else in Privio takes the server's word for who a key belongs to. This
is where that stops.

## What the number is

Signal's `NumericFingerprintGenerator`, from `libsignal_protocol_dart`: 5200
rounds of SHA-512 over each side's **real long-term identity key** and account
id, folded to thirty digits per side and concatenated in a fixed order. Privio
implements none of it and invents none of it.

**One number per device, not one per person.** In Privio each device has its own
identity key and is trusted separately, so a single number would be a summary of
several trust decisions and would go stale for reasons nobody could act on.

## Three ways to compare, one comparison

People are in different rooms, so there are three routes to the same check:

1. **Read the sixty digits aloud** — over a phone call, or across a table.
2. **Paste what they sent** into the compare box, for the case where the digits
   arrived in writing. Comparing sixty digits by eye is where the one mistake
   this screen exists to prevent gets made.
3. **Photograph their QR code**, when you are standing next to each other.

All three compare a fingerprint computed from the same two identity keys, and
**all three happen on the device**. Nothing about a comparison is sent anywhere.

## The QR code

The payload is Signal's `ScannableFingerprint` — a protobuf holding both sides'
fingerprint halves — base64-encoded, produced by the same generator run that
produced the digits. Encoding a format of Privio's own would mean a code only
Privio can read and a comparison only Privio has ever checked, on the one screen
where being wrong is indistinguishable from being attacked.

The comparison is the library's `compareTo`, and it is **two-sided**: their local
half must equal my remote half *and* their remote half must equal my local half.
Two consequences, both of them tests in `qr_scan_test.dart`:

* a code replayed from a **third person's conversation** does not match;
* holding the phone up to a **mirror** — scanning your own code — does not match.

### Why there is no live scanner

Every live-scanning package that works well on Android goes through Google's ML
Kit, which would put a Play Services dependency into a build whose whole claim
is that it has none (`docs/privio-libre.md`). Instead the camera Privio already
opens for chat photos takes **one photograph**, and `media/qr_scan.dart` decodes
it in Dart with `zxing2`.

The trade is honest: a photo of a screen has to be reasonably square-on and in
focus, where a live scanner keeps trying thirty times a second. What is gained is
a decode that links nothing and is testable end to end — the round trip through a
generated QR, including a photograph-sized one, is in the test file.

A scan that matches does **not** mark the contact verified by itself. The button
below does that, which keeps "I checked this" something a person did.

## What is stored, and what breaks it

Marking verified records **the identity keys that were on screen**, per device —
not a flag. So "is this still the thing I checked?" is a comparison rather than a
promise, and it fails by itself when:

* a contact's identity key changes (reinstall, new phone, or substitution);
* a **new device** appears on their account.

Either shows as `VerificationState.changed`, with a warning, and needs comparing
again. Nothing silently re-trusts a changed key: sends are refused
(`IdentityChangedException`) until the user answers the change on this screen.

## Holding a chat after a key change — optional

`Settings → Privacy & Security → Contact identity → Hold chats after a key change`

**Off by default.** On, a one-to-one chat whose safety number changed is held:
the composer is disabled and a banner points at the number.

Being exact about what this does, because the difference between a security
control and a comfort blanket is exactly here:

* **Sending is refused on a changed key whether this is on or off.** That is the
  crypto layer's pinning and it has never been optional. The setting does not
  add it.
* What it adds is that the chat stops *looking* usable, instead of accepting a
  message that will fail.
* **Messages already received are not deleted or hidden.** Privio does not throw
  away something it has already decrypted. Deleting them would destroy evidence
  of the very event the user is being warned about.
* Groups are not held. Locking a group of twelve because one member reinstalled
  is not a control anybody would leave on.

The setting is local and the server is never told — a server that knew which of
its users refuse unexplained key changes would know which of them not to try it
on. `key_change_hold_test.dart` holds that, and holds that the setting is per
account and that a read landing after an account switch is dropped.
