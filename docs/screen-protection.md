# Screen protection

Settings → Privacy & Security → **Screen protection**. One switch, per account,
and two genuinely different features behind it — which is why there are two
explanations under it rather than one.

The short version:

| | Android | iOS |
| --- | --- | --- |
| Screenshot | **blocked** by the system | **cannot be blocked** |
| Screen recording | **blocked** (black frames) | **detected**, app covers itself |
| Screen mirroring / AirPlay | blocked to non-secure displays | **detected**, app covers itself |
| Recent-apps thumbnail | excluded by the system | covered by Privio (always, see below) |

> The switch protects **this device**. It cannot stop the person you are writing
> to from recording their own screen, and it cannot stop anybody pointing a
> second camera at yours. That sentence is on the settings screen, not only
> here, because a switch called "Screen protection" invites exactly that belief.

## Android: `FLAG_SECURE`

`ScreenShield.kt` adds `WindowManager.LayoutParams.FLAG_SECURE` to the
activity's window, and clears it again when the switch goes off.

**Why one flag covers the whole app.** The flag belongs to a *window*, and
Flutter draws every route, dialog, bottom sheet, image viewer and video surface
into the single window owned by `MainActivity`. So chats, groups, channels, the
profile screen and the media viewer are all covered by the one call, and there
is no per-screen opt-in anywhere in the Dart tree. That is deliberate: a list of
"sensitive screens" is a list somebody forgets to add to, and the screen they
forget is the one that matters.

What the platform documents the flag as doing:

- the screenshot key combination produces a toast instead of an image;
- a `MediaProjection` capture — the system recorder and every third-party
  recorder, which all go through that one API — receives black frames;
- the window is left out of the recent-apps thumbnail;
- the window is not mirrored to a non-secure external display.

**Device-dependent limits.** These are real and are not worked around:

- Some manufacturer builds (and some heavily modified ROMs) honour the flag
  incompletely, most often for the recents thumbnail rather than for the
  screenshot itself.
- A rooted device, an emulator with a host-side recorder, `adb shell
  screencap`, and a debugger attached to the process are all outside what any
  in-app flag can reach.
- An accessibility service with screen-capture permission is granted its access
  by the user at the OS level, and `FLAG_SECURE` does not revoke it.
- A physical camera pointed at the screen is, obviously, unaffected.

The alternative to documenting these would be a private API or a trick, and both
would be a promise the app cannot keep.

## iOS: detection, not prevention

There is no `FLAG_SECURE` on iOS and **no public API that stops a screenshot**.
`ScreenShield.swift` therefore does the only supported thing:

- `UIScreen.isCaptured` (public since iOS 11) says whether the screen's contents
  are being captured *right now* — screen recording, an active ReplayKit
  broadcast, AirPlay mirroring, or a QuickTime capture over a cable;
- `UIScreen.capturedDidChangeNotification` says when that changes;
- while the setting is on and a capture is running, Privio covers itself with
  its own neutral view and says why, and uncovers when the capture ends.

The screen the app is actually on is read from the foreground `UIWindowScene`
rather than from `UIScreen.main`, which is deprecated from iOS 16 and is the
wrong answer on a device driving an external display.

**What is deliberately not used:**

- **Any private API.** There is no supported one that blocks capture, and an
  unsupported one means a rejected build and a protection that stops working
  without warning.
- **The secure-text-field trick** — putting the whole interface inside a
  `UITextField` with `isSecureTextEntry`, so the compositor drops it from
  screenshots. It works on some iOS versions today, depends on an undocumented
  implementation detail Apple has changed before, and interferes with touch
  handling and accessibility.
- **Claiming a screenshot was blocked.**
  `userDidTakeScreenshotNotification` fires *after* the image exists. It could
  drive a notice; it is not a block, and Privio does not present one as the
  other.

So on iOS the honest statement is the one the settings screen makes: sensitive
content is hidden when a recording or a screen share is detected, and
screenshots cannot be reliably prevented.

## Supported OS versions

Nothing here needs an availability guard, which is worth stating rather than
leaving to be rediscovered:

- **iOS.** The project's deployment target is **15.0**.
  `UIScreen.isCaptured` and `UIScreen.capturedDidChangeNotification` are public
  since **iOS 11**, and `UIWindowScene.screen` since **iOS 13**. All three are
  therefore always available in every build this project produces.
- **Android.** `FLAG_SECURE` has existed since **API 1**, far below anything
  Flutter's `minSdkVersion` will ever be.

## The app-switcher cover is a separate thing

`PrivacyCover` in `app/lib/app.dart` covers the interface whenever the app is
not `resumed` — the frame the app switcher photographs, a pulled-down
notification shade, an incoming call, a permission sheet.

It **predates this setting and does not depend on it**: every account gets it,
on both platforms, switch or no switch. It wears the calculator disguise where
one is set, because a phone that opens as a calculator and shows a Privio splash
in the app switcher has announced exactly what the disguise was hiding.

Returning from the background goes through the existing lock: the cover comes
down when the app resumes, and if a passcode is set, the lock screen is what is
underneath it. Covering and locking are separate moments on purpose — `inactive`
covers, `paused` locks — so glancing at a notification does not demand a
passcode.

## No "screenshot taken" notice

Privio does not and will not tell the other side that you took a screenshot.
Two reasons, and the second is the one that matters:

1. It cannot be done honestly. Android gives no such signal at all, and iOS
   gives one only for the screenshot it has already taken — never for a photo of
   the screen with another phone, which is the easy way round it.
2. A notice that fires sometimes teaches people to trust it always. Somebody who
   believes they would be told is *more* exposed than somebody who knows they
   would not be.

## Where it is stored

Per account, in the keystore, under `privio.screenShield.<accountId>` — the same
shape as the language, the accent and the verified-calls switch, and for the same
reason: two people sharing a phone do not share a threat model. A new account
starts off. Signing out clears the flag and forgets the account, so the next
account never inherits a protection it did not choose.

The **choice** is stored even on a device that cannot honour it. The value is
what the account decided, not a record of what one particular phone managed to
do, so somebody who turns it on, is told their device cannot block screenshots,
and later signs in on one that can will find it on there.

## What is tested, and what is not

`app/test/screen_shield_test.dart` (25) and
`app/test/screen_shield_screen_test.dart` (10) cover: both capabilities and the
sentence each produces, the switch being dead where the platform can do neither,
turning it on and off — including that **off clears the flag rather than merely
stopping** — surviving a restart, not leaking between accounts, clearing on sign
out, a capture starting and stopping, a capture already running when the switch
goes on, Android never covering, a missing or throwing platform half reading as
"cannot" rather than crashing, and all five languages.

Three bugs were found by these tests and fixed: a `setEnabled` during sign-in
whose answer was then overwritten by the still-running `load`; a capability not
yet known when the switch was thrown; and — the one that mattered — reading the
setting inside `AppState.initialise`, which made start-up wait on a platform
channel. That deadlocked every widget test that boots an `AppState`, and on a
device with a slow or wedged channel it would have parked the app on the splash
screen. The setting is now read from `_onSignedIn`, detached, which already
covered both the cold start and the account switch.

**Not tested on a device.** There is no Android SDK and no Xcode in the
environment this was written in, and no phone. Nobody has watched a screenshot
fail on Android, and nobody has started a screen recording on an iPhone and seen
the cover appear. CI compiles both native halves; compiling is not running.
A new signed Android build and a new TestFlight build are required before any of
this can be seen at all.
