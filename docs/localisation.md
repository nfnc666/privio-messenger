# Sprachen / Languages

Privio speaks English (default), Deutsch, Español, Français and Italiano. This
note says where the words live, what deliberately stays untranslated, and what
is not solved yet.

## Where the words live

* `app/lib/l10n/app_en.arb` is the template — every key, with its placeholders
  and plural forms. `app_de/es/fr/it.arb` hold exactly the same key set; a
  language that drifted from the template would fail generation rather than
  fall back silently at runtime.
* `app/l10n.yaml` points `flutter gen-l10n` at them and writes
  `app/lib/l10n/app_localizations*.dart` (committed) plus `l10n-missing.json`,
  which must stay `{}`.
* The generated class is `AppText`. Screens read it with `AppText.of(context)`.

## The rule everything else follows

**A model, a service or a controller cannot write a sentence, because it cannot
know which language the person reading it has chosen.** So they return a typed
case, and the screen says the words. That is why these exist:

| Case | Said by |
| --- | --- |
| `Failure` / `FailureKind` (`core/failure.dart`) | `l10n/failure_text.dart` |
| `SystemNotice` / `NoticeKind` (`models/models.dart`) | `l10n/notice_text.dart` |
| `ChatPreview`, `ChatStamp` (`models/models.dart`) | `l10n/chat_text.dart` |
| `ChannelPresence`, permission keys, report reasons | `l10n/channel_text.dart` |
| `PasscodeComplaint` (`core/passcode.dart`) | `l10n/passcode_text.dart` |
| `NotificationWarning` (`services/wake_up.dart`) | `l10n/failure_text.dart` |

A system notice is **stored** as its event — kind plus parameters — not as a
finished sentence. Two people in one chat with the app set to different
languages each read the same stored fact in their own. The sentence is built at
the moment the bubble is drawn.

## What is never translated

* Messages, channel names, descriptions, group names, file names — anything a
  person wrote. Choosing a language changes the interface and nothing else; it
  never triggers content translation.
* **PRIVIO** and other proper names.
* Language names in the picker are endonyms (Deutsch, not German) and are the
  same in all five.
* The licence key shape `PRIVIO-XXXX-XXXX-XXXX-XXXX`.

## Per account, and only that account

`LocaleController` is keyed by account id. Loading an account resets to English
*first* and then applies what was stored, so a slow read cannot leave the
previous account's language on screen. Signing out returns to English. A new
account starts in English and never inherits another's choice. Before sign-in
the app is English.

## Dates, times and numbers

Through `intl`, with the reader's locale: `DateFormat.Hm`, `Md`, `yMd`,
`MMMMd`, `yMMMMd`. `initializeDateFormatting()` runs in `main()`. Every call is
wrapped so a phone whose date symbols did not load falls back to the
locale-independent format rather than throwing.

Plurals are ICU (`{count, plural, …}`), so each language keeps its own rule
rather than English's idea of one-versus-many.

## Known limitation

**Error text the server wrote arrives in English.** The client maps every
server error *code* it knows to a `FailureKind` and says it in five languages.
A code it does not know falls back to `Failure.server(message)` — the server's
own wording, passed through untouched rather than guessed at. Closing this gap
means either the server sending codes for everything, or the client shipping
translations for wording it does not control; neither is done.
