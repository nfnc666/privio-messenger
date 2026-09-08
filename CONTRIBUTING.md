# Contributing to Privio

Privio is AGPL-3.0. Everything in this repository — the Flutter client and the
Node server — is source you are free to read, build, change and redistribute
under those terms. Contributions are welcome on the same footing.

## Before you write code

Open an issue first for anything larger than a small fix. It is cheaper to
disagree about an approach in a paragraph than in a thousand-line diff, and
some things that look like bugs are deliberate trades documented in
[`docs/`](docs/).

Two areas need more care than the rest:

* **Cryptography** — `app/lib/crypto/`, `app/lib/media/attachment.dart` and
  anything that decides what leaves the device. A change here needs a written
  rationale, not just a passing test. If it makes the server able to learn
  something it could not learn before, it will be rejected however elegant it
  is.
* **What the server stores** — `server/migrations/` and
  `server/src/services/`. A new column that holds plaintext, or metadata that
  outlives its purpose, has to justify itself against
  [`docs/security-model.md`](docs/security-model.md).

Never open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).

## Working on the code

```
server/   Fastify + PostgreSQL relay. npm test needs a database.
app/      Flutter client. flutter test needs no device.
docs/     Architecture, security model, licensing, the Libre edition.
design/   Brand assets.
```

Setup and build commands live in [`app/README.md`](app/README.md) for the
client and in the [root README](README.md) for the server.

Before you push:

```bash
npm --workspace server run typecheck
npm --workspace server test          # needs TEST_DATABASE_URL
cd app && flutter analyze && flutter test
```

If migration fails with *"Database is ahead of this checkout: it has applied
`014_channel_key_epochs.sql`"*, that file was renamed to `015_...` when it
collided with another branch's 014. The schema it created is already in your
database and nothing needs re-applying; only the ledger row is stale. Correct it
rather than dropping the database:

```sql
UPDATE schema_migrations SET name = '015_channel_key_epochs.sql'
WHERE name = '014_channel_key_epochs.sql';
```

Written down because renaming an applied migration is a thing that should not
happen quietly, and this one did.

If the server suite fails with something like `column "alias" does not exist`,
read the error above it: a test database that carried a migration from a branch
you have since left is ahead of your checkout, and `migrate()` now says so by
name instead of letting it look like broken code. `dropdb privio_test &&
createdb privio_test` is the fix. CI never hits this — it gets an empty database
every run — which is exactly why it costs a developer an hour and not a build.

### The outage that hid two broken builds

Between **2026-09-05 and 2026-09-07** every workflow run failed within seconds
without executing a step. It was never the code: the jobs were not assigned a
runner (`runner_id: 0`, no steps, no annotations, 404 for the logs), the
workflow files had not changed at that boundary, and the last green run before
it — CI #80 — was followed by 60 identical failures. That is the signature of an
account-level cause, and on a private repository it usually means Actions
minutes.

It was resolved by making the repository **public**. Public repositories get
Actions minutes free, macOS runners included, and the first run afterwards
(CI #147) got a real runner and went green on the server job in 55 seconds.

Two things are worth keeping from it.

**A check nobody can run is not a check.** `build-mobile.yml` was added during
the outage, so its jobs had never once executed. The first minute they ran they
found an Android build that had been broken since #64 — `java.util.Base64` in a
Gradle Kotlin script, where `java` resolves to the Java plugin's extension and
not to the package — and an iOS build that could not proceed past an
entitlements file without an Apple team. Both were merged with a green-looking
pull request and a paragraph explaining that the red ticks meant "no runner".
That paragraph was true and it was not enough.

**Say which red is which.** A red tick that means "no runner" and a red tick
that means "the tests failed" must not be allowed to look the same. When CI
cannot run, run the suites locally and put the results and the commit in the
pull request — and say plainly that no CI run exists.

### Minutes, and where they go

Public repositories do not meter Actions minutes, so the arithmetic below is no
longer a budget — but it is still the reason the expensive jobs are shaped the
way they are, and it comes back the moment the repository is private again.
**macOS bills at ten times the Linux rate**, which is why the signed iOS build
in `ios-testflight.yml` (20–35 minutes, so 200–350 minutes of quota) is
`workflow_dispatch` only, and why its companion `ios-signing-setup.yml` runs on
Linux: making a certificate is a request and an answer, not a compile, and has
no business on a macOS runner.

### What being public changes

* **Workflow logs and build artifacts are readable by anyone.** That includes
  the signed `.ipa` the iOS build uploads. Nothing in these workflows prints a
  secret — there are tests asserting it — but the bar is now "a stranger reads
  this", not "a colleague does".
* **Secrets are still not exposed.** A pull request from a fork gets none of
  them, and the two workflows that use them are `workflow_dispatch` only, which
  needs write access to start.
* **A fork's first pull request waits for approval** before its workflows run.
  That is a repository setting, and it should stay on.

A change to the client that touches sending, receiving or key handling should
come with a test. The existing suite runs without a device or a server on
purpose — keep it that way, and put anything that genuinely needs hardware
behind an interface, the way `VoiceRecorder` is.

## Pull requests

1. Fork, and branch from `main`.
2. Keep the change focused. Unrelated refactors in the same diff make review
   slower and bisects worse.
3. Say what you changed and why. Link the issue it addresses.
4. Run the linters and tests above. A red CI run is not a review request.

Commit messages are written in the imperative and describe the change, not the
file list: "Refuse to relay for unlicensed accounts", not "update licenses.ts".

## Documentation and translations

A correction to `docs/` is as welcome as code; if something there is wrong or
out of date, that is a bug and it should be filed as one.

Interface strings live in the client. To add a language, copy the base English
strings, translate the values and leave placeholders untouched. Keep security
wording exact — "end-to-end encrypted" means something specific and must not be
softened in translation.

## Licensing of contributions

By opening a pull request you agree that your contribution is licensed under
the GNU Affero General Public License, version 3, the same as the rest of the
project. There is no CLA and no copyright assignment: you keep your copyright.

## Conduct

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) applies to every space this project
uses.
