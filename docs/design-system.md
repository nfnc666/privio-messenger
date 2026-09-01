# Privio Design System

Derived from the supplied brand assets and the 25-screen mockup sheet in
`design/mockups/privio-screens-v1.jpg`. Those files are the visual source of
truth; this document is the machine-readable version of them, and
`app/lib/theme/privio_theme.dart` is the code version.

## Brand assets

| File | Use |
| --- | --- |
| `design/logo/privio-logo-wordmark.png` | Splash screen, About screen, store listings |
| `design/logo/privio-mark-transparent.png` | App icon, in-app mark, notification icon |

The mark is a white speech bubble enclosing a white padlock. It is always solid
white — never tinted green. The green in the product comes from the accent
colour, never from the logo.

## Colour tokens

Sampled from the mockups (JPEG, so values are normalised to clean hex).

### Accent

| Token | Hex | Use |
| --- | --- | --- |
| `accent` | `#22C55E` | Primary actions, active tab, sent-message ticks, toggles, online dots |
| `accentBright` | `#4ADE80` | Pressed/hover states, the neon glow on the splash and loading screens |
| `accentDim` | `#166534` | Disabled accent, outgoing bubble fill, subtle borders |
| `accentSurface` | `#0F2A1A` | Accent-tinted panels: the E2EE banner, voice-note bubbles |
| `bubbleOutgoing` | `#0B3B21` | Outgoing message bubbles (measured at ~#043019 in the mockups, lifted a shade for text crispness) |

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

There is no light theme in V1 beyond what the Appearance screen offers as a
switch; the product is designed dark-first and the mockups are all dark.

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
| 7 | Calls | `/calls` | V2 |
| 8 | Contacts | `/contacts` | V1 |
| 9 | Account | `/account` | V1 |
| 10 | Invite link / QR | `/account/invite` | V1 |
| 11 | Settings | `/settings` | V1 |
| 12 | Backup | `/settings/backup` | V1 |
| 13 | Duress code | `/settings/duress-code` | V1 |
| 14 | Disguise mode | `/settings/disguise` | V2 |
| 15–16 | Calculator disguise (iPhone / Samsung) | `/disguise` | V2 |
| 17 | Notifications | `/settings/notifications` | V1 |
| 18 | Data and storage | `/settings/storage` | V1 |
| 19 | Privacy and security | `/settings/privacy` | V1 |
| 20 | Devices | `/settings/devices` | V1 |
| 21 | Appearance | `/settings/appearance` | V1 |
| 22 | About Privio | `/settings/about` | V1 |
| 23 | Change password | `/settings/password` | V1 |
| 24 | Two-factor authentication | `/settings/2fa` | V1 |
| 25 | Language | `/settings/language` | V1 |
| — | Activation (first start, licensed servers only) | stage, not a route | V1 |
| — | Privio License | `/settings/license` | V1 |
| — | Blocked users | `/settings/blocked` | V1 |

### Navigation bar

The mockups show four tabs — Chats, Calls, Contacts, Account. The brief lists
five, with Channels second. Channels and Calls are both V2 features, so V1 ships
**Chats · Contacts · Account** and the shell adds Calls and Channels as their
milestones land. `PrivioNavShell` takes the tab list as data so the bar grows
without a rewrite.

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
- **Calculator disguise:** two skins. iPhone uses circular keys with
  `calculatorOperator` on the right column; Samsung uses rounded-square keys with
  accent operators. Both must behave as a real calculator — the secret code is
  entered as a normal expression and only the `=` key opens Privio.
