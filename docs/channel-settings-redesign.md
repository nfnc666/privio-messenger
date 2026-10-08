# Channel settings: the Privio layout

The channel screens were built from Telegram screenshots, and they showed it:
a large centred profile, a row of four round actions, and a settings page that
was one long list of coloured icons in the order Telegram puts them. This note
is the redesign — what moved where, and the inventory it was checked against.

**The inventory came first.** A redesign that reorganises eighty functions by
eye loses some of them silently, and "silently" is the part that matters: a
permission that no longer has a row is a permission nobody can withdraw. So
every function in the old screens is listed below with its new home, and
`test/channel_settings_test.dart` asserts the ones that can be asserted.

## What the old screens held

| Where | Functions |
| --- | --- |
| **Feed app bar menu** | channel info, invite link, scheduled posts, join requests, picture, reactions, comments on/off, members, statistics, hand the channel on, report, leave, delete |
| **Profile screen** | picture, name, verified badge, audience count, livestream, mute/unmute, search, overflow; share link with copy and QR; description; admins; subscribers; settings; media and links tabs |
| **Profile overflow** | copy link, QR code, invite settings, statistics, report, leave |
| **Edit screen** | picture choose/remove, name, description, public/private explanation, discussion on/off, reactions, welcome message on/off and text, appearance (accent, background), direct messages, admins, subscribers, signature; save and cancel with a dirty check |
| **Admins screen** | the list, add, per-admin permissions, dismiss, hand the channel on, signature |
| **Subscribers screen** | the list, search, add from contacts, remove, silence, copy link |
| **Members screen** | role, the five permission grants, silence, remove |
| **Invite sheet** | expiry, usage limit, approval required, replace the link |
| **Statistics sheet** | posts, waiting to join, waiting to publish, people who voted |

## Where each one lives now

The new **Channel settings** screen is sections of plain rows, each with a
one-line summary of what it is currently set to, and each opening its own page.
Nothing is a tile, nothing is centred, and no row carries a coloured square.

| Section | Rows | Opens |
| --- | --- | --- |
| *(header)* | picture, name, short description, left-aligned | — |
| **Channel profile** | picture, name, description, link | Profile page (new) |
| **Access & invitations** | public or private, invite link, join requests | Access page (new) |
| **Team & members** | administrators, subscribers | The existing admin and subscriber screens |
| **Posts & interaction** | reactions, discussion, welcome, signature, direct messages, appearance | Posts page (new) |
| **Integrations** | livestream | The existing livestream flow |
| *(separated, at the end)* | hand the channel on, delete the channel, leave | Confirmations |

Everything else keeps the screen it already had — the admin list, the
subscriber list, the member permission sheet, the statistics, the scheduled
posts and the reaction picker are unchanged, because they were not the part
that looked copied.

## What changed about *how* it looks

* **A compact left-aligned header.** 56pt picture, name, one line of
  description, on one row. The old screen spent the first third of a phone on a
  96pt circle, a centred name and a count.
* **Sections with summaries.** Every row says what it is set to — *Public ·
  @handle*, *3 administrators*, *6 reactions*, *Signature on* — so the common
  question ("what is this channel set to?") is answered without opening
  anything.
* **No colour-coded icons.** The old rows had a blue megaphone, a red heart, a
  purple hand. Privio has one accent, the one the person chose, and it is used
  for what is interactive — not as decoration that happens to differ per row.
* **One typographic scale.** Section captions are small and upper-case, rows are
  body text, summaries are secondary. No row is larger than another to signal
  importance; order does that.
* **Danger at the end, with air above it.** Handing the channel on and deleting
  it sit under their own caption, after a gap, in the danger colour.

## What is new rather than moved

**Deleting a channel has a screen.** `ChannelController.delete` existed and was
reachable only from the feed's overflow menu; the settings screen now offers it
where the rest of the dangerous things are, behind a confirmation that asks for
the channel's name. The API call is the one that was already there.

Nothing else was added. In particular there is **no bot row under
Integrations**: a bot cannot post to a channel yet — see
[`bot-api.md` §9](bot-api.md#9-what-is-not-built-yet) — and a row that led
nowhere would be exactly the kind of decoration this redesign removes.

## Second pass: what a real phone showed

The first version was tested in widget tests at the default text size and looked
right there. On a phone with the text size turned up it did not: a row laid its
summary *beside* its title, the channel description took the whole width, and
"Bild, Name und Beschreibung" was pressed into a column one letter wide. The
header also said "1 subscriber" in English on a German phone, because the count
came from the model's own English string instead of the translations.

What changed:

* **Every row is a tile** (`widgets/channel_settings_tiles.dart`): an icon in a
  tile of the account's accent, the title on its own line, what it is set to
  under it, and a chevron. The title can no longer be squeezed by anything.
* **Switch states read as a pill** — *An* in the accent, *Aus* in grey — on the
  overview, so nobody has to open a page to see how it is set.
* **Red is kept for what cannot be undone**: the last section, its caption, its
  tiles and *Link ersetzen* on the access page. Ownership transfer on the admin
  page moved from a one-off amber to the same red.
* **Fields are labelled above the box**, with a quiet counter under it, instead
  of a label floating on the outline.
* **Captions are sentence case** in all five languages, in the accent.
* **The header says public or private in words** with an icon, not a grey
  globe, and the audience comes from the translations.
* `SettingsRow` everywhere else no longer lets a value take more than its half
  of the line, so the same squeeze cannot happen on any other settings screen.

No function moved or disappeared: the inventory test still asserts every row by
name for the owner, an editor-only admin, a doorkeeper and a subscriber. New
tests: a phone-sized screen at 1.6× text with a long description (the title must
be wider than tall and the summary below it), every tile carrying its icon, the
four switch states drawn as pills, and the audience in German.

