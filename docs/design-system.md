# Privio Design System

Derived from the supplied brand assets and the 25-screen mockup sheet in
`design/mockups/privio-screens-v1.jpg`. Those files are the visual source of
truth; this document is the machine-readable version of them, and
`app/lib/theme/privio_theme.dart` is the code version.

## Brand assets

Two files are the artwork as delivered. Everything else is cut from them by
`tools/generate_brand_assets.py`, which is the only thing that writes a brand
asset anywhere in this repository — re-run it after a re-delivery rather than
editing a size by hand.

| File | What it is |
| --- | --- |
| `design/logo/privio-icon-master.png` | **Delivered.** The app icon: the mark on true black, full bleed, square |
| `design/logo/privio-wordmark-master.png` | **Delivered.** The horizontal lock-up on white |
| `design/logo/privio-mark.png` | Derived. The mark alone, transparent |
| `design/logo/privio-wordmark-light.png` | Derived. Transparent, black wordmark — for light surfaces |
| `design/logo/privio-wordmark-dark.png` | Derived. Transparent, white wordmark — for dark surfaces |

The mark is a green **P** whose counter is a speech bubble. The green is the
logo's own and is never recoloured — not for a dark surface, not for a light
one. What may change is the *wordmark*: black on light grounds, white on dark
ones. Since every surface in the app is black, the app ships the dark cut.

**Neither delivered file has an alpha channel.** The icon is green on solid
black, the wordmark green-and-black on solid white. Transparency is derived by
inverting the compositing equation, not by thresholding a background colour
away — a "white becomes transparent" pass eats the antialiasing and leaves a
pale fringe on every curve. The generator also floors coverage below 4/255,
because the flat fields in both masters carry compression noise that would
otherwise become a faint wash across the whole canvas.

## Colour tokens

Sampled from the mockups (JPEG, so values are normalised to clean hex).

### Accent

**The accent is a setting, not a constant.** Settings → Appearance offers eight,
stored per account; green is the default and what a new account gets. Everything
below is *derived from one seed* in `PrivioAccents.of` and carried on the theme
as a `ThemeExtension`, so a screen asks `context.accents.accent` rather than
naming a colour. The hexes in this table are what green produces — the shipped
palette, which the derivation was fitted to reproduce exactly.

| Token | Green | Use |
| --- | --- | --- |
| `accent` | `#22C55E` | Primary actions, active tab, sent-message ticks, toggles, online dots |
| `bright` | `#4ADE80` | Pressed/hover states, the neon glow on the splash and loading screens |
| `dim` | `#166534` | Disabled accent, subtle borders |
| `surface` | `#0F2A1A` | Accent-tinted panels: the E2EE banner, voice-note bubbles |
| `bubbleOutgoing` | `#0B3B21` | Outgoing message bubbles |
| `onAccent` | `#000000` | Text and icons **on** the accent |

The eight seeds: green `#22C55E`, blue `#3B82F6`, turquoise `#14B8A6`, violet
`#A855F7`, pink `#EC4899`, red `#F43F5E`, orange `#F97316`, yellow `#EAB308`.

`onAccent` is measured, not chosen: `PrivioAccents.readableOn` takes whichever
of black or white has the higher WCAG contrast against the seed. All eight
currently land on black — white on `#A855F7` is 3.96:1 and fails AA for normal
text, black is 5.31:1 — which is also what the app already did on green.
`test/accent_test.dart` holds every offered colour to ≥3:1 against the black
background and ≥4.5:1 for its own label, so a ninth accent cannot be added
without the check running against it.

**What the accent does not touch.** The black background and the grey cards are
the app's shape rather than its colour. `danger` and `warning` mean something:
red stays `#EF4444` for errors, deleting and hanging up in all eight themes,
which is why the accent red is a rose (`#F43F5E`) rather than a second shade of
the same thing. The brand mark's glow, the splash, and the disguise calculator
keep the fixed green — the first two are the brand, and an accent-coloured
calculator would be a tell. A channel keeps the colour *it* chose; a reader's
setting changes their own app, never anybody else's content.

### Neutrals

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#000000` | App background. True black — it is the brand, and it costs nothing on OLED |
| `surface` | `#0B0B0B` | Cards, list rows, bottom sheets |
| `surfaceRaised` | `#141414` | Search fields, incoming bubbles, settings rows |
| `surfaceHigh` | `#1E1E1E` | Pressed states, dividers on raised surfaces |
| `border` | `#232323` | Hairlines, 1px separators |
| `textPrimary` | `#FFFFFF` | Titles, message text, icons |
| `textSecondary` | `#A1A1A1` | Timestamps, subtitles, last-message previews |
| `textTertiary` | `#6B6B6B` | Placeholders, disabled labels, section captions |

### Status

| Token | Hex | Use |
| --- | --- | --- |
| `danger` | `#EF4444` | Duress code, missed calls, "Log out all devices", destructive rows |
| `warning` | `#F59E0B` | Unverified safety number, degraded connection |
| `calculatorOperator` | `#FF9F0A` | Operator keys in the iPhone-style disguise calculator only |

There is no light theme. The product is designed dark-first, the mockups are
all dark, and the Appearance screen used to carry a switch for a light half
that was never built — it is gone rather than left offering something the app
cannot do.

## Typography

- **Family:** the app ships its own face rather than naming one and hoping the
  platform has it. It is declared as `Privio` in `pubspec.yaml` and backed by
  Roboto (Apache-2.0) in `app/assets/fonts` — regular, medium and bold. The
  mockups were drawn in Inter; the two are close enough at these sizes that the
  layout is unchanged, and shipping the file is what stops a web build from
  fetching a fallback font from Google's CDN on first paint. Swapping in a
  licensed Inter later is three files and one line.
- **Scale:** display 32/38 semibold · title 22/28 semibold · headline 17/22
  semibold · body 15/20 regular · label 13/16 medium · caption 11/14 regular.
- Numerals in the PIN pad and the calculator are tabular; nothing else is.
- Wordmark "Privio" in the splash uses the logo asset, not live text.

## Shape and spacing

- Spacing scale: 4 · 8 · 12 · 16 · 20 · 24 · 32.
- Radii: 12 for cards and inputs, 18 for message bubbles, 24 for the primary
  button, 999 for avatars and pills.
- Screen gutter: 16. List row height: 72 for chats/contacts, 56 for settings.
- Elevation is expressed as surface lightness, not shadow. The only glow in the
  product is the accent bloom behind the splash and loading marks.

## Screen inventory

Numbers match the mockup sheet. The two rows without a number are not on it:
licensing came after it was drawn, and both follow its parts rather than
introducing anything new.

| # | Screen | Route | Milestone |
| --- | --- | --- | --- |
| 1 | Splash | `/` | V1 |
| 2 | Initialising / loading | `/boot` | V1 |
| 3 | First opening / welcome | `/welcome` | V1 |
| 4 | Passcode entry (keypad or passphrase) | `/lock` | V1 |
| 5 | Home / Chats | `/chats` | V1 |
| 6 | Chat | `/chats/:id` | V1 |
| 7 | Calls | `/calls` | V1 |
| 8 | Contacts | `/contacts` | V1 |
| 9 | Account | `/account` | V1 |
| 10 | Invite link / QR | `/account/invite` | V1 |
| 11 | Settings | `/settings` | V1 |
| 12 | Backup | `/settings/backup` | V1 |
| 13 | Duress code | `/settings/duress-code` | V1 |
| 14 | Disguise mode | `/settings/disguise` | V1, not on iOS |
| 15–16 | Calculator disguise (iPhone / Samsung skin) | `/disguise` | V1, not on iOS |
| 17 | Notifications | `/settings/notifications` | V1 |
| 18 | Data and storage | `/settings/storage` | V1 |
| 19 | Privacy and security | `/settings/privacy` | V1 |
| 20 | Devices | `/settings/devices` | V1 |
| 21 | Appearance | `/settings/appearance` | V1 |
| 22 | About Privio | `/settings/about` | V1 |
| 23 | Change password | `/settings/password` | V1 |
| 24 | Two-factor authentication | `/settings/2fa` | V1 |
| — | Activation (first start, licensed servers only) | stage, not a route | V1 |
| — | Privio License | `/settings/license` | V1 |
| — | Blocked users | `/settings/blocked` | V1 |

### Navigation bar

The mockups show four tabs — Chats, Calls, Contacts, Account. The brief lists
five, with Channels second. All five ship: Channels and Calls were planned as
later milestones and both have landed. `PrivioNavShell` takes the tab list as
data, which is why each arrived as one entry rather than a rewrite.

There is a sixth screen with no tab: the call screen. It is drawn above the
navigator, in the `MaterialApp` builder, so it covers whatever is open —
including a pushed chat or settings screen. It is the one place in the app that
deliberately sits outside the routing, because a ringing phone is not something
to go looking for in a tab.

There is no Language screen. The mockup sheet has one and Settings carried a
row reading "English" that opened nothing; Privio is English-only, so the row
is gone rather than offering a choice that does not exist.

## Component notes from the mockups

- **Chat list row:** 44px avatar with an accent online dot, name in headline,
  preview in `textSecondary`, timestamp top-right in caption, unread count as an
  accent pill. Attachment previews are prefixed with a small type icon.
- **Chat screen:** an accent-tinted E2EE notice sits above the first message of
  a conversation. Incoming bubbles use `surfaceRaised`, outgoing use `accentDim`,
  both radius 18 with one squared corner on the tail side. Outgoing uses
  `bubbleOutgoing`, not `accentDim` — the mockups' bubbles are much darker than
  the accent. Delivery ticks are
  `textTertiary` when sent and `accent` when read. Voice notes render a waveform
  inside an `accentSurface` bubble.
- **PIN entry:** four dots, a 3×4 keypad on `surface` circles, and a fingerprint
  affordance directly under the pad.
- **Settings rows:** leading icon in `textSecondary`, label in body, trailing
  chevron in `textTertiary`, grouped on `surface` cards with 12px radius.
  Destructive rows drop the icon and colour the label `danger`.
- **Toggles:** accent track when on, `surfaceHigh` when off.
- **Calculator disguise:** two skins. The iPhone-style one uses circular keys
  with `calculatorOperator` on the right column against true black; the
  Samsung-style one uses rounded squares with accent operators on `#1B1B1D`.
  One grid, one arithmetic model, two sets of clothes. Both behave as a real
  calculator: any sum whose answer is the passcode opens Privio on `=`, and
  every other answer is just an answer. The pad is sized from the screen's
  width and capped at 62% of its height, so it fills the screen on a phone and
  shrinks rather than overflowing on anything shorter.

  Screens 14–16 do not exist on an iPhone. The feature is withheld on iOS,
  which cannot rename an app, so a disguise there would carry Privio's own name
  under a calculator icon.
