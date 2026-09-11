# Channel links, and the page behind them

A Privio channel link is meant to be pasted into WhatsApp, printed on a poster,
or put on a website. Whoever taps it has usually never heard of Privio, so what
they get is a web page: what the channel is, and a button that opens it in the
app.

This document is the configuration that page needs, and — more usefully — the
list of what is **not** configured yet.

## What is not configured, as of writing

| Thing | State | What it costs |
|---|---|---|
| `privio.channel` | **not registered** | Links are built against the server's own hostname instead. They work. |
| App Store listing | **does not exist** | The page shows no App Store button. |
| Google Play listing | **does not exist** | No Play button. |
| APK download page | **does not exist** | No APK button. |
| `IOS_APP_ID` | unset | `apple-app-site-association` answers 404, so iOS does not verify the link and the button falls back to the web page. |
| `ANDROID_PACKAGE`, `ANDROID_CERT_FINGERPRINTS` | unset | `assetlinks.json` answers 404, same fallback on Android. |

None of these stop the pages working. They decide whether the **button** opens
the app rather than another page.

## The link shapes

```
https://<host>/houseoftrading    a public channel, by handle
https://<host>/+<code>           a private invitation
https://<host>/c/<code>          what every shipped build generates
```

A public link carries **no capability**: a handle is how a public channel is
searched for, so a link to one is its name. The old `/c/<code>` form put an
invite code into every public link, which meant a link posted on a website was a
capability sitting in a search index. It still resolves, because links already
pasted somewhere cannot be rewritten.

`/open/...` is the same path with a prefix, and it is the **only** shape the
app-link files claim. That separation is the whole design: the shared link shows
the page, and the button on the page hands the link to the app. Claiming the
share paths instead would mean the app swallowing every link before anybody saw
a page.

## Server configuration

| Variable | Meaning | Default |
|---|---|---|
| `PUBLIC_WEB_URL` | Absolute origin the pages live at, e.g. `https://privio.channel`. | empty — use the host the request arrived on |
| `APP_STORE_URL` | iOS listing. | empty — no button |
| `PLAY_STORE_URL` | Play listing. | empty — no button |
| `APK_DOWNLOAD_URL` | Direct download page. | empty — no button |
| `IOS_APP_ID` | `<team id>.<bundle id>`, e.g. `ABCDE12345.app.privio.privio`. | empty — file 404s |
| `ANDROID_PACKAGE` | e.g. `app.privio.privio`. | empty — file 404s |
| `ANDROID_CERT_FINGERPRINTS` | Comma-separated SHA-256 signing fingerprints. | empty — file 404s |

Empty means the feature is absent, never faked. A download button that leads to
a store listing which does not exist is worse than no button, and a
`apple-app-site-association` served with a placeholder team id is worse than a
404: Apple's CDN caches what it fetches for days, so a wrong file is a broken
link for a week after the right one is deployed.

`ANDROID_CERT_FINGERPRINTS` is plural on purpose. An app distributed through
Play App Signing has an upload certificate **and** the one Google re-signs with,
and this project also ships a directly-downloaded APK signed with a third. A
file naming only one verifies for some installs and silently fails for the rest.

## What has to happen outside this repository

### DNS and hosting

1. Register the domain. `privio.channel` is the name the code already uses, in
   `ChannelService.channelLinkHost` on the client and `PUBLIC_WEB_URL` on the
   server. **Confirm the `.channel` TLD is actually available** before treating
   the name as settled — the repo has assumed it twice without checking.
2. Point it at the Privio server. The pages are served by the API process, so
   there is no second host to run: one `CNAME` to the existing deployment.
3. Set `PUBLIC_WEB_URL` to the new origin and change `channelLinkHost` to match.
   The two have to agree, or a link built by one is not recognised by the other.

Until then, the pages work on the server's own hostname, and so do the links.

### Apple — and the order matters

**Universal Links are deliberately not configured in the entitlements yet.**
`com.apple.developer.associated-domains` is a *capability*, not a plain key:
adding it makes signing fail unless the App ID has Associated Domains enabled
and the provisioning profile was regenerated with it. CI builds iOS with
`--no-codesign` and would not catch that — the TestFlight workflow would, by
breaking. There is also nothing to point it at while the domain is
unregistered.

In this order, once the domain exists:

1. Enable **Associated Domains** on the App ID in the Apple Developer portal.
2. Regenerate the provisioning profile and update the CI secret that holds it.
3. Add to `app/ios/Runner/Runner.entitlements`, replacing the comment there:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
     <string>applinks:privio.channel</string>
   </array>
   ```

4. Set `IOS_APP_ID` on the server to `<team id>.<bundle id>`.
5. Run the TestFlight workflow and confirm it still signs before relying on it.

Apple fetches `https://<host>/.well-known/apple-app-site-association` directly —
no redirects, `application/json`, and no `.json` extension. The server serves it
exactly that way.

Until all of that: **`privio://` works today**. It is in `Info.plist`, needs no
domain, no verification file and nothing from Apple, and it is what actually
opens a link on an installed device.

### Android

The intent filters are already in the manifest — both of them:

* `privio://` — needs nothing, works on install.
* `https://privio.channel/open/` with `android:autoVerify="true"`.

The second fetches `assetlinks.json` at install time. While that answers 404,
verification simply fails and the link opens in a browser, which shows the
invite page, which has a button. That is a working fallback, not a broken state.

To finish it:

1. Set `ANDROID_PACKAGE` and every SHA-256 signing fingerprint the app ships
   under. `keytool -list -v -keystore <store>` prints them; Play Console shows
   the one Google re-signs with under **App signing**.
2. Change the `android:host` in the manifest if the domain is not
   `privio.channel`.

Verify with `adb shell pm get-app-links <package>` on a device: anything other
than `verified` means the file and the fingerprints disagree.

## Opening a link never joins

Tapping an invitation shows the channel with a **Join** button. It does not put
anybody in a channel — a person who taps a link out of curiosity should not
find their name in a stranger's member list. Somebody who is already a member
lands in the channel itself.

This was not always true: opening an invite link used to join immediately,
inside the same call that resolved it.

A link that arrives when the app is locked, or on a device with no account,
**waits**. It is held in a controller rather than in a route, so it survives
the passcode screen, signing up and the activation step, and opens once there
is somewhere to put it.

## After installing

Open the same link again. Privio does not try to work out which invitation
brought somebody to a store and does not claim to: there is no reliable way to
carry a link through an install, and the page says so rather than pretending.

## What the page discloses

A **public** channel's page shows its title, description and subscriber count,
and carries Open Graph tags so a messenger can draw a preview. All three are
already plaintext in the database because discovery needs them; the page
discloses nothing that search does not.

A **private** invitation's page shows nothing about the channel — not its name,
not its size, not a word of it. The server does not have the name: it is sealed
with the channel key. The link preview is neutral and identical for every
private invite, because a preview is fetched by whichever messenger the link was
pasted into, and anything in it travels to a third party without the sender
choosing to send it. The page is `noindex`, and every private page is served
`private, no-store`.

Both pages fetch **nothing**: no script, no font, no analytics, no image from
anywhere but this server. A private invite's token is in the URL, and every
external request a page makes carries that URL in a `Referer` header.
`Referrer-Policy: no-referrer` says so, and a `default-src 'none'` CSP makes it
structural rather than a promise.

**Opening a page never spends an invitation.** A preview bot fetches it, and so
does everybody the link was forwarded to; either would burn a one-use invitation
before its person arrived. The counter moves inside the transaction that adds
the member, and nowhere else.
