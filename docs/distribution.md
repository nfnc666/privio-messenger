# Distribution, licensing and the client/server split

Four ways to get Privio, one source tree, and a proposed split into a public
client and a private server. This document is the licence and rights review
that has to come first, the technical state of the four distributions, and a
migration plan that changes nothing until somebody with the authority to decide
has decided.

**Nothing here is legal advice and nothing here is a legal clearance.** The
findings are a reading of the licence files actually present in this repository
and its dependency tree. They are the basis for a decision, not the decision.

## 1. The four distributions

| | App Store | Play Store | Website APK | F-Droid |
| --- | --- | --- | --- | --- |
| Name | Privio | Privio | Privio | **Privio Libre** |
| Edition id | `appstore` | `play` | `direct` | `libre` |
| Android flavour | — | `play` | `direct` | `libre` |
| Paid for by | Apple | Google Play | Licence key | Licence key |
| Wake-up | APNs | FCM | UnifiedPush | UnifiedPush |
| Proprietary code | allowed | allowed | **none** | **none** |
| Updates | App Store | Play | Signed APK from the site | F-Droid |

The encryption core, the chat, group and channel features are the same in all
four. Libre is not a reduced build and is not given weaker security; it is the
same app without the stores' plumbing.

`direct` and `libre` contain the same dependencies and compile the same Kotlin.
They are separate products because the name, the signing key and the update path
differ — and because an APK that says "Privio Libre" on the home screen while
its Dart side believes it is the website build is a bug users cannot see.

## 2. Licence and rights review

### What the project is under now

`AGPL-3.0-only`, client and server both, declared in `LICENSE`, in
`package.json`, in `app/pubspec.yaml`'s edition constants and in the README.

### Third-party dependencies

Server (`server/package.json`), all permissive:

| Package | Licence |
| --- | --- |
| fastify, fastify-plugin, @fastify/cors, @fastify/rate-limit, @fastify/websocket | MIT |
| pg, zod, ioredis, otplib, @node-rs/argon2 | MIT |
| tsx, @types/node, @types/pg | MIT |
| typescript | Apache-2.0 |

Client (`app/pubspec.yaml`), direct dependencies:

| Package | Licence | Note |
| --- | --- | --- |
| **libsignal_protocol_dart** | **GPL-3.0** | The ratchet. See the blocker below. |
| cryptography | Apache-2.0 | AES-GCM, Argon2id |
| flutter_secure_storage, qr_flutter, scrollable_positioned_list, http, web_socket_channel, path_provider | BSD-3-Clause | |
| file_picker, image, archive, just_audio, flutter_webrtc | MIT | |
| record | BSD-3-Clause | |
| org.unifiedpush.android:connector (Android, `libre`/`direct`) | Apache-2.0 | Maven Central |
| com.google.firebase:firebase-messaging (Android, `play` only) | Proprietary | Never in a free build |

### Blocker A — the client cannot be relicensed away from copyleft

`libsignal_protocol_dart` is **GPL-3.0**, not the permissive licence its
neighbours use. GPL-3.0 is copyleft: anything distributed with it has to be
distributed under GPL-3.0 or a compatible licence. AGPL-3.0 is compatible, so
the project as it stands is fine — but it means the public client **cannot** be
moved to MIT, BSD or a proprietary licence while that dependency is in it.

*What is needed to resolve it:* a decision to keep the client copyleft (no work
required, and the natural choice for a client whose auditability is the point),
or a replacement Signal implementation under a permissive licence, which is a
substantial piece of cryptographic engineering and is not something to take on
casually.

### Blocker B — GPL and the Apple App Store

This is the one that touches a **binding** distribution. Apple's App Store terms
impose usage rules on the person who downloads a binary — device limits, and no
right to redistribute — and GPL-3.0 §6 and its anti-tivoisation terms are
generally read as incompatible with that. Apps have been removed from the App
Store over exactly this; the FSF's position and the VLC case are the usual
references.

Privio's client links a GPL-3.0 library and is itself AGPL-3.0.

*What is needed:* a written position from someone qualified, on whether Privio
can ship to the App Store as it is. The realistic options are (a) obtain a
licence exception from the copyright holder of `libsignal_protocol_dart`
(MixinNetwork) for App Store distribution, (b) replace the library, or (c) do
not ship to the App Store. **Until that is answered, the `appstore`
distribution is legally unconfirmed**, however well it builds.

### Blocker C — the server cannot simply become proprietary

The server is AGPL-3.0 today. Two separate consequences:

1. **Section 13.** Anyone who interacts with a modified AGPL server over a
   network is entitled to its source. Moving the repository to private does not
   remove that: the obligation attaches to the users of the running service, not
   to who can see a git repository. Running our own server privately while it is
   AGPL means our users can ask for the source.
2. **Other authors.** Every contributor holds copyright in what they wrote.
   Relicensing needs the agreement of all of them, or a contributor licence
   agreement they signed at the time. This repository has no CLA and no
   `CONTRIBUTORS` file.

*What is needed, concretely:*

* A list of everyone who has contributed to `server/`, from `git log`, with the
  commits attributable to each.
* From each: either a signed relicensing agreement, or removal and reimplement-
  ation of their contribution.
* A decision on whether *future* contributions require a CLA or DCO.
* If any contributor cannot be reached or declines, the server stays AGPL, and
  the "private server" plan means a private *repository* running AGPL code, with
  section 13 still owed to its users.

**The legal conversion is blocked** until those exist. Nothing in this branch
removes a licence notice, changes `LICENSE`, or declares any file proprietary,
and nothing should until the above is answered.

### What is safe to do in the meantime

Everything technical: making the client independently buildable, documenting the
API, correcting the editions, and preparing the build and update paths. All of
that is useful whether the split happens or not, and none of it changes anyone's
rights. That is what this branch does.

## 3. The split, when it is allowed

**Public** — the whole Flutter client: `app/` including Android and iOS,
cryptography, tests, build instructions; `docs/` including
[`server-api.md`](server-api.md) and the security model.

**Private, subject to the rights review** — `server/`, licence issuing and
verification, internal administration, deployment.

The client must build with no access to the private repository. That is
enforced by a test (`app/test/client_independence_test.dart`): no client source
may import from the server tree, no `path:` dependency may reach outside `app/`,
and the API document must exist and cover the routes the app depends on. The
client's own suite runs against fakes, so a contributor never needs a server.

### Migration plan (non-destructive; nothing below has been done)

1. Answer the rights review above. Until then, stop here.
2. Keep this repository as the public one. It already contains the client and
   the documentation, and its history is the project's history — moving the
   client to a new repository would throw that away.
3. Create a **new** private repository for the server. Copy `server/` into it
   with `git log --follow` history preserved via `git subtree split`, or accept
   a fresh history and keep this one as the archive.
4. Only once the private repository is running: remove `server/` from the public
   one, in an ordinary commit that anyone can see. **Do not rewrite history** —
   the AGPL server code has been published, that cannot be unpublished, and
   pretending otherwise by force-pushing is both futile and a red flag.
5. Leave the AGPL notices in the copied server code unless and until step 1 says
   otherwise.

Repository visibility is not changed by this branch and must not be changed by a
script.

## 4. Building each distribution

```bash
cd app

# F-Droid
flutter build apk --release --flavor libre  --dart-define=PRIVIO_EDITION=libre

# Website APK
flutter build apk --release --flavor direct --dart-define=PRIVIO_EDITION=direct

# Google Play
flutter build appbundle --release --flavor play --dart-define=PRIVIO_EDITION=play

# App Store
flutter build ipa --release --dart-define=PRIVIO_EDITION=appstore
```

The flavour and the edition must match. Gradle refuses a build where they do
not, and a **release** build refuses an edition it does not recognise rather
than falling back to Libre — which it used to do, quietly turning a mistyped
build script into a store binary that claimed to be free software.

`PRIVIO_API_URL` selects the server and defaults to `http://localhost:8080`.

## 5. Signing, updates and identifiers

**Not changed by this branch, and not to be changed without a decision.** The
applicationId is shared by all Android flavours today. Two consequences that
have to be decided before the first release, not after:

* **F-Droid signs its own builds.** An APK from F-Droid and one from our website
  have the same package name and different signatures, so **neither can update
  the other**. A user moving between the two must uninstall — losing local data
  unless they restore from a backup first. This is inherent to the two
  distribution paths, not a bug, and it needs to be said plainly on the download
  page.
* **Changing an applicationId later is worse than choosing it now.** A rename
  after release is a new app: no updates, no reviews, no ratings.

The `direct` APK needs a **signature-checked** update path: the app learns a new
version is available, the user chooses to install it, and Android's installer
verifies the signature — as it does for any APK signed with the same key. No
silent installation, and no download over anything but HTTPS with the signature
checked before the installer is offered the file. Not implemented yet.

## 6. Build provenance

Every artifact should be traceable to the commit and the configuration that
produced it. `app/lib/core/build_info.dart` carries the version, the commit and
the edition, injected at build time; `tools/build-info.sh` prints the
`--dart-define` arguments for a build.

Reproducibility is a claim to be earned: an Android build is described as
reproducible only after two independent builds of the same commit have been
compared and matched. That comparison has not been run — see the blockers at the
end. Until it has, this document says "prepared for", not "reproducible".

**Credentials, production configuration and signing keys are never in this
repository and never in an artifact built from it.** `google-services.json` is
absent by design and the Gradle config only applies the Google Services plugin
when it is present.

## 7. State of it

| | Implemented | Automated test | Compiled | On a device |
| --- | --- | --- | --- | --- |
| Edition matrix, names, push providers | yes | yes | — | no |
| Release refuses an unknown edition | yes | yes | no | no |
| Flavour/edition mismatch refused | yes | rules tested in Dart | **no** | no |
| `direct` Android flavour | yes | rules tested in Dart | **no** | no |
| iOS built as `appstore` | yes (CI) | — | **no** | no |
| Licence key: invalid, reused, revoked | yes | yes | — | no |
| Client entitlement cannot be self-granted | yes | yes | — | no |
| Device change keeps the entitlement | yes | yes | — | no |
| Store purchase verification | **no** | asserts its absence | — | no |
| Client builds without the server | yes | yes | — | — |
| Signed update path for the `direct` APK | **no** | — | — | — |
| Reproducible Android build | prepared | — | **no** | no |

### Blockers

* **Rights review** (section 2). Blocks the licence change and the App Store
  distribution. Needs decisions and documents, not code.
* ~~**No CI runners.**~~ Resolved on 2026-09-07 by making the repository public:
  public repositories get Actions minutes free, macOS included. The build jobs
  run again — and the first time they did, they found the Android build broken
  since #64 and the iOS build unable to get past its entitlements file. Neither
  was visible while nothing could run.
* **No Android SDK and no macOS in this environment**, so nothing in the
  "Compiled" column can be filled in here. `dl.google.com` is blocked by the
  network policy.
* **No store accounts, certificates or service-account keys**, so purchase
  verification cannot be implemented against anything real. Writing it against a
  guess would be worse than leaving it out.
