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

### Continuous integration is currently not running

Since **2026-09-05** every workflow run has failed in a few seconds without
executing a single step. This is not the code, and it is worth knowing before
spending an afternoon on it:

* The last green run was CI #80 (2026-09-05 00:57 UTC). #81, twelve minutes
  later, failed in 3 seconds, and all 60 runs since have failed the same way —
  a median of 3 seconds, the longest 39.
* The workflow files did not change at that boundary. The last edit to
  `.github/workflows/` before it was 2026-09-04 15:15, and 29 runs passed after
  that edit.
* The jobs are never assigned a runner: the API reports `runner_id: 0` and an
  empty `runner_name`, there are no step records, no annotations, and
  downloading the logs returns 404 — there are no logs, because nothing ran.

A failure that begins on a date, affects every workflow at once, leaves no logs
and correlates with nothing in the repository is an account-level one: exhausted
Actions minutes, a spending limit, or Actions disabled for the account. **It can
only be fixed by the repository owner**, in GitHub's billing settings — not by
anything in this repository, and not by weakening a check to make it green.

This repository is **private**, which is what makes minutes finite: they are
billed against the account's quota rather than free as they would be on a public
repository. Keep that in mind before adding a job, and especially before adding
a macOS one — **macOS bills at ten times the Linux rate**, so the signed iOS
build in `ios-testflight.yml` costs 200–350 minutes of quota per run. That is
why it is `workflow_dispatch` only, and why its companion,
`ios-signing-setup.yml`, runs on Linux: making a certificate is a request and an
answer, not a compile, so it has no business on a macOS runner.

Until it is fixed, the checks on a pull request are red for that reason and the
suites have to be run locally, with the results and the commit written into the
pull request. Say which they are; a red tick that means "no runner" and a red
tick that means "the tests failed" must not be allowed to look the same.

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
