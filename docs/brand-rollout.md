# Rolling out the new mark

The logo and app icon were replaced across the repository. This is what that
covered, what it deliberately did not, and what has to be done by hand in places
this repository cannot reach.

## Where the artwork lives

Two delivered files, and one script that derives everything else:

```
design/logo/privio-icon-master.png      the app icon, as delivered
design/logo/privio-wordmark-master.png  the horizontal lock-up, as delivered
tools/generate_brand_assets.py          writes every size from those two
```

Re-run the script after a re-delivery. Nothing else in the repository writes a
brand asset, so there is no second place to keep in step:

```
python3 tools/generate_brand_assets.py
```

## What it replaced

| Where | Files |
| --- | --- |
| iOS app icon | 16 sizes in `AppIcon.appiconset`, including the 1024 App Store / TestFlight asset |
| iOS launch image | `LaunchImage@1x/2x/3x` |
| Android legacy launcher | `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` |
| Android adaptive launcher | `ic_launcher_foreground.png` per density, `mipmap-anydpi-v26/ic_launcher.xml`, `values/colors.xml` |
| Android launch window | `drawable/` and `drawable-v21/launch_background.xml` |
| In-app (splash, welcome, sign-in, activation, About, loading) | `app/assets/logo/privio_{mark,wordmark}.png` and the two-layer `privio_wordmark_{symbol,word}.png`, via `PrivioMark` / `PrivioWordmark` |
| Web shell | `favicon.png`, `Icon-{192,512}.png`, `Icon-maskable-{192,512}.png` |
| Channel invite pages | `server/assets/privio-mark.png` on the page, `privio-icon.png` for link previews |
| README | theme-aware `<picture>`, light and dark cuts |

Ordinary interface icons — back, search, the padlock that marks an unreadable
post — are untouched. So is the calculator icon the disguise mode ships
(`ic_calculator`): it is a disguise, and branding it Privio would defeat it.

App id, bundle identifier, signing and user data were not touched.

## Two decisions worth knowing about

**The delivered files have no alpha channel.** The icon is green on solid black;
the wordmark is green-and-black on solid white. Transparency is *derived* by
inverting the compositing equation rather than by thresholding a background
colour away — a "white becomes transparent" pass eats the antialiasing and
leaves a pale fringe on every curve. Coverage below `4/255` is floored to zero,
because the flat fields in both masters carry compression noise that would
otherwise become a faint wash across the entire canvas and defeat every trim.

**The lock-up changed shape.** The previous one stacked the mark above the word
and was barely wider than tall; the new one is horizontal at roughly 3.4:1. At
the sizes the splash and About screens were passing, it would have run off the
edge of a 320-point phone, so `PrivioWordmark` now clamps itself to a fraction
of the available width and both call sites were re-sized.

## The mark follows the accent — where it can

Everything Flutter draws is painted in the accent from
`Settings → Appearance`: the mark, the lock-up's symbol, the splash's tagline,
its progress bar and the faint rain behind it. `PrivioColors.accent` — the
brand green as a constant — appears in no screen any more; the colour comes
from `Theme.of(context).extension<PrivioAccents>()`, which is the same value the
rest of the app is drawn from. There is no second setting and no second palette.

**How the artwork is recoloured.** `ColorFilter.mode(accent, BlendMode.srcIn)`
over artwork that is one flat ink. The alpha channel decides coverage, so the
shape and the softness of every curve survive exactly; only the ink changes.
That is why there is no per-colour cut of the logo and why the mark cannot
shift by a pixel between accents.

The lock-up needed splitting first: it is green symbol *and* white text, and one
filter over the flat file would recolour the word too.
`build_wordmark_layers()` writes `privio_wordmark_symbol.png` and
`privio_wordmark_word.png`, both cropped to the **combined** bounding box, so
stacking them is the flat artwork again at the same size and spacing. Cropping
each to its own ink would have shifted the two apart.

### The first frame

`main()` awaits `AccentController.preload()` before `runApp`. It reads the last
signed-in account id and that account's stored accent — two local keystore
reads, no network, no artificial delay — so the first frame the user sees is
already the right colour. `AppState.initialise()` loads it again, and
`load()` now only resets to green when the colour on screen belongs to *another*
account; resetting unconditionally, as it used to, would have repainted the
splash green for a frame directly over what `preload` had just put there.

The preload is capped at 500 ms. A keystore read is still a platform channel,
and an app that one wedged channel can hold on a black screen is worse than an
app that starts green and corrects itself a moment later.

Per account throughout: the accent is keyed on the account id, an account with
nothing stored is green, a switch never inherits the previous account's colour,
and every sign-out path clears it.

### What the native splash can and cannot do

The screen the *operating system* draws before Flutter starts is a static
resource. No code of ours runs, so there is no preference to read and nothing to
read it with; making one follow a per-user colour would mean writing resource
files at runtime or reaching for private APIs, and neither is something this app
will do.

So both native launch screens are now **plain black** — the app's own
background, and the same black the Flutter splash sits on. The hand-off is
black to black, and the first mark anybody sees is the one Flutter draws in
their colour. Two things changed to get there:

| Platform | Before | Now |
| --- | --- | --- |
| iOS `LaunchScreen.storyboard` | **White** background with the green mark centred | Black, nothing on it |
| Android `launch_background.xml` | Black with the green launcher foreground centred | Black, nothing on it |

The iOS background was the Flutter template's white in front of an app that is
true black — a white flash on every cold launch, independent of this work.

**One platform limit remains, and it is Android's.** From Android 12 the system
draws its own splash from the launcher icon (`windowSplashScreenAnimatedIcon`),
and that icon is a resource, not a preference. On those versions the green mark
appears briefly before the app's own view regardless of what this drawable says.
It is the launcher icon doing what a launcher icon does; the alternative is a
runtime resource swap, which is the kind of trick this file exists to refuse.

**The home-screen icon is untouched.** It is a different asset with its own
setting — see [`app-icon.md`](app-icon.md) — and it stays whatever the user
picked there, whatever accent they choose here.

## What still has to be done by hand

**Nothing here has been published.** These are portal changes, outside the
repository:

| Portal | What to upload |
| --- | --- |
| App Store Connect | The 1024×1024 icon is built into the app binary, so it ships with the next TestFlight or App Store build. The **marketing** assets — screenshots, the promotional artwork — still carry the old mark and are replaced in the listing by hand. |
| Google Play Console | The launcher icon ships in the AAB. The **512×512 store icon** and the feature graphic are uploaded separately in the listing. |
| Anywhere the wordmark appears outside this repository | A marketing site, social profiles, press material. |

`design/logo/privio-icon-master.png` is 1254×1254, so it downsamples cleanly to
both stores' 512 and 1024 requirements; the generator already writes a 1024
opaque copy at `server/assets/privio-icon.png` if a file is easier than a crop.

### If a marketing website exists

This repository contains the app, the server and the channel invite pages, and
those are all updated. **A separate marketing site, if there is one, is not in
this repository and has not been touched** — it would need the same swap, and
`design/logo/privio-wordmark-{light,dark}.png` are the files for it.

## What was verified, and what was not

Verified here: every generated file's dimensions and colour mode; that no iOS
icon carries an alpha channel or a non-square size (Apple rejects both); that
the derived alpha has no dark halo when composited on white; that the wordmark's
dark cut is white text with the green *unchanged*; that the invite page serves
an opaque preview image and a transparent on-page mark; the full server and
Flutter suites.

Verified for the accent work: all eight colours on the splash, read off the
colour filter and off the tagline's own style rather than off a screenshot;
that the background stays black whatever the accent; that `preload` reads the
stored colour with nothing else signed in; that a signed-out device and an
account that never chose are both green; that loading the same account twice
repaints **nothing** — the no-flash rule, asserted by counting notifications —
while an account switch passes through green and never through the other
account's colour; that a relaunch reads back the choice and a reset reads back
green. Falsified: hard-coding the green back into the lock-up turns seven colour
tests red, and resetting unconditionally in `load` turns the no-flash test red.

**Not verified:** how any of it looks on a real phone. There is no simulator
here, so the launcher icon under a circular mask, the adaptive icon's parallax,
the native-to-Flutter hand-off on both platforms, and Android 12's own splash
have been reasoned about and measured but not seen.
