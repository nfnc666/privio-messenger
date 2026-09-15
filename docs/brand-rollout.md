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
| In-app (splash, welcome, sign-in, activation, About, loading) | `app/assets/logo/privio_{mark,wordmark}.png` via `PrivioMark` / `PrivioWordmark` |
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

**Not verified:** how any of it looks on a real phone. There is no simulator
here, so the launcher icon under a circular mask, the adaptive icon's parallax,
and the splash hand-off have been reasoned about and measured but not seen.
