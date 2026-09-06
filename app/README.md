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

## The Android build

It could not be produced at all until now, and the chain was:

1. Flutter moved to built-in Kotlin. `file_picker` 11 still applied its own
   Kotlin Gradle Plugin, so its Android classes were never produced and the
   registrant Flutter generates failed to compile against them:
   `cannot find symbol: class FilePickerPlugin`.
2. `file_picker` 12 fixes that.
3. But 12 would not resolve alongside `flutter_secure_storage` 9, and pub's
   advice was to move that to 11 — the package holding the session token, the
   archive key and the recovery key, whose Android implementation changed in
   version 10 such that data written by 9 may not be readable afterwards.

Step 3 turned out not to be about the keystore at all. The conflict is between
`windows_file_picker` (wants `win32` ^6) and `flutter_secure_storage_windows`
3.1.2 (pins `win32` ^5) — two Windows packages, in an app with no `windows/`
directory, neither of which is ever compiled. Pub resolves every platform's
plugins regardless, so a Windows version range was refusing an Android fix.

So `pubspec.yaml` carries one `dependency_overrides` entry, `win32: ^6.3.0`,
and `flutter_secure_storage` stays at 9. No keystore migration, no history to
lose. `file_picker` 12 also replaces `FilePickerResult` with a plain
`PlatformFile` and moves reading off the picker (`readAsBytes()`), which the
two call sites — the avatar picker and the chat attachment button — now use.

**What that is verified to mean, and what it is not.** Verified: the
dependencies resolve, `flutter analyze` is clean, and the whole test suite
passes on Flutter 3.47.1. Not verified here: that `flutter build apk` succeeds.
This environment has no Android SDK and cannot install one — `dl.google.com` is
refused by its network policy, which also rules out Gradle reaching AGP — so
the compile has to be proven by CI or by a machine with an SDK. Until one of
those runs green, treat the Android build as *unblocked in principle, unproven
in fact*, and treat anything about how it behaves on a phone as untested.

## Tests

```bash
flutter analyze   # No issues found!
flutter test      # All tests passed!  (551 tests, ~45 s)
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
