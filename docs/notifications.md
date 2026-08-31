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

An Android foreground service holding that socket open — a persistent
notification, and an exemption from battery optimisation — is the other way to
be woken without a third party. It is not implemented. It is a real option and
it belongs here as one, not as a promise.

## State of it

Working and tested: everything on the server. The endpoint validation, the
sender, the routing between providers, and the checks above have tests in
`server/test/push.test.ts`.

Working, untested on a device: the Dart side — the delivery preference, the
registration flow, and what the settings screen shows. Its tests run without a
phone.

**Not written: the Android half.** `ChannelPushDistributor` talks over a method
channel to a native implementation that does not exist yet, so on a real phone
today every call answers "no distributor" and the app stays on its socket. That
is a deliberate seam, not a stub pretending to work: the channel's absence and
an uninstalled distributor are the same answer, and the app is honest in both
cases.

Three methods have to exist behind `app.privio/unifiedpush`:

| Method | Returns | Does |
| --- | --- | --- |
| `isAvailable` | `bool` | Whether any distributor is installed and reachable |
| `register` | `String?` | Registers and yields the endpoint URL, or null if declined |
| `unregister` | — | Tells the distributor to forget this app |

### The dependency, and the shape it actually has

The UnifiedPush Android connector is `org.unifiedpush.android:connector`, and
it **is** on Maven Central — `3.3.5` is the current release, with the `.aar`
present. So it belongs in `libreImplementation`, and F-Droid can fetch it like
any other dependency. (An earlier note here worried that the library was
JitPack-only, because that is what its README advertises. That was wrong, and
it is corrected rather than quietly deleted: JitPack would have been a problem,
Maven Central is not.)

```kotlin
// android/app/build.gradle.kts — the Libre flavour only.
libreImplementation("org.unifiedpush.android:connector:3.3.5")
```

One thing to know before writing the platform side, because it is not what the
Dart interface's shape suggests: **the endpoint does not come back from
`register()`.** The connector's `UnifiedPush.register(...)` starts a
conversation with the distributor, and the endpoint arrives later on a
broadcast, at the app's receiver. So the native half has to hold the pending
method-channel result until that callback fires — with a timeout, so a
distributor that never answers does not leave the Dart side waiting forever —
or the interface has to grow an event channel instead.

The Dart contract is still implementable as written; it just puts that work on
the native side. That is the right place for it: nothing above the channel
should have to know that this protocol is asynchronous underneath.

Also worth checking against the pinned version rather than the library's
`main` branch: the API is mid-rename there (`registerApp` → `register`,
`unregisterApp` → `unregister`), so code written from what is on `main` may not
compile against 3.3.5.

The Kotlin itself is still not written, and deliberately so. There is no
Android SDK on the machine this was built on, and the connector's released
sources could not be read from here either — only its `main` branch, which is
mid-rename. Committing Kotlin nobody has compiled, against an API read from the
wrong branch, into the tree F-Droid builds from is the one mistake that would
stay invisible until it broke for everyone. The seam holds until someone can
run `flutter build apk --flavor libre` and watch it go green.

Also not written: APNs and FCM adapters. `LoggingPushSender` records the intent
and sends nothing, which is why the store builds are not offered a choice yet
either.
