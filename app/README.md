# Privio client

The Flutter client, for Android and iOS. One source tree, four editions.

## Editions

| Edition | Channel | Paid for by | Proprietary code |
| --- | --- | --- | --- |
| `libre` | F-Droid | A license key from privio.com | None |
| `direct` | APK from privio.com | A license key from privio.com | None |
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
