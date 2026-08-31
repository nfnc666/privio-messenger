# Licensing

Privio Libre (F-Droid) and the direct APK are free to download and activated
with a license key. The App Store and Google Play builds are paid for through
those stores instead.

This document describes where a license lives, who may create one, and what a
client can and cannot decide for itself.

## Why the license lives here

A key is bound to an account on redemption — "one key, one account, for good".
Accounts exist only on this server, so the license has to exist here too. The
website sells the key and hands it to the buyer; it never sees an account and
never decides whether anyone is licensed.

```
  Website                        Server (this repo)                 App
  ───────                        ──────────────────                 ───
  payment confirmed
  by signed webhook
        │
        │ POST /v1/internal/licenses          licenses row created
        │ Bearer LICENSE_ISSUER_TOKEN  ─────► key generated, hash stored
        │ ◄───────────────────────────────── licenseKey (once, only here)
        │
   shows the key
   to the buyer  ───────────────────────────────────────────────►  user types it
                                                                        │
                    POST /v1/licenses/redeem  ◄──────────────────────────┘
                    Bearer <session token>
                    ───► bound to the account, atomically

                    GET /v1/licenses/me       ◄─── what the app renders
                    POST /v1/messages         ◄─── refused while unlicensed
```

## What the user goes through

```
  install                                          Privio Libre from F-Droid
     │
     ▼
  first launch          GET /v1/server        ──►  does this server sell
     │                  (no auth, no account)      licences at all?
     │                  ◄── licenseRequired
     ▼
  "Enter License Key"   ── shape checked on device, held in the keystore
     │                     (or walked past — the screen is not a wall)
     ▼
  create the account    POST /v1/accounts     ──►  account + first device
     │
     ▼
  key is spent          POST /v1/licenses/redeem   bound to the account,
     │                  Bearer <session>      ──►  atomically, once
     │                  ◄── licensed, maxDevices   pending key cleared
     ▼
  normal use            status cached locally so the app can say something
                        true while offline — a cache, never a gate
```

The order is the point. A key is what the hosted service is paid for, so it is
asked for before the account rather than after: asking later would mean letting
someone in for free and then presenting a bill. But the screen has a way past
it. Someone who has not bought a key yet, or who is about to point the app at
their own server, can create an account and read what arrives — the server
holds back sending, and nothing else.

`GET /v1/server` exists for exactly one reason: the app has to know whether to
show that screen before anyone has signed in, which the authenticated licence
endpoint cannot answer. It is the only endpoint an unauthenticated caller can
reach, and it carries policy — never state, never a secret.

## Devices

`licenses.max_devices` is what a purchase is worth. It is checked when a device
registers, inside the transaction that already holds the account row lock, so a
licence revoked mid-registration cannot be raced past.

An account with no active licence falls back to `DEFAULT_DEVICE_LIMIT`, and a
revoked licence drops it back to the same place rather than to zero: someone
who has lost a licence can still reach their account and read what already
arrived, which is the same split the send gate uses.

`GET /v1/licenses/me` reports `maxDevices` and how many are in use, so a client
can say "2 of 5" rather than guess. An older server reports neither, and a
client that sees neither must not claim a limit.

## Storage

Only `hmac_sha256(LICENSE_HASH_SECRET, normalised_key)` is stored. The hash has
to be deterministic — a redemption arrives with the key and nothing else to
look it up by — which rules out Argon2 here. Keying the hash is what replaces
it: without the secret, a stolen database is not something an attacker can
grind 80 bits of key entropy against.

`LICENSE_HASH_SECRET` cannot be rotated. Changing it orphans every license ever
issued, because none of the stored hashes match any more.

## Key format

```
PRIVIO-XXXX-XXXX-XXXX-XXXX
```

16 symbols of Crockford base32 (no I, L, O, U) — 80 bits. On the way in, a key
is folded to a canonical form: case, separators and the Crockford aliases
(`O`→`0`, `I`/`L`→`1`, `U`→`V`) are all normalised, so a key read off a screen
and typed by hand still activates.

## Redemption is one statement

```sql
UPDATE licenses SET redeemed_by = $2, redeemed_at = now()
 WHERE key_hash = $1 AND status = 'active' AND redeemed_by IS NULL
 RETURNING source, redeemed_at
```

There is no read-then-write window for two devices to race in: the row is only
claimed if it is still unclaimed. Zero rows back means the key does not exist,
was revoked, or belongs to someone else — and only then is it worth a second
query to say which.

A partial unique index on `redeemed_by` enforces one license per account. When
it fires, the transaction rolls back, so a key offered to an already-licensed
account is rejected without being consumed — it is still worth something.

Re-sending the same key from the account that already holds it returns success.
That is a retry after a lost response, not an error.

## Enforcement

`LICENSE_REQUIRED=true` makes the server refuse to relay for unlicensed
accounts. Gated: sending a direct or group message, creating a group, creating
a channel, posting to a channel. Not gated: signing in, registering a device,
fetching what was already delivered, redeeming a key.

That split is deliberate. An unlicensed user can still reach their account and
activate it, and messages that were already delivered never become unreadable
because of a billing state.

The app collects the key in two places — the activation step at first start
(`app/lib/screens/activation_screen.dart`) and the License screen in Settings
(`app/lib/screens/license_screen.dart`) — and both only show what the server
answered. They are couriers, not gates.

The same goes for the status cached in the keystore. It exists so a launch with
no signal renders the truth rather than a question mark, and so a paying user is
never accused of not having paid because a request timed out. It decides
nothing: a value the device holds is one deleted line away from being bypassed
in a build anyone can compile.

**Client-side checks are cosmetic.** Privio Libre is open source; anyone can
build it with the license screen removed. Only the server refusing service
enforces anything, which is why the gate is a `preHandler` here and not a
condition in the app.

**Self-hosting.** A self-hosted deployment leaves `LICENSE_REQUIRED=false`. A
licence for infrastructure you already own would mean nothing, and the server
tells the app so in `GET /v1/licenses/me` (`required: false`), which is how a
client knows not to ask for a key at all.

## Endpoints

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/v1/licenses/redeem` | session | Redeem a key for the calling account |
| GET | `/v1/licenses/me` | session | `{ licensed, source, redeemedAt, required }` |
| POST | `/v1/internal/licenses` | issuer token | Issue a license for a paid order |
| POST | `/v1/internal/licenses/revoke` | issuer token | Revoke after a chargeback |
| GET | `/v1/server` | none | Whether this server requires a licence at all |

Redemption is rate limited to 5 attempts per 10 minutes per device.

### Issuing is once-only

`POST /v1/internal/licenses` takes an optional `maxDevices` and returns the
plaintext key exactly once. A retried
webhook for the same `(paymentProvider, paymentReference)` gets `409
license_already_issued` with the license id — not a second key, because the
order was only paid once and the plaintext no longer exists on this side.

**The website must persist the key it is given.** This server cannot show it
again.

### Error codes

| Code | Status | Meaning |
| --- | --- | --- |
| `license_not_found` | 404 | No license matches the key |
| `license_already_redeemed` | 409 | Redeemed by another account |
| `license_revoked` | 409 | Refunded or charged back |
| `account_already_licensed` | 409 | The account already holds a license |
| `license_required` | 403 | The gate: activate a key to send |
| `license_already_issued` | 409 | This order already has a license |

## In the app

`lib/core/license_controller.dart` holds the client side, and holds it thinly:
it asks `GET /v1/licenses/me`, shows the answer, and turns error codes into
sentences. It never decides that anyone is licensed.

* The key screen (`lib/screens/activation_screen.dart`, `AppStage.activation`)
  is reached from two directions, on a server that answered `required: true`
  and in a build that is activated with a key — the Libre build and the APK
  from the website. **Before the account**, on a fresh install: there is nobody
  to bind a key to yet, so it is held in the keystore and spent by the first
  sign-in. And **once per account after signing in**, for anyone who walked
  past it and is still unlicensed. A
  Play or App Store build was paid for at the moment it was installed and is
  never shown a key field; if it still comes back unlicensed, that is a
  receipt to settle with the store, and the License row in Settings says so.
  It is a step, not a wall —
  "Not now" goes through to the app, because the server itself lets an
  unlicensed account sign in and read. Refusing entry would be the client
  inventing a restriction the server does not apply.
* That question is remembered per account (`privio.license.activation_asked_for`
  in the keystore), so someone who skipped it is not asked again on every
  launch; a second account on the same device is asked in its turn, and a
  successful activation is not recorded at all — the server simply stops
  saying a key is needed.
* The **Privio License** row in Settings appears only when the server answered
  `required: true`, and reads *Not active* until a key is redeemed. On a
  self-hosted deployment there is nothing to buy, so there is no payment prompt
  anywhere.
* The key field folds Crockford aliases as you type and sends the canonical
  `PRIVIO-XXXX-…` form; the server folds again on arrival, and doing it on both
  sides is what makes the key that was typed and the key that is stored the
  same string. A key that is not even 16 symbols is refused on the device:
  redemption allows five attempts per ten minutes, and a typo should not spend
  one. It is one widget
  (`lib/widgets/license_key_field.dart`) shared by both screens, so a key typed
  at first start and a key typed in Settings reach the server in the same
  shape. Typing the printed `PRIVIO` prefix by hand is not folded into the key
  body — the prefix contains an I and an O of its own — and backspace clears
  the field rather than putting the prefix back.
* A `403 license_required` on send is turned into "Activate your license to
  send messages", with a button to the screen, rather than repeating the
  server's wording.
* A server old enough to lack the endpoint answers 404, which the client reads
  as "does not require a license" instead of showing an error. Every other
  failure leaves the last known answer alone — offline is not unlicensed.
* A server old enough to lack the endpoint answers 404, which the client reads
  as "does not require a license" instead of showing an error.

Removing that screen from a build changes nothing: the gate is a `preHandler`
here, not a condition there.

## Store purchases

Apple and Google receipts are validated server-side and written to the same
table with `source = 'apple' | 'google'`. One query then answers "is this
account licensed", however it was paid for. Receipt validation is not
implemented yet; the column and the check are already shaped for it.

## Configuration

```
LICENSE_REQUIRED=true
LICENSE_HASH_SECRET=<32+ random bytes, never rotated>
LICENSE_ISSUER_TOKEN=<32+ random bytes, shared with the website only>
```

The server refuses to boot with `LICENSE_REQUIRED=true` and no hash secret: a
paid deployment that cannot tell who has paid is worse than one that will not
start.
