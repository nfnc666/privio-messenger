# Privio Libre

Privio Libre is the free-software build of the Privio client: the same app as
everywhere else, with nothing in it that cannot be built from source. It is
what F-Droid ships, and what the direct APK on privio.com is cut from.

Its public home is
[privio-libre-open-source-fdroid](https://github.com/nfnc666/privio-libre-open-source-fdroid),
which carries the client, the F-Droid recipe and the store listing. This
repository stays the place where the client and the server are developed
together; the Libre repository is what F-Droid builds from.

## What "libre" means here, exactly

* **No proprietary dependency.** No Google Play services, no Firebase, no
  analytics SDK, no crash reporter. Enforced by the flavour split in
  `app/android/app/build.gradle.kts`: anything Google-shaped goes in
  `playImplementation`, which the Libre variant does not compile.
* **No push service.** [`PrivioEdition.pushProvider`](../app/lib/core/edition.dart)
  is null for Libre. That is a real trade, not an omission: FCM would tell
  Google when a device is being messaged, and it would be a proprietary blob
  in the APK. Libre receives over its own socket while it is running instead.
* **No dependency-metadata blob.** `dependenciesInfo` is off, because the
  block Gradle embeds is signed by Google and cannot be reproduced from source.
* **No tracking of any kind.** True in every edition; here it is checkable.

The app says which build it is on the about screen, along with the licence and
the source URL.

## AGPL-3.0

Everything in this repository is under the GNU Affero General Public License,
version 3 — the client and the server both. See [`../LICENSE`](../LICENSE).

Two consequences worth stating plainly:

* You may run, study, change and redistribute Privio. If you distribute a
  changed client, its source has to be available under the same licence.
* If you run a modified **server** for other people, section 13 applies: those
  users are entitled to your modified source. That is the whole reason for
  choosing AGPL over GPL. A private messenger whose server can be forked into a
  closed one would be missing the point.

The licence covers the code. It does not cover the Privio name or logo in
`design/`, and it does not make the hosted service free of charge.

## Licensing is not the licence

Two different things share a word:

| | |
| --- | --- |
| **The licence** | AGPL-3.0. What you may do with the code. Never expires, cannot be revoked. |
| **A license key** | What pays for the hosted relay. Bought on privio.com, redeemed once, bound to one account. |

The key does not unlock the app. You already have all of the app, and can
build it yourself with the activation screen deleted — which is exactly why
the gate lives on the server and not in the client. See
[`licensing.md`](licensing.md#enforcement).

Self-hosting needs no key at all: a server with `LICENSE_REQUIRED=false`
answers `required: false`, and the client then never asks for one.

## Building it yourself

```bash
cd app
flutter pub get
flutter build apk --release --flavor libre \
  --dart-define=PRIVIO_EDITION=libre \
  --dart-define=PRIVIO_API_URL=https://api.privio.com
```

Full instructions, including the store builds, are in
[`../app/README.md`](../app/README.md).

## Reproducible builds

The goal is that the same source and the same toolchain produce a
byte-identical APK, so that what F-Droid ships can be checked against what this
repository says. What is in place today:

* The dependency-metadata blob is off, so no unreproducible Google signature
  is embedded.
* Dart and Gradle dependencies are pinned — `pubspec.lock` is committed, and
  the Gradle wrapper version is fixed in the repository.
* Nothing is generated at build time from the clock, the hostname or the build
  path.

What is not verified yet: no published Libre APK has been rebuilt and compared
byte for byte, because none has been published. Until that has actually been
done, this section describes an intention, not a result — and it will say so
rather than claim otherwise. The check, once there is a release to check:

```bash
# Rebuild from the tag, then compare against the published APK.
apksigner verify --print-certs privio-libre.apk
diffoscope privio-libre-fdroid.apk privio-libre-local.apk
```

Signatures will differ — F-Droid signs with its own key. Everything else
should not.

## Reporting a problem with the Libre build

Anything that makes the Libre build differ from what this document says — a
proprietary dependency that crept in, a network call to something that is not
your server, a build that will not reproduce — is a bug worth filing, and a
security report if it leaks anything. [`../SECURITY.md`](../SECURITY.md) says
where those go.
