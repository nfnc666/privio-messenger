# Two accounts on one phone

A phone is shared, handed on, resold, or simply used by somebody who keeps a
second account. Whatever the reason, the rule is one sentence:

> **Whatever an account sees must be its own.**

This document is what was wrong, what was changed, and — because the two are not
the same question — what to do about data that was already mis-assigned.

## What was reported

A new account was created on a device, and it opened onto the **previous
account's profile picture**. That is the symptom; there were three causes
behind it, and only the first was the one being described.

## Cause 1 — sign-out stopped the controller instead of taking it down

`AppState.signOut()` called `_conversations?.stop()`. That cancels timers and
closes the socket. It clears **nothing**: not the profile picture, not the
contact list, not the decrypted attachment cache, not the outbox.

The controller is then reached through a getter that builds one only if there
is not one already:

```dart
ConversationController get conversations =>
    _conversations ??= ConversationController(services);
```

So the next account was handed the previous account's controller, with
everything still in it. Signing in set a new `accountId` on the same object and
changed nothing else.

Both of the other teardown paths — `deleteAccount` and the duress wipe — already
disposed it and dropped it. Sign-out was the one that did not, and sign-out is
the only boundary two people on one phone ever cross.

**Fixed** by disposing and dropping it, the same shape the other two had.

## Cause 2 — the device kept signing as the account that left

`signOut` deliberately did not wipe the crypto store, on the reasoning that
signing back into the same account should keep its Signal sessions.

But what is in that store is not the *device's* — it is the **account's**: the
identity key a safety number is computed from, the sessions with every contact,
and the channel and group keys. Keeping it meant the next account on the phone

* published the previous account's identity key as its own,
* showed the previous account's safety number to anyone who verified it, and
* still held the keys to private channels it had never been a member of.

A test pins this down by comparing the identity fingerprint across a sign-out.
Before the fix the two were identical.

**Fixed** by wiping it on sign-out. This costs nothing that was not already
being paid: both `register` and `login` send a fresh device registration, and
`registerDevice` inserts a new device row for every sign-in regardless, so
re-registering is what already happened.

## Cause 3 — a slow reply could land in the next account's screen

A request goes out, the network is slow, and by the time the answer arrives the
person has signed out and somebody else has signed in. Applying that answer
writes one account's data into another account's screen.

Fixing this at the call sites would mean fixing it at *every* call site, and the
number of those only grows. It is fixed in the transport instead:
`PrivioApiClient` keeps a session counter that `useToken` bumps, every request
records the counter it was issued on, and a reply whose counter has moved is
refused with `StaleSessionException` before it is even decoded. One rule, obeyed
by every route, including ones not written yet.

Fire-and-forget work started at sign-in goes through `detached(...)`, which
drops that one exception and nothing else — a real failure in detached work is
still as loud as it ever was.

## Cause 4 — a push token could stay registered to two accounts

Not part of the report, found while checking the rest.

Signing out clears the push token. A sign-out that happened with **no network**
never reached the server, so the row kept it. The next account on that handset
then registered the same vendor token against its own new device, and the relay
went on posting the previous account's wake-ups to a phone that now belonged to
somebody else.

**Fixed** in `PUT /v1/devices/current/push`: registering a token takes it, and
any other device holding it is cleared in the same transaction. A vendor token
identifies one app install, so it can only belong to one account at a time.

## What was *not* wrong: the server

The server derives identity from the session and from nothing else. Every route
reads `auth(request)`, which is `resolveSession(bearer token)`; no route takes an
account id from a path, body or query and treats it as a claim about who is
asking. The account ids that *do* appear in paths are targets — who to promote,
ban or remove — and each is checked against the caller's membership and
permissions.

`test/account_isolation.test.ts` is B's session pointed at A's real identifiers:
A's backup, A's media by id, A's private channel and its posts, members and
statistics, A's devices, and a `PATCH /v1/accounts/me` whose body names A. It
also asserts the other half of the rule — that a **public** channel *is* visible
to B, because separation is not "B sees nothing", it is "B sees what B is
entitled to".

## Local storage, and what is keyed by what

| What | Where | How it is separated |
|---|---|---|
| Session, passcode, settings, archive key | `SecureStore` | Wiped entirely on sign-out |
| Message history | `EncryptedMessageArchive` | Sealed, **and stamped with its owner** |
| Signal identity, sessions, channel & group keys | `CryptoStorage` | Wiped on sign-out |
| Contacts, own avatar, attachment cache | `ConversationController` | In memory; disposed on sign-out |
| Channel list and pictures | `ChannelController` | In memory; disposed on sign-out |

The archive stamp is the one that survives a crash. Sign-out clears the archive
and the keystore in two separate writes, and a phone killed between them leaves
a history behind with no session — which the next account would otherwise load
as its own. The owner now travels **inside** the sealed payload (an owner a
thief could rewrite would be worse than no owner at all), and `restore()` names
the account it expects.

An archive written before this field existed carries no owner and is still
accepted. Refusing those would be a data-loss bug dressed up as a security fix.
See the residual risk below.

## Repairing data that was already mis-assigned

Two different situations, and neither is repaired by guessing who owned what.

### On the server: nothing to repair, except push tokens

No server-side record was ever attributed to the wrong account — the leak was
entirely on the device. The one exception is the push token overlap from cause 4,
which is repairable **without guessing**, because the rule is not "who owned
this" but "only one device may hold a given token, and it is the one that
registered it last":

```sql
-- Dry run first: which tokens are held by more than one device?
SELECT push_token, count(*) AS holders, array_agg(account_id) AS accounts
  FROM devices
 WHERE push_token IS NOT NULL AND revoked_at IS NULL
 GROUP BY push_token HAVING count(*) > 1;

-- The repair: keep the most recent registration of each token, clear the rest.
-- Ordered by created_at, so "most recent" is a fact in the row rather than a
-- judgement about who deserves it.
UPDATE devices d
   SET push_provider = NULL, push_token = NULL, voip_token = NULL
 WHERE d.push_token IS NOT NULL
   AND EXISTS (
     SELECT 1 FROM devices newer
      WHERE newer.push_token = d.push_token
        AND newer.id <> d.id
        AND newer.created_at > d.created_at
   );
```

Clearing a token is not destructive: the affected device falls back to the
socket and re-registers on its next sign-in or refresh.

**Run it on a backup first, and keep the dry-run output** — it is the record of
what was changed and for whom.

### On a device: offer the remedy, do not force it

A phone that hit this bug already shows the previous account's history under the
new account. Updating stops it happening again; it cannot un-see what has
already been shown, and **there is no way to tell an unstamped archive that is
legitimately mine from one that is not** — which is exactly why the code does
not try.

So the remedy is the user's to apply, and it is one action:

> **Sign out once after updating.** Sign-out now clears the archive, the
> keystore and the crypto store completely, so the next sign-in starts clean.

Do not ship a forced wipe on upgrade. Every device that only ever had one
account — which is nearly all of them — would lose its history for a leak that
never happened to it.

## Residual risk, stated plainly

An archive written by a build older than this change carries no owner stamp. On
a device that was in the bugged state at the moment of upgrade, the first launch
will accept that archive and the first save will stamp it under whoever is
signed in. The leak is not new — it had already happened — but the upgrade makes
it permanent on that device unless the user signs out once.

This is a deliberate trade: the alternative is deleting the history of every
single-account device to clean up the few. It is called out here rather than
left for somebody to find.

## The verification that was actually run

Client, `app/test/account_separation_test.dart` — all five reproduce the bug
against the pre-fix code:

1. A signs up, sets a picture and contacts; A signs out; B signs up. B's
   picture, contacts and conversations are empty. *(Before: B wore A's picture.)*
2. A's and B's identity fingerprints differ across the sign-out.
   *(Before: identical.)*
3. A request issued by A and answered after B signs in is refused, and B's
   screen is untouched.
4. A history left behind by a half-finished sign-out is not adopted by B.
5. An archive from before owners were stamped still opens, so nobody loses a
   history to this fix.

Server, `server/test/account_isolation.test.ts` — nine tests, B's session
against A's identifiers, covering profile, backup, media, avatar adoption,
private channels, public-channel visibility, envelopes, device revocation and
the push token.

Both regressions that had a pre-existing fix — the push token, and the
`RETURNING` bug found alongside it — were run against the old code first and
observed to fail.

**Not tested on a device.** There is no simulator here. The whole flow is
exercised by the tests above against real crypto, a real Postgres and the real
sign-out path, but nobody has watched two accounts on a phone.
