# iOS beta from Windows, with no Mac

Everything Apple needs a Mac for happens on GitHub's macOS runner. What is left
for you is a browser, and one optional stretch with a command prompt that is
not Xcode and never touches a phone.

The route:

```
  developer.apple.com   ─┐
  App Store Connect     ─┤  browser, on Windows: identifiers, an app record,
  App Store Connect API ─┘  an API key, internal testers
            │
            ▼
  GitHub → Settings → Secrets     four secrets, pasted once
            │
            ▼
  GitHub → Actions → "iOS signed build" → Run workflow
            │                              (upload: no, the first time)
            ▼
  a signed .ipa as a build artifact        ← proof the signing works
            │
            ▼
  Run workflow again with upload: yes      ← your decision, never automatic
            │
            ▼
  App Store Connect → TestFlight → your iPhone
```

**Read this first, in order.** Two of the steps cost money or make a build
visible to testers, and both are marked.

---

## 0. Before anything: GitHub Actions is not currently running

This has to be fixed by you, in the browser, and nothing in the repository can
work around it.

Since **2026-09-05** every workflow run in this repository has failed within
seconds without executing a step. The last green run was CI #80 (2026-09-05,
00:57 UTC); #81, twelve minutes later, failed after 3 seconds, and every run
since has failed the same way. The workflow files did not change at that
boundary, and the jobs are never assigned a runner — the API reports
`runner_id: 0`, there are no step records, and downloading the logs returns 404
because none were produced. That combination is an account-level cause, not a
repository one.

**This repository is private.** That matters twice over:

* Actions minutes for a private repository are billed against your account's
  included quota (2,000 minutes a month on Free, 3,000 on Pro).
* **macOS runners bill at ten times the Linux rate.** A run of the signed iOS
  build is roughly 20–35 minutes of wall clock, so **200 to 350 minutes** of
  quota. On a Free plan that is a tenth of the month per build.

So: go to **<https://github.com/settings/billing>** and look at Actions usage.
You will find one of three things.

| What you see | What it means | What to do |
| --- | --- | --- |
| Included minutes used up | Every run fails instantly, exactly as observed | Wait for the monthly reset, or set a spending limit above zero — **which costs money and is your decision** |
| No payment method / spending limit at $0 | Same symptom | Same choice |
| Actions disabled for the account | Same symptom | Re-enable it |

Two alternatives, so the choice is a real one:

* **Make the repository public.** Actions are free for public repositories,
  macOS runners included. It is also a publication decision — the code is
  AGPL-3.0, so nothing stops it, but it is not reversible in any meaningful
  sense and it is not mine to make. Nothing in this repository has been made
  public.
* **A self-hosted runner** is the usual escape, and it does not apply here: it
  would have to be a Mac.

Nothing below can run until this is resolved. Everything below can be *prepared*
before it is.

---

## 1. Apple, in the browser

You need a paid Apple Developer Program membership. You have one.

### 1.1 Register the App ID

<https://developer.apple.com/account/resources/identifiers/list>

* **+** → **App IDs** → **App**.
* Description: `Privio`.
* Bundle ID: **Explicit**, `app.privio.privio` — that is what the Xcode project
  is set to. If it is taken, pick your own (`com.yourname.privio`) and type it
  into the workflow's `bundle_id` box when you start a build; the workflow
  rewrites the project for that run.
* Capabilities: tick **Push Notifications**. Not optional — the app asks for the
  `aps-environment` entitlement, and signing fails if the App ID does not have
  the capability.
* Register.

### 1.2 Create the app record

<https://appstoreconnect.apple.com/apps> → **+** → **New App**

* Platform: iOS. Bundle ID: the one from 1.1. SKU: anything unique, `privio-1`.
* **Name must be unique across the entire App Store.** If "Privio" is taken,
  use something like "Privio Messenger" — this is only the store listing name;
  the name under the icon on your phone comes from the app itself and stays
  **Privio**.
* You are not submitting anything. An app record is what TestFlight hangs off.

### 1.3 Create an App Store Connect API key

<https://appstoreconnect.apple.com/access/integrations/api> → **Team Keys** →
**+**

* Name: `GitHub Actions`.
* Access: **App Manager**. Less than that and the runner cannot create signing
  certificates or upload builds.
* **Download the `.p8` file. Apple lets you download it once.** Keep it
  somewhere safe on your PC; you will paste its contents into a GitHub secret
  in step 2 and can then delete it if you like. It is a private key: do not mail
  it to yourself, do not put it in the repository, do not paste it into a chat.
* Note the **Key ID** (10 characters, shown in the row) and the **Issuer ID**
  (a UUID above the table, the same for every key on the team).

### 1.4 Find your Team ID

<https://developer.apple.com/account> → **Membership details** → **Team ID**,
ten characters like `A1B2C3D4E5`.

### 1.5 Set up internal testing

<https://appstoreconnect.apple.com> → your app → **TestFlight** → **Internal
Testing** → **+** next to Testers group.

* Create a group, call it `Internal`.
* Add yourself. You must exist under **Users and Access** first — as the account
  holder you already do.
* Internal testers get builds **without Beta App Review**, which is why this is
  the fast route to your own phone. Up to 100 people.

### 1.6 On the iPhone

Install **TestFlight** from the App Store and sign in with the same Apple ID.

---

## 2. GitHub secrets

<https://github.com/nfnc666/privio-messenger/settings/secrets/actions> → **New
repository secret**, four times. The names must match exactly.

| Secret | What to paste | Where it came from |
| --- | --- | --- |
| `APPSTORE_KEY_ID` | e.g. `2X9ABC3DEF` | 1.3 |
| `APPSTORE_ISSUER_ID` | e.g. `69a6de70-…-1f2e3d4c5b6a` | 1.3 |
| `APPSTORE_PRIVATE_KEY` | the **whole** contents of the `.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines | 1.3 |
| `APPLE_TEAM_ID` | e.g. `A1B2C3D4E5` | 1.4 |

To read the `.p8` on Windows: right-click → **Open with** → **Notepad**. It is a
text file. Select all, copy, paste into the secret box. The workflow checks for
the `BEGIN PRIVATE KEY` line and stops with a readable error if what arrived was
a filename or half a file.

A GitHub secret cannot be read back — not by you, not by me, not by a workflow
log. If you ever need to know what it was, make a new key and replace it. If one
ever leaks, revoke it at 1.3's page; that takes effect immediately.

**Nothing else in this repository holds a key.** The `.p8` reaches the runner
only through the secret, is written to a file that only the runner user can
read, and is deleted in a step that runs even if the job fails or is cancelled.

---

## 3. The first run: build only, no upload

<https://github.com/nfnc666/privio-messenger/actions/workflows/ios-testflight.yml>
→ **Run workflow**.

| Field | What to put |
| --- | --- |
| `api_url` | Your server, `https://…`. **https only** — iOS blocks plain HTTP, and the workflow refuses an `http://` address rather than building something that installs and never connects |
| `upload` | **no** |
| `bundle_id` | `app.privio.privio`, or yours from 1.1 |
| `build_number` | leave empty — the run number is used, and it only goes up |
| `xcode_version` | leave empty |

Then **Run workflow**, and watch it. Twenty to thirty-five minutes.

What you get: an artifact called `privio-ios-<number>` containing a signed
`.ipa`, at the bottom of the run's summary page.

**You cannot install that .ipa from Windows.** There is no supported way to put
an .ipa on an iPhone from a PC — that is what TestFlight is for. The point of
this run is to prove that signing works before anything is distributed. If it
succeeds, the hard part is done.

### About your server

The build talks to whatever `api_url` you gave it, and to nothing else. Without
a reachable Privio server the app installs and cannot register — there is no
demo mode and no fallback. Getting that server up is a separate job from this
document; `README.md` and `server/.env.example` cover it. `APNS_ENVIRONMENT` on
that server must be **production**, because a TestFlight build is a Release
build and Release builds use Apple's production push servers.

---

## 4. The second run: upload to TestFlight

Same form, `upload` set to **yes**. This is the step that puts a build in front
of testers, which is why it is never the default and never happens on a push.

The workflow validates the build with Apple first and then uploads it. After it
finishes:

1. **App Store Connect → TestFlight** shows the build as *Processing*. Five to
   thirty minutes, sometimes longer for a first build.
2. It will then say **Missing Compliance**. TestFlight asks whether your app
   uses encryption, and Privio does — end-to-end, which is the whole point.
   Answering it is a legal declaration about export rules, so it is yours to
   make and not something this repository should answer for you. Apple's
   questionnaire is in the browser next to the build; the relevant reading is
   Apple's "Export compliance overview" and, if you want to stop being asked on
   every build, the `ITSAppUsesNonExemptEncryption` key in `Info.plist` records
   the answer permanently. **It is deliberately not set in this repository.**
3. Once the answer is in, the build appears for your internal group.
4. On the iPhone: open TestFlight, the build is there, **Install**.

Nothing in this flow submits anything for App Store review, and TestFlight is
not the App Store.

---

## 5. When the certificate limit bites

The default path signs *automatically*: Xcode, using your API key, creates a
distribution certificate and a provisioning profile on the runner. It works
with zero setup, and it has one flaw — the runner is thrown away after every
run, so the next run creates **another** certificate. Apple allows a small
number of distribution certificates per account (typically two or three), and
when they are used up a build fails with:

> Maximum number of certificates generated

Two ways out.

**The quick one.** <https://developer.apple.com/account/resources/certificates/list>
→ revoke the unused `Apple Distribution` certificates. Nothing installed
breaks: a build that is already uploaded stays valid. Then run the workflow
again.

**The durable one.** Make one certificate yourself, keep it in a secret, and the
workflow will use it every time instead of making new ones. This needs a
command prompt on Windows — not Xcode, and no phone involved. Git for Windows
ships `openssl`; if `openssl version` is not found, use
`"C:\Program Files\Git\usr\bin\openssl.exe"` instead of `openssl` below.

```powershell
# 1. A key that stays on your PC, and a request Apple can sign.
openssl genrsa -out privio-dist.key 2048
openssl req -new -key privio-dist.key -out privio-dist.csr `
  -subj "/emailAddress=you@example.com/CN=Your Name/C=DE"
```

* Upload `privio-dist.csr` at
  <https://developer.apple.com/account/resources/certificates/add> →
  **Apple Distribution** → download `distribution.cer`.
* Create a profile at
  <https://developer.apple.com/account/resources/profiles/add> →
  **App Store Connect** distribution → your App ID → that certificate →
  download `Privio_AppStore.mobileprovision`.

```powershell
# 2. Certificate + key into one .p12, protected by a password you choose.
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -inkey privio-dist.key -in distribution.pem -out privio-dist.p12

# 3. Base64, because a GitHub secret holds text. PowerShell, one line each:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("privio-dist.p12")) | Set-Clipboard
# paste into the secret, then:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Privio_AppStore.mobileprovision")) | Set-Clipboard
```

(Use PowerShell's `[Convert]`, not `certutil -encode` — certutil wraps the
output in `BEGIN CERTIFICATE` lines that are not part of the data.)

Three more secrets:

| Secret | What to paste |
| --- | --- |
| `IOS_DIST_CERT_P12_BASE64` | the base64 of `privio-dist.p12` |
| `IOS_DIST_CERT_PASSWORD` | the password you chose in step 2 |
| `IOS_PROVISIONING_PROFILE_BASE64` | the base64 of the `.mobileprovision` |

The workflow notices all three and switches to manual signing on its own: it
imports the certificate into a keychain it creates for that run and deletes
afterwards, and it reads the profile's name out of the profile rather than
asking you for it. Delete `privio-dist.key` and the `.p12` from your PC once the
secrets are in, or keep them somewhere safe — they are the identity that signs
your app.

---

## 6. When something goes wrong

| What it says | What it is | What to do |
| --- | --- | --- |
| The run fails in seconds with no logs | Section 0 — no runner | Billing, not the code |
| `Secret … is not set` | A name is misspelled or missing | Section 2; names are case-sensitive |
| `does not look like a .p8 key` | The filename or a partial paste landed in the secret | Paste the whole file including BEGIN/END |
| `Maximum number of certificates generated` | Section 5 | Revoke, or move to manual signing |
| `No profiles for 'app.privio.privio' were found` | The App ID is not registered, or belongs to a different team | Section 1.1, and check `APPLE_TEAM_ID` |
| `Provisioning profile … doesn't include the aps-environment entitlement` | The App ID has no Push Notifications capability | Section 1.1, tick it, then re-run |
| `The bundle version must be higher than the previously uploaded version` | That build number is already in TestFlight | Re-run; the run number will be higher, or set `build_number` yourself |
| `Invalid Bundle. The bundle … does not support the minimum OS version` | Xcode/Flutter mismatch on the runner image | Pin `xcode_version` when starting the run |
| TestFlight shows *Missing Compliance* forever | Nobody answered the export question | Section 4, step 2 |
| The app installs and cannot connect | `api_url` was wrong, or the server is not reachable over HTTPS | Re-run with the right address |

---

## 7. What has not been verified

Stated plainly, because everything above is instructions and none of it is a
result:

* **The workflow has never run.** It cannot be run from here: this environment
  has no macOS, and the repository's Actions have not executed since
  2026-09-05.
* **The entitlements change has never been compiled.** `Runner.entitlements` and
  the three `CODE_SIGN_ENTITLEMENTS` lines in the Xcode project are written and
  unbuilt. They are what makes push work on the device; if they turn out to be
  what breaks the first build, the error will be one of the two entitlement
  rows in section 6.
* **No Apple credential exists in this repository or in this environment**, so
  no part of the signing path has been exercised against Apple.
* **Nothing has been uploaded anywhere**, no billing setting has been changed,
  no repository setting has been changed, and no workflow has been started.

The device beta checklist (`device-beta-checklist.md`) still has every row at
`not run`. Installing this build on your iPhone is what starts filling it in.
