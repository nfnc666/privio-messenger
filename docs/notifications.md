# Notifications

The rule the whole design answers to: **a push carries no content.** It is a
wake-up. The device connects and pulls its envelopes over its own TLS
connection, so whoever forwards the ping learns that a device was pinged, and
nothing else — not who wrote, not how many, not what.

That rule is what makes it possible to offer more than one path without
arguing about which is more private. They differ in latency, battery and who
has to be trusted to stay up; none of them differ in what they can read.

## The paths

| Path | Who forwards it | In the APK | Woken while closed |
| --- | --- | --- | --- |
| Socket | Nobody | Nothing | No — only while running |
| UnifiedPush | A distributor app the user chose | Nothing proprietary | Yes |
| FCM | Google | Play services | Yes |
| APNs | Apple | Nothing extra | Yes |

`PrivioEdition.pushProvider` decides which is even offered. Libre and the
direct APK say `unifiedpush`; Play says `fcm`; the App Store build says `apns`.
The store builds have nothing to choose and are not asked.

## UnifiedPush

The user installs a distributor — ntfy, NextPush, Sunup — which holds one
connection for every app that uses it and hands each a URL. Privio registers
that URL with the server, and the server POSTs to it.

```
  Privio  ──register──►  distributor app  ──►  returns an endpoint URL
     │
     └──PUT /v1/devices/current/push { provider: "unifiedpush", token: <url> }
                                     │
                                     ▼
  something arrives  ──►  server POSTs "." to the endpoint
                                     │
                                     ▼
                          distributor wakes Privio
                                     │
                                     ▼
                     Privio fetches its envelopes over TLS
```

Why it is worth having: one connection for every app is better for battery
than each app holding its own, the latency is comparable to FCM, and the
distributor can be self-hosted — at which point nobody outside the user's own
infrastructure is in the path at all. On a public distributor, that operator
learns the timing of pings to an opaque topic. That is a real disclosure, and
it is the reason the choice is the user's rather than the default.

### The endpoint is an address, not a token

This is the part that needed care. An APNs or FCM token is a handle a vendor
resolves. A UnifiedPush endpoint is a URL **this server will make an outbound
request to**, chosen by whoever controls a device — which is a server-side
request forgery unless it is guarded.

`server/src/util/outbound.ts` does the guarding:

* HTTPS only, and no credentials in the URL.
* The host must not be, or resolve to, a private, loopback, link-local, CGNAT
  or multicast address. `169.254.169.254` — the cloud metadata service — is
  covered by that, and so is `::ffff:127.0.0.1`, which the URL parser hands
  back as `::ffff:7f00:1`: the check reduces every form to the same sixteen
  bytes before judging it.
* Checked when the endpoint is registered, so a bad one fails while someone is
  looking at it, and again before every send, because a name that resolved
  publicly last week may not today.
* Redirects are refused. Following one lands the relay on an address nothing
  validated.
* `UNIFIEDPUSH_ALLOWED_HOSTS` narrows it to named distributors for a
  deployment that would rather not reach arbitrary hosts. Empty — the default —
  means any public host, which is what makes self-hosting a distributor work.

What is **not** closed: the gap between resolving a name and connecting to it.
A name can change its answer in between. Closing it properly means connecting
to a pinned address while carrying the hostname separately for TLS, which is
more machinery than a wake-up ping justifies. It is written here rather than
left to be found.

## A wake-up cannot fail a send

Worth stating because it stopped being obvious the moment a provider became
something that makes a network call. Before UnifiedPush the sender was a
logging stub: instant, and incapable of failing. Now it does DNS and an HTTPS
POST to an address someone else chose.

Two things follow, and both are enforced in `DeliveryService.wake`:

* **Every failure is swallowed.** A distributor that has gone away, a URL that
  stopped resolving publicly, a vendor refusing a stale token — none of that
  means the message did not arrive, because it was stored before any of this
  ran. Letting it through would turn a delivered message into an error the
  sender sees and retries. Unhandled, it would also take the process down.
* **The send does not wait past one second.** Otherwise registering an endpoint
  that black-holes would cost everyone who messages you the full request
  timeout, which is a cheap thing to do to other people. Stragglers finish on
  their own; they can no longer reject, so nothing is waiting on them.

## The fallback

No distributor installed means the socket, which is what every build did
before: messages arrive while Privio is open, and not otherwise. The settings
screen says so plainly rather than showing a switch that silently does nothing.

The same rule cleared the rest of that screen. It used to carry five toggles —
message notifications, group notifications, sound, vibration, show preview —
none of which set anything: sound, vibration, the light and what shows on the
lock screen are the operating system's own settings for Privio, and an app
cannot decide them from the inside. The delivery path is the one thing on that
screen Privio actually owns, so it is the one thing left on it.

An Android foreground service holding that socket open — a persistent
notification, and an exemption from battery optimisation — is the other way to
be woken without a third party. It is not implemented. It is a real option and
it belongs here as one, not as a promise.

## State of it

Written and tested without a phone; **nothing below has been run on a device**,
because this was built in an environment with no Android SDK, no macOS and no
handset. Every "works" here means "the logic is exercised by a test"; every
claim about what a phone actually does is marked as untested and belongs in the
test plan at the end.

| Piece | Where | State |
| --- | --- | --- |
| Endpoint validation, routing, wake-up senders | `server/src/services/push.ts` | Tested |
| APNs and FCM senders, dead-token handling | same | Tested against injected transports |
| Call urgency, dropping dead tokens | `server/src/services/delivery.ts` | Tested |
| Registration, renewal, sign-out, permission states | `app/lib/services/wake_up.dart` | Tested |
| Late and duplicate call signals | `app/lib/services/call_service.dart` | Tested |
| UnifiedPush bridge and receiver | `app/android/app/src/libre/…` | **Never compiled** |
| FCM bridge and service | `app/android/app/src/play/…` | **Never compiled** |
| APNs registration and wake | `app/ios/Runner/PushBridge.swift` | **Never compiled** |
| CallKit / ConnectionService ringing | — | **Not written** |

### The two things deliberately not written

**A background Dart isolate.** On Android, a wake-up that arrives while the
process is dead currently posts a neutral notification and stops there; the
fetch happens when the app is opened. Fetching from a dead process means running
a headless `FlutterEngine` with a registered entry point, and that is a piece of
machinery whose failure mode is silence — exactly the thing that cannot be
verified by reasoning about it. It is specified here and left for someone with a
device.

**CallKit and PushKit, and ConnectionService.** iOS will launch a killed app for
a VoIP push, and requires in exchange that the app report an incoming call to
CallKit *every single time* — an app that does not is terminated by the system,
and repeat offenders lose the entitlement. That is not a rule to learn from a
first attempt on a phone somebody else is holding. The server side is ready for
it (`voip_token`, `apns-push-type: voip`, the `.voip` topic) and refuses to send
a call push to a device with no VoIP token, so nothing half-works in the
meantime: a call simply does not ring while the app is closed on iOS.

## What is actually promised, per platform and edition

Nothing here promises delivery in a state where the operating system prevents
it. The honest table:

| State | libre / direct (Android, UnifiedPush) | play (Android, FCM) | appstore (iOS, APNs) |
| --- | --- | --- | --- |
| App in the foreground | Socket. Immediate | Socket. Immediate | Socket. Immediate |
| App backgrounded, process alive | Wake-up → fetch | Wake-up → fetch | Wake-up → fetch, **when iOS decides** |
| Device locked | Same as backgrounded | Same as backgrounded | Same as backgrounded |
| Process killed by the system | Neutral notification; fetch on open | Neutral notification; fetch on open | **Nothing until opened** |
| Force-stopped by the user | **Nothing.** Android delivers no broadcast to a force-stopped app until it is opened again | **Nothing**, same reason | Not applicable — iOS has no force-stop with this effect; a swipe from the app switcher still allows a push |
| Connection lost and restored | Socket reconnects and drains; the watermark stops anything arriving twice | Same | Same |
| Notifications refused | Messages still arrive and are fetched. **Nothing is shown**, and a call does not ring | Same | Same |
| Signed in on several devices | Every device is woken separately; each has its own token and fetches its own copy | Same | Same |

Three of those deserve saying out loud rather than leaving in a table:

* **Force-stop is final.** "Force stop" in Android's settings puts the app in a
  stopped state, and the system delivers no broadcast or FCM message to it until
  a person launches it again. No app can work around this and none should claim
  to. The same is true of some manufacturers' aggressive battery managers, which
  is a real and widely-reported problem outside the app's control.
* **iOS background pushes are a request, not an instruction.** A
  `content-available` push is delivered when iOS decides, weighted by how much
  the user opens the app and how the battery is doing. It can be minutes and it
  can be never. This is why a *call* uses PushKit instead — and why, until
  PushKit is implemented here, calls to a closed iOS app do not ring.
* **A refused permission costs the notification, not the message.** The push
  still wakes the process and the envelopes still arrive; nothing appears on
  screen. The app says exactly this rather than showing a warning triangle, and
  it does not re-prompt — neither platform shows its dialog twice.

## What is still needed to finish it

Nothing on this list can be produced from a source tree; each needs an account,
a certificate or a physical device.

| Needed | For | Why it cannot be done here |
| --- | --- | --- |
| Apple Developer account, APNs `.p8` key, key id, team id | `appstore` | Signing keys, issued to an enrolled account |
| The `voip` background mode and a PushKit entitlement | iOS calls | Part of the signed provisioning profile |
| A Firebase project and `app/google-services.json` | `play` | Per-project configuration; deliberately not in this repository |
| An FCM service-account key | The server's `FcmSender` | A credential. It belongs in the environment, never in a commit |
| An Android phone and an iPhone | All of it | See the test plan below |
| A UnifiedPush distributor (ntfy or similar) | `libre` / `direct` | An app the tester installs |

Credentials go in the server's environment. There is no place in this repository
where one belongs, and nothing here reads one from a file.

## Testing it on a phone

Roughly forty minutes per platform. The point of writing it down is that the
interesting cases are the ones nobody thinks to try.

### Both platforms, first

1. Run a server the phone can reach, and register two accounts on two devices.
2. Sign in on the phone under test. Settings → Notifications should show which
   path this build uses.
3. Send a message from the other device with Privio **open**. It should appear
   immediately — this is the socket, and it proves the setup before push is in
   the picture at all.

### Android, `libre`

4. Install ntfy from F-Droid. Settings → Notifications → the UnifiedPush option
   should now be offered; before installing it, it should say plainly that there
   is nothing to register with.
5. Turn it on. Expect a distributor prompt, then a registered endpoint.
6. Background Privio. Send a message. **Expect:** a neutral notification saying
   only "You have new activity" — no name, no preview, no count.
7. Lock the phone and repeat. Same result on the lock screen.
8. Swipe Privio out of the recents list and repeat. Same result.
9. Settings → Apps → Privio → **Force stop**, then send. **Expect nothing.**
   This is the documented limit, and seeing it is the point of the step.
10. Turn Privio's notifications off in system settings. Send a message, then
    open Privio. **Expect:** nothing on screen, and the message present when
    opened. The Notifications screen should explain exactly that.
11. Aeroplane mode for two minutes while three messages are sent; then back on.
    **Expect:** all three, each once.
12. Sign out. Confirm on the server that `push_token` is null for that device.

### Android, `play`

Same list, minus steps 4 and 5 — registration happens on sign-in. Additionally
try a device or emulator image **without** Play services: the app should say it
cannot be woken while closed, rather than failing silently.

### iOS, `appstore`

Same list, minus the distributor. Two differences to watch for:

* Step 6 may take noticeably longer than on Android, and occasionally not
  arrive at all until the app is opened. That is the documented iOS behaviour,
  not a bug to chase.
* Step 9 has no equivalent. Swiping the app away in the switcher does **not**
  stop pushes on iOS.

### Calls

13. With Privio open on both devices, place a call. It should ring, answer,
    connect and hang up. (This path is covered by tests and should already work.)
14. Background the callee and call again. **Today: it does not ring** on iOS,
    and on Android it produces the neutral notification. This is the gap that
    CallKit and ConnectionService close.
15. The one to try deliberately: put the callee in aeroplane mode, call, and
    hang up after five seconds. Bring the callee back online. **Expect:** a
    missed call in the log and **no ringing**. A call that is over stays over —
    this is tested, and it is worth confirming on a real queue.
