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
`phone_test.dart` (9), `phone_screen_test.dart` (7): registering with no number,
a verification that works and one that does not, the attempt and resend limits,
an expired code, a changed number, a removed number, a recycled number that does
not merge accounts, an account switch, and — the one that matters most — that a
verified but not discoverable number is never a match.

The client and the server must blind identically or nothing ever matches, and
the failure would look like "discovery finds nobody" rather than a hashing bug.
Both suites assert the same literal for the same number.
