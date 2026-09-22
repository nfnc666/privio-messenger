# The operator API, and what it deliberately cannot do

The admin panel lives in its own repository and talks to this server over the
routes in `server/src/routes/admin.ts`. This document is the argument behind
those routes: what an operator can see, what they cannot, and why the line is
where it is.

It is written down because the pressure on this boundary is constant and always
reasonable-sounding. Somebody will eventually need to know what is in a reported
channel, or to log in as a customer to reproduce a bug, or to delete a message
that should not have been sent. Each of those is a fair thing to want and each
of them requires the server to be able to read what it says it cannot.

## The rule

**The server never holds a key that can open a message — so neither does an
operator.**

There is no route in the operator API that reads `envelopes.content`,
`channel_posts.content`, `backups`, `media_objects`, a group's
`encrypted_metadata`, or a private channel's `encrypted_metadata`. Not because
the ciphertext would be useless, though it would be, but so that the absence is
visible when reading the file rather than argued about later.

## What an operator can see

Routing metadata — what the server already had to know in order to forward
sealed bytes:

- A username, display name, when the account was created and last seen.
- Its devices: name, platform, when each was added and last checked in, whether
  a push route is registered. Never the push token itself, which is an address
  this server sends to.
- Whether the account holds a licence, and whether it has two-factor on.
- Aggregate counts: accounts, devices, channels, queued envelopes, live
  sessions.

Plus the plaintext a **public** channel publishes on purpose, so that it can be
searched for: its handle, title, description and category. `004_channels.sql`
sets out why those three columns are readable and why a private channel's are
not.

## What an operator cannot do

| | |
| --- | --- |
| **Read content** | No message, post, backup or attachment. The keys are not here. |
| **Act as an account** | No impersonation, no session minting, no password reset for anybody but themselves. An operator who could sign in as somebody could read everything that person's device can. |
| **Delete an account** | Erasure is the account holder's own action, from their own device, at `DELETE /v1/accounts/me`. |
| **See a private channel** | Not its title, not its members, not its posts. A report on one shows an id, a member count and the reasons given — and nothing else. |
| **Retrieve a licence key** | A key is shown once at issue. Only a keyed hash survives, so the panel can say a licence exists and cannot say what to type into an app. |

## Operator credentials

An operator login is a row in `admin_users`, not a flag on an account. A staff
member's own Privio account and their operator login are different credentials,
revoked separately; compromising one does not hand over the other.

- **Password**: Argon2id, the same parameters an account password gets.
- **Second factor**: TOTP, sealed under `TOTP_SECRET_KEY` exactly as an
  account's is. Enforced per row rather than globally, so the first operator can
  be created and then immediately enrol — which is impossible if the login
  refuses everyone without a factor they have no way to set up yet.
- **Sessions**: `ADMIN_SESSION_TTL_MINUTES`, twelve hours by default, against a
  year for an account session. A phone in a pocket staying signed in is the
  feature; a browser tab on a shared workstation staying signed in is the
  incident.

A wrong username, a wrong password and a disabled operator are all answered
identically, so a list of names cannot be tested against the login. A failed
attempt is recorded with the username as typed and nothing else — in particular
no "did that name exist" flag, which would put the enumeration oracle back in
the audit log after carefully keeping it out of the response.

### Roles

Capabilities rather than a rank, because the roles are not a straight line:

| Role | read | licenses | moderate | operators |
| --- | :---: | :---: | :---: | :---: |
| `owner` | ✓ | ✓ | ✓ | ✓ |
| `admin` | ✓ | ✓ | ✓ | |
| `support` | ✓ | ✓ | | |
| `viewer` | ✓ | | | |

Support answers billing questions and must not suspend a channel; an admin
moderates and must not create the operator who moderates them. A ranked check
would have to decide which of those two is "higher" and would be wrong for one
of them.

Disabling an operator, or changing their role, ends their live sessions. A role
carried inside an already-issued session would otherwise outlive the change by
up to the session lifetime, which is exactly the window somebody being demoted
would use.

## The first operator

There is no sign-up endpoint and there will not be one: a route that mints the
first operator mints it for whoever reaches it first, and a server that has just
been deployed and not yet configured is exactly where that race is lost.

```bash
npm --workspace server run create-admin -- --username ada --role owner
```

It migrates first (so it works on a database that has never been migrated),
refuses to run if an enabled operator already exists unless `--force`, and
prints a generated password once. Shell access to the machine is the credential
this trades on — which is the same credential that could read the database
anyway.

## Suspending a channel

The only moderation action the server can take honestly.

A suspended public channel stops being listed by `/v1/channels/discover`, stops
resolving at `/v1/channels/by-handle/:handle`, stops being reachable by invite
code, refuses new members at `/v1/channels/:id/join`, and its public invite page
says so. Those five are what a suspension *is*: the ways a stranger reaches a
channel they are not already in.

What it does **not** do:

- **Delete posts.** The server cannot read them to know what it would be
  deleting.
- **Remove members.** Their devices hold the channel key and the server never
  did. There is no mechanism by which they could lose access, and claiming
  otherwise would be a lie told in a confirmation dialog.

A **private** channel cannot be suspended at all — `400 channel_not_public`. It
was never discoverable, so suspending it would remove nothing while looking like
an action was taken.

Reports are reviewed per channel rather than per report: ten reports are one
thing to look at, and leaving nine open after acting on the tenth would show the
channel back in the queue for a decision already made. Clearing a channel does
not delete the reports — somebody did report it, and the next operator deserves
to know it was judged fine before.

## Reports about people

`GET /v1/admin/reports/accounts`, grouped per account, with counts per reason —
the same shape as the channel queue and for the same reason: ten reports are one
thing to look at.

It is **read-only, and thinner than the channel queue on purpose**. A channel
has a public title and description an operator can read before deciding. An
account has a username and nothing else the server may look at, and there is no
message history to quote because the server never held one in the clear. What
this answers is how many people reported somebody and on what grounds. That is a
signal, not evidence, and it is worth showing only as long as nobody mistakes it
for the second thing.

There is deliberately **no suspend to go with it**. Suspending a channel removes
things the server controls — a listing, a handle, an invite code. What
suspending a *person* would mean for conversations the server cannot read is a
design decision, not a query, and shipping a button before making it would be
the kind of moderation that looks like an action and is not one.

See [`contact-profiles.md`](contact-profiles.md) for what a reporter is told
before they pick a reason.

## The audit log

`admin_audit_log` is append-only. There is no `UPDATE` or `DELETE` path to it
anywhere in the server and the panel offers no way to clear it: a log an operator
can edit records nothing about the only party it exists to record.

`services/admin_audit.ts` is the single writer, which is what gives the rule one
place to be enforced: **nothing written to the log may come from user content.**
`detail` takes scalars — ids, enum values from a fixed set, counts, field names —
capped at 128 characters, with arrays reduced to their length and nested objects
dropped rather than stringified. A dropped field is a gap somebody notices; a
stringified one is a leak nobody does.

`actor_username` duplicates what `admin_user_id` points at, on purpose: an
operator can be renamed, and the log has to read as what was true when the action
happened.

## The panel's own architecture

Stated here because it is a security property of this API, not only of that
repository: the panel holds the operator token in an httpOnly cookie and calls
these routes from its own Node process. The browser never holds the token.

That is why no browser origin is added to `CORS_ORIGINS` for the panel. An
operator token is the one credential on a Privio deployment that sees across
accounts, and a single XSS hole in a panel that kept it somewhere a script could
read would hand it to an attacker to use directly, from anywhere, for as long as
the session lasted.
