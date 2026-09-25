# Device beta checklist

Everything in this repository has been tested without a phone. That is not a
complaint about the tests — the suites are real and they run — but a test suite
cannot tell you whether a locked iPhone rings, whether a Pixel with a battery
optimiser still wakes, or whether a voice message recorded on one handset plays
on another. This document is the list of things only a device can answer.

**Nothing here may be marked as passed from reading the code.** A row is passed
when somebody ran it on the named hardware and wrote down what happened. Every
row starts as `not run`, and a row that stays `not run` at the end of a beta is
a result too: it says that part is unverified, which is the truth and is more
useful than an optimistic tick.

## Using it

* One row per test **per device pair**. The same test on Android↔Android and on
  Android↔iPhone is two rows, because the answers differ.
* **Build / commit** is the commit the binary was built from, plus the edition
  (`libre`, `direct`, `play`, `appstore`). `tools/build-info.sh` prints both,
  and the About screen shows what the running build believes it is. If those
  two disagree, stop and fix that first — everything after it is measuring
  something unknown.
* **Result** is one of `pass`, `fail`, `blocked`, `not run`. `blocked` means
  something outside the test stopped it (no certificate, no distributor app, no
  second handset) and is not a failure of the app.
* **Evidence** is what makes the result checkable later: a screenshot, a screen
  recording, a timestamp plus the matching server log line, an `adb logcat`
  excerpt, a Console.app excerpt.
* **Evidence must carry no credentials.** No session tokens, no APNs `.p8`, no
  FCM service-account JSON, no push tokens, no UnifiedPush endpoint URLs — an
  endpoint URL is a capability to wake somebody's phone. Redact before pasting.
  The server already redacts `token=` from its own request logs; a screenshot
  of a debug screen does not.
* A failure gets an issue, and the issue gets the row's evidence. "It did not
  work" without a build id and a device is not reproducible.

## What is needed before starting

| Thing | Why | Status here |
| --- | --- | --- |
| Two Android handsets (one with Play services, one without) | `play` and `libre`/`direct` are different push paths, not a setting | Not available |
| Working CI | The builds are made on GitHub's runners | **Yes, since 2026-09-07** — the repository is public, so Actions minutes are free |
| One iPhone, physical | A simulator has no APNs at all | Held by the maintainer |
| A reachable server with a real TLS certificate | The client pins and refuses plain HTTP | Not set up — the deployment path exists and is CI-verified ([`docs/deployment.md`](deployment.md)), but nobody has deployed it |
| APNs key (`.p8`, key id, team id, topic) | Otherwise iOS pushes are `skipped`, not sent | Not held |
| FCM service-account key | Otherwise Play-edition pushes are `skipped`, not sent | Not held |
| A UnifiedPush distributor (ntfy, NextPush, Sunup) | The `libre`/`direct` path has no push without one | Not installed |
| An Apple developer account | An iOS build cannot be installed on a handset without one. No Mac and no PC needed — see [`ios-testflight.md`](ios-testflight.md) | Account held; nothing configured yet |

The server says which push providers are real at start-up
(`push providers configured; …`). Read that line before testing anything about
notifications: a provider that is not configured returns `skipped`, and a
`skipped` push is not a bug in the phone.

## 1. Builds

Nothing below can start until these produce an installable artefact. None of
them has been produced in this environment: there is no Android SDK here
(`flutter build apk` stops at `No Android SDK found`, and installing one needs
`dl.google.com`, which this environment's network policy denies), and no macOS.

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | `flutter build apk --flavor libre --dart-define=PRIVIO_EDITION=libre` produces an APK that installs and opens | — | | | | not run | |
| B2 | `flutter build apk --flavor direct --dart-define=PRIVIO_EDITION=direct` — same, and the app is named Privio, not Privio Libre | — | | | | not run | |
| B3 | `flutter build appbundle --flavor play --dart-define=PRIVIO_EDITION=play` builds | — | | | | not run | |
| B4a | The **iOS signing setup** workflow creates the certificate and profile and writes them back as secrets — once, on a Linux runner | Needs the App Store Connect key and a short-lived token with secrets write. Refuses rather than revoking a certificate you may be using | | | | not run | |
| B4 | The **iOS signed build** workflow produces a signed `.ipa` — Actions → *iOS signed build* → Run workflow, `upload: no`. See [`ios-testflight.md`](ios-testflight.md) | Needs no Mac and no PC; needs a working Actions account | | | | not run | |
| B7 | The same workflow with `upload: yes` puts the build in TestFlight, and it installs on the iPhone | Export compliance has to be answered in App Store Connect before an internal tester sees it | | | | not run | |
| B5 | A mismatched pair (`--flavor libre` with `PRIVIO_EDITION=play`) is refused by Gradle rather than shipped | Rule is unit-tested; the refusal itself is not, it needs a real Gradle run | | | | not run | |
| B6 | About screen shows the same commit and edition `tools/build-info.sh` printed | — | | | | not run | |

## 2. Account and session

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | Register a new account; it is reachable by username, with no phone number or email asked for | — | | | | not run | |
| A2 | Sign in on a second device of the same account; both receive their own copy of a message | — | | | | not run | |
| A3 | Sign out on one device: the other keeps working, the signed-out one stops receiving | — | | | | not run | |
| A4 | Wrong password is refused, and refused the same way whether or not the username exists | — | | | | not run | |
| A5 | Change the password: every **other** device is signed out within a second, the one that changed it is not | The other device must be connected to see it happen immediately; offline, it finds out when it reconnects | | | | not run | |
| A6 | Revoke a device from another device: its socket closes at once and it stops receiving | Same | | | | not run | |
| A7 | Delete the account: every device is signed out and the username stops resolving | — | | | | not run | |

## 3. Session revocation on a live connection

These are the ones a device beta is actually for: the server-side behaviour is
covered by `server/test/ws_revocation.test.ts` and
`server/test/ws_session_races.test.ts`, but what a handset does when its socket
is closed under it — whether it retries in a loop, whether it shows a sensible
screen — is not something a test asserts.

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R1 | With the app open and the chat visible, sign the device out from another device: it stops receiving within a second and shows the signed-out state, not a spinner | — | | | | not run | |
| R2 | The signed-out device does not silently delete anything: messages sent to it while it was being revoked are still delivered to the device that stays signed in | — | | | | not run | |
| R3 | Revoke while a message is arriving (send several, revoke mid-flight): nothing partially arrives and nothing is lost | Timing is hard to hit by hand; repeat it a few times | | | | not run | |
| R4 | Let a session expire (shorten `SESSION_TTL_DAYS` on a test server): the open socket closes on its own within `WS_REVALIDATE_MS` (default 60 s) | This is a *periodic* check; it is not instant by design | | | | not run | |
| R5 | Stop Redis on a multi-instance deployment, then sign out: the socket still closes, within one revalidation interval rather than immediately, and the server logs `revocation broadcast failed` | Single-instance deployments have no Redis and no window | | | | not run | |
| R6 | The app comes back cleanly after a revocation — signing in again works, history is intact | — | | | | not run | |

## 4. Messaging, Android ↔ Android

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 | Send and receive text both ways; delivery and read state match what actually happened | — | | | | not run | |
| M2 | Safety numbers match on both handsets, and change when one reinstalls | — | | | | not run | |
| M3 | Record and send a voice message; it plays on the other device with the same duration | Codec support is per-manufacturer; note the handset | | | | not run | |
| M4 | Send an image attachment; it arrives, and its metadata (EXIF, location) is gone | — | | | | not run | |
| M5 | Reply, react, edit-window behaviour and deletion all appear the same on both sides | — | | | | not run | |
| M6 | Disappearing messages: both sides remove the message at the same point | Clocks differ; a few seconds apart is not a failure | | | | not run | |

## 5. Messaging, Android ↔ iPhone

Every row in section 4, repeated across the platform boundary — that is where
the interesting failures live (encoding, clock skew, notification behaviour).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| X1 | Text both ways | — | | | | not run | |
| X2 | Voice message recorded on Android plays on iPhone, and the reverse | Different recorders; this is the row most likely to fail first | | | | not run | |
| X3 | Image attachment both ways, metadata scrubbed both ways | — | | | | not run | |
| X4 | A group with both platforms in it: everyone sees the same messages and the same membership | — | | | | not run | |
| X5 | Safety number verification between the two platforms | — | | | | not run | |

## 6. Groups and channels

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G1 | Create a group, add two members, everyone can post and read | — | | | | not run | |
| G2 | Remove a member: they stop receiving, and messages sent afterwards are unreadable to them | — | | | | not run | |
| C1 | Create a private channel; the name is not visible to anyone without the key | — | | | | not run | |
| C2 | A joiner sees posts from the current key version onwards, and the channel's name | The boundary is the last rotation, not the moment of joining — older posts under the same key version are readable, by design | | | | not run | |
| C3 | **Remove a member → the key rotates → post again**: the remaining members read the new post, the removed member cannot | The removal advances the version; a device has to generate the new key. If no admin opens the app, the channel shows as awaiting its key | | | | not run | |
| C4 | The remaining members receive the new key without asking for it — no padlocks left after the admin's device has been open once | Delivery is per member; an unreachable member gets it when they next ask | | | | not run | |
| C5 | Kill the admin app in the middle of a rotation (immediately after the removal), reopen it: the rotation finishes — key promoted, private channel name readable by a member who joined afterwards | This was the bug fixed in this milestone; it is worth doing twice | | | | not run | |
| C6 | Two admins remove someone at the same moment: one key version is spent, not two, and the channel stays publishable | Needs two handsets and some coordination | | | | not run | |

## 6b. Opening a profile from a chat

Covered by `app/test/contact_profile_test.dart`; none of it has been run on a
phone. See [`contact-profiles.md`](contact-profiles.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | Tap the header of a one-to-one chat: the profile that opens is **that** person — name, `@handle` and picture match who you were talking to | — | | | | not run | |
| P2 | Type half a message, open the profile, come back: the draft and the scroll position are exactly as they were | A soft keyboard dismissing and reappearing is the part a widget test cannot reproduce | | | | not run | |
| P3 | In a group, tap a sender's name: that sender's profile opens, not the group's | — | | | | not run | |
| P4 | Tap the group's own header: the group screen opens, as before | — | | | | not run | |
| P5 | **Message** from a profile reached elsewhere lands in the existing chat with its history — not a second, empty one | — | | | | not run | |
| P6 | Block from the profile, then open the blocked person again: the banner and **Unblock** are there, and unblocking restores the ordinary actions | Needs a second account | | | | not run | |
| P7 | A contact who has hidden their status and last-seen shows neither — and no row anywhere saying something is hidden | Needs a second account with `lastSeen: nobody` and `profileStatus: nobody` | | | | not run | |
| P8 | Tap the large picture: it opens full-screen and pinch-zooms. With no picture, the tap does nothing | Only a contact whose profile key has arrived has a picture at all | | | | not run | |

## 6b-2. Two names

Covered by `app/test/profile_name_test.dart` and `server/test/names.test.ts`;
none of it has been on a phone. See [`names.md`](names.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| N1 | Sign up: the username field says the name cannot be changed later, **before** the password is filled in, and a taken name is flagged when the field is left | Needs a name that is already registered | | | | not run | |
| N2 | Sign up with a display name containing a space and an emoji typed from the system picker: it arrives intact in the other person's chat list | The system emoji picker is the part a widget test cannot reproduce | | | | not run | |
| N3 | Account → Edit profile: change the display name, reopen the app, it is still changed; clear it, and the account is shown as @username again | | | | | not run | |
| N4 | The username row copies to the clipboard and cannot be edited anywhere in the app | | | | | not run | |
| N5 | Change the display name on one phone: the other device and a contact's device both show the new name, and the chat, its history and its safety number are unchanged | Needs two handsets and a second account | | | | not run | |

## 6c. Matching the address book

Covered by `app/test/contact_match_test.dart` against a fake address book; the
system permission dialog and a real address book have never been near this.
See [`phone-contacts.md`](phone-contacts.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | With "Sync device contacts" **off**, no match row is offered and **no contacts prompt ever appears** | — | | | | not run | |
| S2 | Turning the switch on shows the row and still shows **no** system prompt — the prompt comes on the first press of the row | iOS shows its prompt once per install; getting this wrong is not recoverable without a reinstall | | | | not run | |
| S3 | Allow the prompt: contacts who are on Privio and discoverable appear, and **Add** puts one in the contacts list | Needs a second account with a verified number and "found by my number" on | | | | not run | |
| S4 | Refuse the prompt: the sentence says so and names the other ways in, and nothing is sent | Check the server log shows no `/v1/contacts/discover` for that press | | | | not run | |
| S5 | A real address book (300+ entries) matches in a reasonable time and the app stays responsive | The read is one platform call; the budget is 200 numbers per request | | | | not run | |
| S6 | **iOS limited access** (pick a few contacts): those are matched, and the app does not complain about the limited grant | iOS 18+ only | | | | not run | |

## 6d. Saved

Covered by `app/test/saved_test.dart` and the retention tests in
`storage.test.ts`. None of it has been on a phone. See [`saved.md`](saved.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| V1 | Account → Saved and the chat-list row open the **same** area, and a fresh account finds it from both before anything is in it | — | | | | not run | |
| V2 | A note written on one device appears on the other within seconds | Needs two devices on one account; a single-device account has nobody to sync to, which is correct and not a failure | | | | not run | |
| V3 | Write a note with the network off, turn it back on: it syncs and appears **once** on the second device | The duplicate is what the client id prevents; seeing it twice is the failure | | | | not run | |
| V4 | Save a photo, then open it on the second device **after the ordinary attachment window** has passed | Needs a server with a short `MEDIA_TTL_DAYS` to test in reasonable time | | | | not run | |
| V5 | Long-press a message that is under a disappearing timer: saving is refused with the reason, and nothing appears in Saved | Needs a chat with a timer set | | | | not run | |
| V6 | A Saved area with a few hundred entries scrolls and searches without stalling | The search is a loop over decrypted messages, as everywhere else in the app | | | | not run | |
| V7 | With a busy chat list — something pinned, something that just arrived — Saved is still the first row after the filter chips, and stays there after a force-quit and an account switch | Two accounts on one phone; the failure to watch for is the row sliding down as messages come in | | | | not run | |

## 6e. Disappearing messages

Covered by `app/test/disappearing_test.dart` and
`server/test/disappearing.test.ts`; none of it has been on a phone. The rows
below are the ones a suite cannot answer — two clocks, two devices, and a real
network. See [`disappearing-messages.md`](disappearing-messages.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Set a chat to 30 seconds on one phone: the other phone shows the notice, the chip reads `30s` on both, and a message sent afterwards disappears from **both** within a few seconds of each other | Two handsets; the gap is the two devices' clocks, not a bug unless it is minutes | | | | not run | |
| T2 | Settings → Privacy → Disappearing messages: set 1 hour, open a **new** chat — it follows the general setting and says so; a chat set by hand keeps its own value | | | | | not run | |
| T3 | Apply to existing chats: the preview counts match what changes, a chat with its own setting is untouched until the checkbox is ticked, and groups where you are not an admin are named as skipped | Needs a group you are only a member of | | | | not run | |
| T4 | Set a chat to Off explicitly, then change the general setting: that chat stays Off | This is the tri-state; a chat that starts deleting here is the failure that matters most | | | | not run | |
| T5 | Change the same chat's timer on two phones within a second of each other: both settle on the same value without either announcing back in a loop | Needs two devices on the same conversation | | | | not run | |
| T6 | Send a photo and a voice message with the network off, turn it back on: each starts its timer when it actually goes, not when it was recorded | | | | | not run | |
| T7 | Force-quit both apps for longer than the timer, reopen: what expired is gone from the history, the search and the media gallery, and no bubble flashes before it is cleaned | The flash before the sweep is the bug this row exists for | | | | not run | |
| T8 | Restore a backup taken before the messages expired: they do not come back | Needs a backup made with a timer running | | | | not run | |
| T9 | Sign out and into a second account on the same phone: it has its own general setting and its own chat timers | | | | | not run | |

## 6f. The accent on the loading screen

Covered by `app/test/splash_accent_test.dart`; none of it has been on a phone,
and the two rows that matter most — the first frame, and what the *system* draws
before Flutter starts — are ones no widget test can answer. See
[`brand-rollout.md`](brand-rollout.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Cold start with each of the eight accents: the splash mark, its tagline and the progress bar are all that colour, on black | Eight launches; the failure is one element left green | | | | not run | |
| C2 | Cold start with a non-green accent: **no green frame** before the chosen colour in the Flutter view | Needs a slow-motion screen recording to judge honestly | | | | not run | |
| C3 | The native splash: **iOS** black with nothing on it, **Android 11 and below** the same, **Android 12+** the green launcher icon first — expected, record what it looks like | Android 12+ draws its own splash from the launcher icon and cannot be recoloured per user | | | | not run | |
| C4 | Force-quit and relaunch, then switch accounts: the colour survives the restart and the second account gets **its own**, never the first's | Two accounts with different accents on one phone | | | | not run | |
| C5 | Reset to default: green again, and still green after a relaunch | | | | | not run | |
| C6 | With an app lock set: the lock screen and the sign-in still work, and the colour is right on both | The lock screen is what the splash hands over to | | | | not run | |

## 6g. Tapping an @name

Covered by `app/test/mentions_test.dart` and `app/test/mention_tap_test.dart`;
none of it has been on a phone, and text selection across a tappable span is
the row where the two platforms genuinely differ. See
[`mentions.md`](mentions.md).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 | Tap `@max` in a one-to-one chat, a group and a channel post: the right profile opens each time, by the account it belongs to | Needs a second account whose username you know | | | | not run | |
| M2 | Press and hold to select text **across** a mention, and copy: the copied text is exactly what was written, `@` and all | iOS and Android handle selection over a tappable span differently; this is the row to watch | | | | not run | |
| M3 | The tap target is comfortable for a thumb, and a tap just beside the name does **not** open a profile | | | | | not run | |
| M4 | From a group, tap a mention, choose Message, then go back twice: the group is where it was and the unsent draft is still in the field | | | | | not run | |
| M5 | Type `@` with the keyboard up: the suggestions sit above the field and are reachable without the keyboard covering them; picking one inserts the whole name | A short screen with a tall keyboard is the case to try | | | | not run | |
| M6 | Tap a name that does not exist, and one while in flight mode: a sentence each time, no profile, no crash | | | | | not run | |

## 6h. A group's picture and description

Covered by `app/test/group_profile_test.dart` and
`server/test/group_profile.test.ts`; none of it has been on a phone, and the
picker is the part no widget test reaches. See
[`security-model.md`](security-model.md#groups).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G1 | As an admin, set a group picture from the photo library: it appears in the group info, the chat header and the chat list, on both devices | Needs a second handset in the same group | | | | not run | |
| G2 | A member sees the picture and is offered **no** way to change it; the camera badge is absent | | | | | not run | |
| G3 | Write a description with umlauts and an emoji: it arrives intact on the other device and is cut off at 300 characters in the field | The system emoji picker is what a widget test cannot reproduce | | | | not run | |
| G4 | Remove the picture on one device: it disappears on the other after the next listing, and does not come back on a restart | The failure to watch for is a removal that undoes itself | | | | not run | |
| G5 | Rename the group afterwards: the picture and the description are still there | | | | | not run | |
| G6 | Join by a link on a fresh device: the picture is drawn **before** the group key arrives, while the name and description are still blank | This is the whole reason the picture is not sealed | | | | not run | |

## 6i. A bot in a group

Covered by `app/test/group_bots_test.dart` and
`server/test/bots_in_groups.test.ts`; none of it has been on a phone, and the
rows below need a bot that is actually running somewhere. See
[`bots.md`](bots.md#bots-in-groups).

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | Add a bot as an admin: the disclosure names what it can read, and after adding it has **no** rights — every switch is off | Needs a bot with a token and a poller running | | | | not run | |
| B2 | A member opens the same screen: they see the bot and its rights, and cannot change any of them | | | | | not run | |
| B3 | With **Send messages** on, write `/help` in the group: the bot receives it and answers; write an ordinary sentence: it receives nothing (check the bot's own log) | The bot's log is the evidence; the app cannot show what was not sent | | | | not run | |
| B4 | Turn on **Receive all new messages**: the second dialog appears, and afterwards every new message reaches the bot — but nothing from before | | | | | not run | |
| B5 | Remove the bot: the next message reaches it no more, and the removal dialog says what cannot be undone | | | | | not run | |
| B6 | Two bots in one group: `/help@one` reaches only that one, a bare `/help` reaches both | | | | | not run | |

## 7. App states

The table in `docs/notifications.md` says what each state is *supposed* to do.
This is where that gets checked against a phone.

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Foreground: a message appears immediately over the socket | — | | | | not run | |
| S2 | Backgrounded, process alive: a wake-up arrives and the message follows | iOS delivers `content-available` when it decides — minutes, or not at all | | | | not run | |
| S3 | Device locked: same as backgrounded, and the notification shows nothing about the sender or the content | — | | | | not run | |
| S4 | Process killed from the app switcher: Android shows a neutral notification and fetches when opened; iOS shows nothing until opened | No background isolate on Android yet; this is the documented behaviour, not a defect to file | | | | not run | |
| S5 | Force-stopped from Android settings: **nothing arrives** until the app is opened again | Android delivers no broadcast to a force-stopped app. No app can work around this | | | | not run | |
| S6 | Aggressive battery optimiser (Xiaomi, Huawei, Samsung "sleeping apps"): note what actually happens on that handset | Manufacturer behaviour, outside the app's control; record the model | | | | not run | |
| S7 | Reboot the phone, do not open the app, send a message: what arrives | Android needs the app opened once since install for its receivers to run | | | | not run | |

## 8. Connectivity

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| N1 | Send with the network off: the message queues, is marked as pending, and goes out on reconnect | — | | | | not run | |
| N2 | Aeroplane mode for five minutes with messages arriving: on reconnect everything arrives, once each | The queue is acknowledged, so redelivery is expected; duplicates on screen are not | | | | not run | |
| N3 | Kill the connection mid-send (aeroplane mode as the spinner shows): the message is either sent once or still pending — never sent twice | — | | | | not run | |
| N4 | Switch Wi-Fi → mobile data mid-conversation: the socket reconnects and nothing is lost | — | | | | not run | |
| N5 | Poor network (throttled, high latency): the app stays usable and does not lose messages | — | | | | not run | |
| N6 | Server restarted while the app is open: the socket reconnects on its own | — | | | | not run | |

## 9. Push edge cases

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | Refuse the notification permission: messages still arrive and are fetched, nothing is shown, and the app says so plainly | Neither platform shows its permission dialog twice | | | | not run | |
| P2 | Grant it later in system settings: notifications start appearing without reinstalling | — | | | | not run | |
| P3 | `libre`/`direct` with no distributor installed: the app says push is unavailable and still works while open | This is the expected state, not a failure | | | | not run | |
| P4 | `libre`/`direct` with ntfy installed and self-hosted: wake-ups arrive | — | | | | not run | |
| P5 | Server with **no** APNs/FCM credentials: the affected devices are woken only while the app is open, the server logs `skipped`, and nothing claims a push was sent | This is what the unconfigured-provider path is for | | | | not run | |
| P6 | Reinstall the app: the new push token replaces the old one and the old one stops being used | Apple and Google both reissue on reinstall | | | | not run | |
| P7 | Notification content: never a sender name, never a message body, on either platform | — | | | | not run | |
| P8 | iOS: the background fetch reports what it actually did — an app that always claims new data gets throttled by iOS | Only observable over days; note the trend rather than one push | | | | not run | |

## 10. Calls — not in this beta

Calls work while both apps are open. **A call to a closed app does not ring**,
on either platform, and that is a missing feature rather than a bug to file:

* **iOS** needs PushKit plus CallKit. iOS requires an app receiving a VoIP push
  to report an incoming call to CallKit *every time*; an app that does not is
  terminated, and repeat offenders lose the entitlement. The server side is
  ready (`voip_token`, `apns-push-type: voip`, the `.voip` topic) and refuses to
  send a call push to a device with no VoIP token, so nothing half-works in the
  meantime.
* **Android** needs ConnectionService, or at minimum a full-screen intent, to
  show a ringing screen from a background wake-up.

Both belong in a follow-up milestone of their own, with a device in hand from
the start. They must not be written speculatively alongside other work: the
failure mode of getting them wrong is the operating system killing the app.

| # | Test and expected result | Known platform limit | Build / commit | Device | OS | Result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| V1 | Call with both apps open and in the foreground: audio both ways | — | | | | not run | |
| V2 | Call while the callee's app is backgrounded but alive | Depends on the OS delivering the wake-up in time | | | | not run | |
| V3 | Call to a closed app: **expected not to ring** — record what actually happens | Follow-up milestone, see above | | | | not run | |

## 11. Sign-off

A beta is finished when every row says `pass`, `fail` or `blocked` — and a
`blocked` row names what would unblock it. Rows still saying `not run` are the
scope that was not tested, and belong in the release notes as exactly that.

| Section | Rows | Passed | Failed | Blocked | Not run |
| --- | --- | --- | --- | --- | --- |
| 1 Builds | 8 | 0 | 0 | 0 | 8 |
| 2 Account and session | 7 | 0 | 0 | 0 | 7 |
| 3 Revocation | 6 | 0 | 0 | 0 | 6 |
| 4 Android ↔ Android | 6 | 0 | 0 | 0 | 6 |
| 5 Android ↔ iPhone | 5 | 0 | 0 | 0 | 5 |
| 6 Groups and channels | 8 | 0 | 0 | 0 | 8 |
| 6b Profiles from a chat | 8 | 0 | 0 | 0 | 8 |
| 6b-2 Two names | 5 | 0 | 0 | 0 | 5 |
| 6c Address book | 6 | 0 | 0 | 0 | 6 |
| 6d Saved | 7 | 0 | 0 | 0 | 7 |
| 6e Disappearing messages | 9 | 0 | 0 | 0 | 9 |
| 6f Accent on the loading screen | 6 | 0 | 0 | 0 | 6 |
| 6g Tapping an @name | 6 | 0 | 0 | 0 | 6 |
| 6h Group picture and description | 6 | 0 | 0 | 0 | 6 |
| 6i A bot in a group | 6 | 0 | 0 | 0 | 6 |
| 7 App states | 7 | 0 | 0 | 0 | 7 |
| 8 Connectivity | 6 | 0 | 0 | 0 | 6 |
| 9 Push | 8 | 0 | 0 | 0 | 8 |
| 10 Calls | 3 | 0 | 0 | 0 | 3 |
| **Total** | **123** | **0** | **0** | **0** | **123** |

The four sections between 6 and 7 were missing from this table until the timer
rows were added — 34 rows of scope that the total silently left out. A summary
that undercounts what has not been run is worse than no summary.

Nothing in this table has been run. It is a plan, not a result.
