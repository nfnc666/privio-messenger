# App-Icon / Home-screen icon

Settings → Appearance → App icon offers the Privio mark in eight colours and
changes the icon on the home screen. This note says where the pictures come
from, what each platform actually does, and what has *not* been verified.

## The pictures

One source: the delivered artwork in
`ios/Runner/Assets.xcassets/AppIcon.appiconset` and
`android/app/src/main/res/mipmap-*/ic_launcher*.png`. Everything else is that
file recoloured by `scripts/recolour_icons.py`.

The mark is two tones — the brand green `#01F47B` over black, or over nothing
in Android's adaptive foreground — so every pixel is a blend of the two and the
blend factor comes back exactly from one channel:

```
pixel = black*(1-t) + brand*t    =>    t = pixel.green / 244
```

Writing back `target*t` reproduces the identical coverage in another hue.
Nothing is redrawn, rescaled or re-antialiased, and the alpha channel is
carried across untouched. The shape, the proportions and the padding are
therefore the delivered ones in every variant, not an approximation of them —
`test/app_icon_test.dart` is not where that is checked; the generator's own
comparison is, and it reports a maximum per-pixel coverage difference of 1/255.

**Green is not recoloured.** It is the delivered file, copied. The brand green
is `#01F47B` and the accent-menu green is `#22C55E`; recolouring green to the
accent value would mean "restore the original" returned something that was not
the original. The other seven use the accent menu's own values, so the icon and
the interface name the same colours.

The swatches in the settings screen are a *third* thing again: the mark tinted
at draw time with `BlendMode.srcIn`. Same file, so the preview cannot drift
from what the launcher will show, and no fourth set of files to keep in step.

## iOS

Alternate app icons, declared in the asset catalog:

* `AppIcon-blue.appiconset` … `AppIcon-yellow.appiconset` next to `AppIcon`.
* `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` lists the seven, and
  `ASSETCATALOG_COMPILER_INCLUDE_ALL_APP_ICON_ASSETS = YES` gets them compiled
  in — both added to all three Runner build configurations.
* `ios/Runner/LauncherIcon.swift` swaps them with
  `UIApplication.setAlternateIconName`, and reads the current one back from
  `alternateIconName`.

The asset-catalog route rather than loose PNGs at the bundle root: it needs two
build-setting lines rather than twenty-odd file references with fresh UUIDs in
`project.pbxproj`, which is the difference between an edit that can be read and
one that can only be trusted.

Two things iOS decides and Privio does not work around:

* **It shows its own confirmation alert.** It cannot be suppressed, and
  suppressing it is not something an app should want — the home screen is the
  user's.
* **It cannot change the app's name.** There is no API. That is why the
  calculator *disguise* is not offered on iOS at all (a calculator icon still
  labelled Privio announces itself) while a *colour* is — a colour is not a
  disguise and has no such problem.

## Android

`activity-alias` entries, one per colour, all targeting `MainActivity`, so the
app that opens is the same app and only what the launcher draws differs. They
carry the ordinary app label: a colour is not a disguise, and relabelling it
would make it one.

`MainActivity.applyLauncher` enables the wanted alias **before** disabling
every other one. The order is not cosmetic: with no alias enabled, even for an
instant, some launchers drop the app from the home screen and Android may stop
the process. Disabling *all* the others afterwards is what stops a second entry
being left behind. `DONT_KILL_APP` keeps the process alive through it.

The change is then **read back**. Some manufacturer builds accept the call and
change nothing, and an icon that quietly did not move is worse than one that
reports it could not.

`currentEntry()` reads the package manager rather than a remembered value. An
alias nobody has touched reports `COMPONENT_ENABLED_STATE_DEFAULT`, which is
its manifest value — enabled for the green entry, disabled for the rest — so a
fresh install answers "green" without anything having had to write it.

## The rules this follows

**Per installation, not per account.** A home-screen icon belongs to the phone:
there is one of it, everyone who unlocks the device sees it, and signing in as
somebody else does not rearrange it. That is the opposite of the accent colour
on purpose — the accent is what *this account* sees inside the app, the icon is
what *this device* shows outside it. Stored under one unkeyed entry.

**Stored only after the platform agreed.** `AppIconController.choose` writes
nothing until `show` has returned. A setting that recorded its answer before
asking would show a tick under an icon the phone never adopted.

**The launcher is the truth.** `reconcile()` runs at start-up and again
whenever the settings screen opens: it reads the platform and corrects the
stored value if they disagree — a failed change, a restored backup, a build
that took the call and did nothing.

**The disguise wins while it is on.** The calculator and the icon colour want
the same slot. Picking a colour under an active disguise is refused with an
explanation rather than quietly undoing a security setting through a cosmetic
one. Switching the disguise *off* restores the chosen colour, not the default.

**The store icon does not change.** `ASSETCATALOG_COMPILER_APPICON_NAME` is
still `AppIcon`, and `DefaultLauncher` is still the enabled alias on a fresh
install. What ships and what the listing shows is the green original.

## Tested, and not tested

Held by automated tests (`test/app_icon_test.dart`, and the screen and
account-switch cases in `test/accent_choice_test.dart`): the choice reaching the
platform, nothing being stored when it refuses, a platform that cannot do it at
all being told apart from one that would not, the stored value surviving a
restart, the launcher winning a disagreement, the disguise interaction in both
directions, an account switch leaving the icon alone, and the section's
swatches, tick, reset and unavailable line.

**The native code has not been compiled, let alone run.** This work was done on
Linux in a container with **no Android SDK and no Xcode** — `flutter doctor`
reports both toolchains absent. `MainActivity.kt` and `LauncherIcon.swift` have
therefore never been through a compiler, and the `project.pbxproj` edits have
only been checked for balanced braces and matching names.

That is why `test/app_icon_assets_test.dart` exists: it reads the manifest, the
Kotlin, the Swift and both asset catalogues and checks that every colour is
named identically in all of them. A typo there would otherwise not fail
anything on this machine — it would fail once, on a phone, as an icon that did
not change. The test catches the likeliest mistake; it cannot catch a
compilation error.

None of the following has been observed:

* that the Kotlin and the Swift compile;
* that the icon on a real home screen actually changes, on either platform;
* that Xcode accepts the two build settings and compiles the seven alternate
  sets;
* that launching the app from a changed icon works;
* that no duplicate launcher entry is left on any particular Android skin;
* how long a given launcher takes to redraw its grid;
* what iOS's confirmation alert looks like in each of the five languages (it is
  the system's own text, not Privio's).

**A new build is required for any of it.** The assets and the native code are
only in the bundle after one, so nothing here can be checked from a TestFlight
build made before this change.
