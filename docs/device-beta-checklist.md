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
| One iPhone, physical | A simulator has no APNs at all | Held by the maintainer |
| A reachable server with a real TLS certificate | The client pins and refuses plain HTTP | Not set up |
| APNs key (`.p8`, key id, team id, topic) | Otherwise iOS pushes are `skipped`, not sent | Not held |
| FCM service-account key | Otherwise Play-edition pushes are `skipped`, not sent | Not held |
| A UnifiedPush distributor (ntfy, NextPush, Sunup) | The `libre`/`direct` path has no push without one | Not installed |
| An Apple developer account | An iOS build cannot be installed on a handset without one. No Mac needed — see [`ios-testflight.md`](ios-testflight.md) | Account held; nothing configured yet |

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
| B4 | The **iOS signed build** workflow produces a signed `.ipa` — Actions → *iOS signed build* → Run workflow, `upload: no`. See [`ios-testflight.md`](ios-testflight.md) | Needs no Mac; needs the four App Store Connect secrets and a working Actions account | | | | not run | |
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
| 1 Builds | 7 | 0 | 0 | 0 | 7 |
| 2 Account and session | 7 | 0 | 0 | 0 | 7 |
| 3 Revocation | 6 | 0 | 0 | 0 | 6 |
| 4 Android ↔ Android | 6 | 0 | 0 | 0 | 6 |
| 5 Android ↔ iPhone | 5 | 0 | 0 | 0 | 5 |
| 6 Groups and channels | 8 | 0 | 0 | 0 | 8 |
| 7 App states | 7 | 0 | 0 | 0 | 7 |
| 8 Connectivity | 6 | 0 | 0 | 0 | 6 |
| 9 Push | 8 | 0 | 0 | 0 | 8 |
| 10 Calls | 3 | 0 | 0 | 0 | 3 |
| **Total** | **63** | **0** | **0** | **0** | **63** |

Nothing in this table has been run. It is a plan, not a result.
