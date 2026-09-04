# Privio client

The Flutter client, for Android and iOS. One source tree, four editions.

## Editions

| Edition | Channel | Paid for by | Proprietary code |
| --- | --- | --- | --- |
| `libre` | F-Droid | A license key from getprivio.com | None |
| `direct` | APK from getprivio.com | A license key from getprivio.com | None |
| `play` | Google Play | Play Billing | Allowed |
| `appstore` | App Store | App Store purchase | Allowed |

The split is enforced by the build, not by discipline: `libre` and `play` are
Gradle product flavours, and a dependency added for push, billing or maps goes
in `playImplementation` where the Libre build cannot reach it. The Dart side
learns which build it is in from `--dart-define=PRIVIO_EDITION`, and reports it
on the about screen.

Nothing else differs. Same protocol, same crypto, same screens.

## Running it

```bash
flutter pub get

# Flavours are declared, so `flutter run` needs one.
flutter run --flavor libre --dart-define=PRIVIO_EDITION=libre \
  --dart-define=PRIVIO_API_URL=http://10.0.2.2:8080
```

`PRIVIO_API_URL` defaults to `http://localhost:8080`, which is the right
address on a desktop and the wrong one inside an Android emulator — use
`10.0.2.2` there. Point it at your own server and nothing else changes.

## Building

```bash
# F-Droid / direct APK
flutter build apk --release --flavor libre \
  --dart-define=PRIVIO_EDITION=libre \
  --dart-define=PRIVIO_API_URL=https://api.getprivio.com

# Google Play
flutter build appbundle --release --flavor play \
  --dart-define=PRIVIO_EDITION=play \
  --dart-define=PRIVIO_API_URL=https://api.getprivio.com

# iOS
flutter build ipa --release \
  --dart-define=PRIVIO_EDITION=appstore \
  --dart-define=PRIVIO_API_URL=https://api.getprivio.com
```

Release builds are currently signed with the debug key — see the TODO in
`android/app/build.gradle.kts`. F-Droid signs its own builds regardless, which
is why an APK from F-Droid and one built here cannot update each other.

The Libre build is meant to be reproducible from source: see
[`../docs/privio-libre.md`](../docs/privio-libre.md).

## The Android build is blocked

No Android APK can be produced today, in any environment. Found by dispatching
the release workflow by hand, which is the only Android compiler this project
has; the iOS build passes, and so do the analyzer and the tests.

The chain, in the order it has to be undone:

1. Flutter has moved to built-in Kotlin. `file_picker` 11 still applies its own
   Kotlin Gradle Plugin, so its Android classes are never produced, and the
   registrant Flutter generates fails to compile against them:
   `cannot find symbol: class FilePickerPlugin`.
2. `file_picker` 12 fixes that, and raises the floor to Flutter >=3.38 and
   Dart >=3.10 — which is honest, since nothing older can build anyway.
3. But 12 will not resolve alongside `flutter_secure_storage` 9. Pub says to go
   to `flutter_secure_storage` 11.

Step 3 is why this is not a one-line change. That package is the keystore:
the session token, the archive key, the recovery key and a held licence key all
live in it. Its Android implementation changed substantially in version 10, so
**data written by version 9 may not be readable afterwards** — on this app that
means someone's history and their backup, not a preference.

So it wants doing deliberately, on a real device, with the upgrade path tested
against a keystore written by the current release, and a migration if there is
none. It is not something to bump and hope, and it is not something CI can
answer: green here would only prove it compiles.

## Tests

```bash
flutter analyze
flutter test
```

The suite runs without a device, an emulator or a server. Hardware sits behind
interfaces — `VoiceRecorder`, `SecureStore`, `CryptoStorage` — and the fakes in
`test/support/` drive the same state machines the real ones do. Keep it that
way: a test that needs a phone is a test nobody runs.

## Layout

```
lib/core/      App state, API client, editions, licensing
lib/crypto/    Signal sessions, sealed storage, padding
lib/data/      Local history, outbox, archive, backups
lib/media/     Attachments, avatars, voice, metadata scrubbing
lib/models/    Plain data
lib/screens/   One file per screen
lib/services/  Messaging, channels, backup, realtime socket
lib/theme/     Colours, spacing, typography
lib/widgets/   Shared pieces
```
