# The optional phone number

A phone number somebody may attach so contacts can find them. **PRIVIO works
completely without one**, and this document is partly about the lengths the code
goes to in order to keep that true.

## The number is not an identity

The PRIVIO ID is. A number here is a lookup key, and specifically **not**:

| | |
| --- | --- |
| A way to sign in | There is no phone login. `POST /v1/sessions` takes a username and a password. |
| A way to recover an account | Recovery is the archive key, as it was. |
| A way to merge accounts | Proving a recycled number moves the *link*. The previous holder keeps their account, their chats and everything else; they simply stop being findable by that number. |
| A field in registration | `POST /v1/accounts` has no phone field. The app offers a code **after** the account exists. |

An empty field never blocks anything: `PhoneField` has no validator, an unparsed
number yields null exactly as an empty one does, and every branch of the sign-up
flow ends with a finished account.

## What the contact matching is worth

This is the part to read carefully, because it is easy to overclaim and this
document does not.

**The mechanism.** The client normalises a number to E.164 and computes
`blind = HMAC-SHA256(DISCOVERY_CONTEXT, e164)`. It sends only blinds. The server
computes `HMAC-SHA256(pepper, blind)` and matches that against `phone_links`.
Both steps are HMAC-SHA256 from a standard library — `node:crypto` on the server,
`package:crypto` in the app. There is no primitive here this project wrote, and
there is no protocol either. It is keyed hashing.

**What it buys.**

- A dump of `phone_links` without the pepper says nothing. The pepper lives in
  the environment, not the database.
- The server is never handed a plaintext address book, so ordinary operation
  does not accumulate one.
- Nothing about a lookup is stored. The only row a match writes is the counter
  that limits how much looking one account may do.

**What it does not buy.** Stated here and in `services/phone.ts` rather than
left to be discovered:

- `DISCOVERY_CONTEXT` is **public**. It has to be — the client computes with it
  and it ships in the app binary. So anybody who observes a blind can brute-force
  it back to a number, because the phone-number space is about 10^10. **A blind
  is not an anonymised number** and no code here treats one as though it were.
- The pepper plus the table is the whole table, for the same reason.
- An operator *could* log what the discovery route is sent. This server does not.
  That is a property of this implementation, not something the cryptography
  enforces.

**So the defence that actually limits enumeration is the budget**, not the
hashing: 200 numbers per request, 2000 per account per day, counted in one
`INSERT … ON CONFLICT` so two requests in flight cannot both see room for the
last hundred. The hashing limits what a leak of data at rest is worth.

**No equivalence to any other messenger's architecture is claimed**, here or
anywhere in this repository. A design where the server *cannot* learn the query
is a private set intersection protocol or a trusted enclave. Neither is here:
SGX needs hardware this deployment does not have, and writing a PSI protocol
would be writing cryptography, which this project does not do.

## Two consents, kept apart

Both default to off, and neither implies the other.

- **Be found by my phone number** publishes something: it puts this account into
  the set a lookup can match. Changing the number resets it to off in the same
  statement that writes the new hash, because consent given for the old number
  does not carry to a new one.
- **Sync device contacts** reads something: it is consent to look at the address
  book, and it is the flag the app checks *before* asking the operating system
  for permission.

If the system permission is refused, the manual ways of adding somebody — the
PRIVIO ID, an invite link, a QR code — are unchanged, and the sentence that says
so is `failureContactsPermissionDenied`.

Only accounts with a **verified** number and discoverability **on** can ever be
a match. Both conditions are in the SQL rather than in a filter afterwards, so
there is no path that returns somebody who did not ask to be found. Removing the
`discoverable` gate turns three tests red.

## Reading the address book

Until this milestone the "Sync device contacts" switch wrote a flag and nothing
read an address book: the consent existed and the thing it consented to did
not. This is that half.

### The order, which is the design

1. **The consent is already on.** The match is not offered at all while the
   switch is off — not offered and refused, not offered and greyed, simply not
   there. The app never asks the operating system about contacts on its own
   initiative.
2. **Somebody presses the button.** Turning the switch on reads nothing. That
   matters on iOS in particular, where the system prompt appears once per
   install: spending it on a toggle would burn the one chance on something
   nobody had asked for yet.
3. **Then, and only then, the operating system is asked** — by
   `contacts/address_book.dart`, which is the only thing in the app that
   touches an address book, through `ContactsReader` on either platform.
4. **The numbers are blinded here.** `PhoneController.discover` hashes each one
   and sends hashes. What that is worth is the section above, and it is
   deliberately modest.
5. **Nothing is kept.** The numbers are not written anywhere, the matches live
   in the screen's own state, and turning the consent back off drops them on
   the spot.

### Only numbers are ever read

Android projects `Phone.NUMBER` and nothing else; iOS fetches
`CNContactPhoneNumbersKey` and nothing else. No name, no photo, no email, no
organisation, no note — so there is no name to leak, because none was ever
asked for. That is visible in one line of each reader rather than in what
happens to the objects afterwards, which is the point of doing it that way.

Both sides de-duplicate before returning. An address book routinely holds one
number three times (a contact merged from two accounts, the same mobile under
"work" and "mobile"), and each duplicate would otherwise spend another slot of
a daily budget that is deliberately small.

### Three answers, three sentences

`AddressBookRead` is a sealed set because the screen has to say three different
things:

| | |
| --- | --- |
| Numbers | Blind them and ask the server |
| Denied | The sentence behind `failureContactsPermissionDenied` — **and a reminder that a PRIVIO ID, an invite link and a QR code all still work**. Not a dead end. |
| Unsupported | A build with no native half, or a platform with no address book. Said differently on purpose: sending somebody to a settings app for a permission that is not the problem helps nobody. |

A platform error that is *not* `permission_denied` reads as unsupported rather
than as a refusal, for the same reason.

On iOS 18 and later a **limited** grant — the person picked specific contacts —
is read exactly like a full one. The system decides what the store returns, and
an app that refused to work with a limited grant would be arguing with a
privacy choice.

### What a deployment without a pepper does

The row is shown and disabled, with the sentence saying this server cannot
match. It does **not** open the address book to then fail: reading contacts for
a request that was never going to work is the one cost that would be pure loss.

## Verifying

A six-digit code, stored as an Argon2id digest like every other credential here.
Ten minutes, five attempts, three sends, sixty seconds between sends. The
plaintext number exists in the server process for the length of one request,
because a text has to be addressed to something; it is not written to the
database, not returned, and not logged.

Nothing logs a number, a code, or a provider's response body.

## SMS configuration

| | |
| --- | --- |
| `SMS_PROVIDER` | `none` (default) or `twilio` |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` | required when `twilio` |
| `SMS_DEV_ECHO` | development only; **refused outright when `NODE_ENV=production`** |

**Unconfigured is an error with a name, not a pretence.** `NoSmsSender` refuses,
the route answers `sms_not_configured`, and the app shows a sentence saying this
server cannot send texts *and that PRIVIO still works without a number*. The row
that would add one is disabled rather than offered and always failing.

`SMS_DEV_ECHO` returns the code in the API response so the flow can be worked on
without a paid account. Every response it produces carries `developmentStub:
true`, and the verification sheet shows a warning box saying no text was sent.
It is not a finished feature and nothing presents it as one.

## The discovery key

```
CONTACT_DISCOVERY_PEPPER=$(openssl rand -base64 32)
```

Empty means the feature is off — the routes answer `discovery_not_configured`
rather than hashing under an empty key and producing a table that looks
protected and is not. `discoveryHash` throws rather than falling back.

Keep it out of the database; its whole job is to be somewhere a database dump is
not. **Changing it invalidates every stored link**, because the hashes no longer
match, and everybody has to verify their number again. That is correct behaviour
for a rotated key and it is not reversible.

## Removing a number

The row goes entirely rather than being marked inactive: the point of removing a
number is that the server stops holding the thing that links it to this account,
and a soft delete would keep exactly that.

## What is tested

`server/test/phone.test.ts` (27) and `app/test/phone_controller_test.dart` (19),
`phone_test.dart` (9), `phone_screen_test.dart` (7),
`contact_match_test.dart` (10): registering with no number,
a verification that works and one that does not, the attempt and resend limits,
an expired code, a changed number, a removed number, a recycled number that does
not merge accounts, an account switch, and — the one that matters most — that a
verified but not discoverable number is never a match.

The client and the server must blind identically or nothing ever matches, and
the failure would look like "discovery finds nobody" rather than a hashing bug.
Both suites assert the same literal for the same number.

`contact_match_test.dart` covers the address-book half, and its central test is
not "does a match work" but **"is a plaintext number anywhere in what was
sent"** — asserted against the raw request body, for the number as typed, for
its normalised form, and for the bare national part. Replacing
`PhoneNumbers.blind(...)` with the number itself turns it red. So does reading
the address book when the consent switch is flipped: a fake address book counts
how many times it was asked, which is the only way to prove it was left alone.

**None of this has been run on a phone.** A widget test can drive a fake
address book; it cannot show the system permission dialog, and it cannot say
what a real address book with 800 entries costs. See rows S1–S6 in
[`device-beta-checklist.md`](device-beta-checklist.md).
