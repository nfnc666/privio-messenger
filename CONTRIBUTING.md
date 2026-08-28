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
