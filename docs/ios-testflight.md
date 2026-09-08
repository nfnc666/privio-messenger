# iOS beta from an iPhone, with no computer at all

Everything Apple normally needs a Mac for happens on GitHub's runners. What is
left for you is Safari on the phone you are going to install the app on.

No Xcode. No terminal. No `openssl` on a laptop you do not own. The signing
key is generated inside a GitHub Actions run and goes straight into this
repository's secrets, so it exists only in the two places it should: Apple's
records, and GitHub's encrypted storage.

```
  Safari, on the iPhone
    ├─ developer.apple.com          nothing to do here — the setup run does it
    ├─ appstoreconnect.apple.com    an app record, an API key, a tester group
    └─ github.com                   four secrets pasted in, two buttons pressed
                │
                ▼
  Actions ▸ "iOS signing setup"     Linux runner. Makes the key, gets the
                │                   certificate and profile from Apple, writes
                │                   them back as secrets. Once.
                ▼
  Actions ▸ "iOS signed build"      macOS runner. upload: no ⇒ a signed .ipa
                │                   upload: yes ⇒ TestFlight
                ▼
  TestFlight, on the iPhone         Install.
```

**Read section 0 first.** Actions does not currently run at all, and that is
not something this repository can fix.

---

## 0. Actions runs again — and what being public changed

For two days it did not. Between **2026-09-05 and 2026-09-07** every workflow
run failed within seconds without executing a step: no runner assigned
(`runner_id: 0`), no step records, 404 for the logs because none were produced.
That is an account-level cause, and on a private repository it usually means
Actions minutes.

**The repository is public now, and that fixed it.** Public repositories get
Actions minutes free, macOS runners included — so nothing below costs anything,
and no spending limit has to be raised. The first run after the change (CI #147)
was assigned a real runner and went green.

Two consequences to know before you start a build:

* **Logs and artifacts are readable by anyone.** That includes the signed `.ipa`
  this workflow uploads. It is a signed build of your app, and it cannot be
  installed by a stranger — an App Store build only runs on devices Apple lets
  it run on — but it is public. If that is not what you want, delete the
  artifact after a run, or set the repository back to private and read the
  billing paragraph below.
* **Your secrets are still yours.** They are not readable in a log, a fork's
  pull request gets none of them, and both workflows here are start-by-hand
  only, which requires write access to the repository. Nothing changed about
  that when the repository became public.

If you make it private again: minutes are metered (2,000 a month on Free, 3,000
on Pro) and **macOS bills at ten times the Linux rate**, so a signed build is
200–350 minutes of quota. The signing setup runs on Linux and costs about ten.

---

## Working on the phone: three things worth knowing first

**Ask for the desktop site.** App Store Connect and the Apple developer portal
have mobile layouts that hide the buttons you need. In Safari: **aA** in the
address bar → **Request Desktop Website**. Do it for `appstoreconnect.apple.com`,
`developer.apple.com` and `github.com`. Under Settings → Safari → Request
Desktop Website you can make it the default per site so it sticks.

**Downloads land in Files.** Safari's download arrow puts files in
*On My iPhone → Downloads* (or iCloud Drive → Downloads).

**Getting a downloaded file's text onto the clipboard.** You will need this
exactly once, for Apple's `.p8` key. iOS will not let you select text inside an
unknown file type, so use the built-in **Shortcuts** app:

1. Shortcuts → **+** (new shortcut).
2. **Add Action** → search *Get File* → add **Get File** (from Files). Tap the
   action and turn **Show Document Picker** on.
3. **Add Action** → search *Get Text* → add **Get Text from Input**.
4. **Add Action** → search *Clipboard* → add **Copy to Clipboard**.
5. Name it "Copy file text", done. Run it, pick the file, and the whole text is
   on the clipboard.

(The fallback, if you would rather not build a shortcut: in Files, long-press
the file → **Rename** → change the ending from `.p8` to `.txt`, then tap it —
iOS will show it as text.)

---

## 1. Apple, in Safari

You need a paid Apple Developer Program membership. You have one.

Notice what is **not** in this section: no certificate, no provisioning
profile, no App ID. The setup workflow in section 3 creates all three through
Apple's API. There is nothing to download and nothing to sign.

### 1.1 An App Store Connect API key

<https://appstoreconnect.apple.com/access/integrations/api> → **Team Keys** →
**+**

* Name: `GitHub Actions`.
* Access: **App Manager**. Anything less cannot create certificates or upload
  builds.
* **Download the `.p8`. Apple allows that once.** It goes to Files. Use the
  shortcut above to copy its text when you get to section 2.
* Note the **Key ID** (10 characters, in the row) and the **Issuer ID** (a UUID
  above the table, the same for every key on the team). Both are on screen; you
  can copy them by long-pressing.

This key is the credential that lets a runner act on your Apple account. It is
also the one to revoke, on this page, if anything ever looks wrong — revoking
takes effect immediately and breaks nothing that is already installed.

### 1.2 The app record

<https://appstoreconnect.apple.com/apps> → **+** → **New App**

* Platform iOS, bundle ID `app.privio.privio` (or your own — whatever you use,
  type the same thing into both workflows later), SKU anything unique.
* **The name has to be unique across the whole App Store.** If "Privio" is
  taken, use "Privio Messenger" or similar. That is the store listing name only
  — the name under the icon on your phone comes from the app and stays
  **Privio**.
* This is not a submission. TestFlight needs an app record to hang off.

> The bundle ID drop-down here only lists identifiers that already exist. If
> yours is not in it, run the signing setup (section 3) first — it registers
> the identifier — then come back and create the app record.

### 1.3 A tester group with you in it

Your app → **TestFlight** → **Internal Testing** → **+** next to Testers.

* Create a group called `Internal`, add yourself. As the account holder you are
  already a user, so you can be added straight away.
* Internal testers get builds **without Beta App Review** — that is what makes
  this the short route to your own phone.

### 1.4 TestFlight on the phone

Install **TestFlight** from the App Store, sign in with the same Apple ID.

---

## 2. Four secrets, in the GitHub web UI

<https://github.com/nfnc666/privio-messenger/settings/secrets/actions> → **New
repository secret**. Names must match exactly.

| Secret | What goes in it |
| --- | --- |
| `APPSTORE_KEY_ID` | the Key ID from 1.1, e.g. `2X9ABC3DEF` |
| `APPSTORE_ISSUER_ID` | the Issuer ID from 1.1, a UUID |
| `APPSTORE_PRIVATE_KEY` | the whole text of the `.p8`, `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` included — use the shortcut from above |
| `SIGNING_ADMIN_TOKEN` | a GitHub token, made in the next paragraph |

**The token.** The setup workflow writes secrets back into this repository, and
the token a workflow gets by default deliberately cannot do that. Make one at
<https://github.com/settings/personal-access-tokens/new>:

* **Fine-grained**, expiring in 7 days — it is needed for one run.
* Resource owner: you. Repository access: **Only select repositories** →
  `privio-messenger`.
* Permissions → Repository permissions → **Secrets: Read and write**. That is
  the only one to change; Metadata comes with it automatically.
* Generate, copy, paste into the `SIGNING_ADMIN_TOKEN` secret.
* **Revoke it after the setup run.** It is the one credential here that can
  overwrite the others.

A GitHub secret cannot be read back afterwards — not by you, not by me, not in
a log. If you lose one, make a new key and replace it.

---

## 3. Run "iOS signing setup" — once

<https://github.com/nfnc666/privio-messenger/actions/workflows/ios-signing-setup.yml>
→ **Run workflow**.

| Field | Value |
| --- | --- |
| `bundle_id` | `app.privio.privio`, or yours |
| `profile_name` | `Privio App Store` |
| `revoke_oldest` | **no** |

About ten minutes on a Linux runner. What it does, in order:

1. Generates a 2048-bit RSA key and a certificate request **on the runner**.
2. Registers the bundle identifier with Apple if it does not exist, and turns
   on **Push Notifications** for it — without that capability the profile
   carries no `aps-environment` and signing fails with an error that names an
   entitlement rather than a checkbox.
3. Asks Apple for a distribution certificate for that request.
4. Creates the App Store provisioning profile for the identifier and the new
   certificate, replacing any earlier profile of the same name — a profile is a
   snapshot of a certificate list, so one made for a replaced certificate is not
   repairable.
5. Packs key and certificate into a `.p12` with a random password, and writes
   `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
   `IOS_PROVISIONING_PROFILE_BASE64` and `APPLE_TEAM_ID` into this repository's
   secrets. The team id is read back from Apple rather than typed.
6. Deletes every working copy, whether it succeeded or failed.

The run summary says what Apple now holds — identifiers, serial numbers,
expiry dates. No key, certificate body or profile body is ever printed.

**If it stops with "Apple already holds 3 distribution certificates".** That is
the account limit, and it refuses rather than revoking something quietly: a
certificate you revoke stops signing everywhere, including on machines that
have nothing to do with this repository. Either revoke one yourself at
<https://developer.apple.com/account/resources/certificates/list>, or re-run
with `revoke_oldest: yes` if you are sure the oldest one is unused.

Then **revoke `SIGNING_ADMIN_TOKEN`** at
<https://github.com/settings/personal-access-tokens>. Nothing needs it again
unless you re-run the setup.

---

## 4. Run "iOS signed build" — upload off

<https://github.com/nfnc666/privio-messenger/actions/workflows/ios-testflight.yml>
→ **Run workflow**.

| Field | Value |
| --- | --- |
| `api_url` | your server, **https only** — iOS blocks plain HTTP, and the workflow refuses an `http://` address rather than building something that installs and never connects |
| `upload` | **no** |
| `bundle_id` | the same identifier as in section 3 |
| `build_number` | empty — the run number is used, and it only goes up |
| `xcode_version` | empty |

Twenty to thirty-five minutes. It picks up the certificate and profile the
setup run stored, imports them into a keychain it creates for the run and
deletes afterwards, archives, and exports a signed `.ipa` as an artifact.

**That artifact cannot be installed from an iPhone**, and there is no way to
make it installable outside TestFlight. This run exists to prove the signing
works before anything is distributed. If it goes green, the hard part is done.

### The server

The build talks to whatever `api_url` you gave it and to nothing else. Without
a reachable Privio server the app installs and cannot register — there is no
demo mode. That server also needs `APNS_ENVIRONMENT=production`, because a
TestFlight build is a Release build and Release builds use Apple's production
push servers. Setting one up is a separate job; `README.md` and
`server/.env.example` cover it.

---

## 5. Run it again with upload: yes

Same form, `upload` set to **yes**. This is the step that puts a build in front
of testers, which is why it is never a default and never happens on a push.

Afterwards, in App Store Connect on the phone:

1. **TestFlight** shows the build as *Processing* — five to thirty minutes,
   longer for a first build.
2. Then it says **Missing Compliance**. TestFlight asks whether the app uses
   encryption. Privio does, end-to-end, which is the whole point of it.
   Answering is an export-control declaration and is yours to make, not
   something this repository should answer on your behalf; Apple's questionnaire
   is next to the build. (The `ITSAppUsesNonExemptEncryption` key in
   `Info.plist` records an answer permanently and is deliberately not set here.)
3. The build then appears for your internal group.
4. TestFlight app → **Install**.

Nothing in this submits anything for App Store review. TestFlight is not the
App Store.

---

## 6. When something goes wrong

| What it says | What it is | What to do |
| --- | --- | --- |
| A run fails in seconds with no logs | No runner was assigned — the outage in section 0 | Check Actions is enabled and, on a private repository, that minutes are left |
| `Secret … is not set` | A name is misspelled or missing | Section 2; names are case-sensitive |
| `does not look like a .p8 key` | A filename, or half a file, landed in the secret | Copy the whole text with the shortcut |
| `App Store Connect GET … failed: 401` | The key, issuer or `.p8` do not match, or the key was revoked | Re-check 1.1; a new key is cheap |
| `Apple already holds 3 distribution certificates` | The account limit | Section 3 |
| `Resource not found` when creating the app record | The bundle ID is not registered yet | Run the signing setup first, then create the app record |
| `No profiles for '…' were found` | The build's `bundle_id` is not the one the setup used | Use the same identifier in both |
| `doesn't include the aps-environment entitlement` | The App ID has no Push capability | Re-run the signing setup; it turns it on |
| `MAC verification failed` while importing the certificate | The `.p12` and its password disagree | Re-run the signing setup; it writes both together |
| `The bundle version must be higher than the previously uploaded version` | TestFlight already has that build number | Re-run — the run number is higher — or set `build_number` |
| TestFlight stays on *Missing Compliance* | Nobody answered the export question | Section 5, step 2 |
| The app installs and cannot connect | `api_url` was wrong, or the server is unreachable | Re-run with the right address |

**A certificate expires after a year**, and a provisioning profile with it.
When that happens, run the signing setup again: it replaces both and rewrites
the secrets. You will need a fresh `SIGNING_ADMIN_TOKEN` for that run.

---

## 7. What is not verified

Everything above is instructions. None of it is a result.

* **Neither of these two workflows has ever run.** They are start-by-hand, and
  nobody has started one. Actions itself does run again — the ordinary CI and
  the unsigned mobile builds execute on every pull request.
* **The unsigned iOS build has been compiled on a real macOS runner**, which is
  how the entitlements file's effect on an unsigned build was found. That is a
  compile, not a signed build: nothing here has produced an `.ipa`.
* **No Apple credential exists here**, so nothing has ever spoken to the App
  Store Connect API from this repository. The setup script's token signing,
  its decisions and the requests it builds are covered by 15 unit tests against
  a stand-in for Apple; what those tests cannot cover is whether Apple accepts
  them.
* **The entitlements change has never been compiled.** `Runner.entitlements`
  and the three `CODE_SIGN_ENTITLEMENTS` lines in the Xcode project are
  written and unbuilt.
* **Nothing has been uploaded**, no billing setting changed, no repository
  setting changed, no workflow started.

`device-beta-checklist.md` still has every row at `not run`. Installing this
build is what starts filling it in.
