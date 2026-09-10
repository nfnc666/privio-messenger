# Putting the server somewhere, from an iPhone

The app is useless without a server to talk to, and the server is the half that
was never deployed. This is how it gets deployed — from Safari on a phone, with
no terminal, no Docker on a laptop, and no SSH key.

```
  Safari, on the iPhone
    ├─ render.com ▸ New ▸ Postgres, in the region you will use
    │        │
    │        │   Created by hand, on purpose. Copy its internal
    │        │   connection string.
    │        ▼
    └─ render.com ▸ New ▸ Blueprint ▸ this repository
             │
             │   render.yaml is read from the repo: one web service (built
             │   from the Dockerfile) and one 10 GB disk.
             ▼
     Paste in DATABASE_URL and any secrets      ← the only typing
             │
             ▼
     Deploy. Migrations run inside the container at start-up.
             │
             ▼
     https://privio-server-xxxx.onrender.com/health  ⇒ {"status":"ok"}
             │
             ▼
  GitHub ▸ Actions ▸ "iOS signed build" ▸ api_url = that URL
```

Two things to know before you start, because they are structural rather than a
matter of preference:

* **A persistent disk needs a paid instance type.** Render's free web services
  cannot mount one, and they sleep when idle. Without a disk, every attachment,
  voice message and backup is lost on each redeploy — the server logs a warning
  saying exactly that at start-up. Prices are in the dashboard, not in this
  file; anything written here would be out of date.
* **A free Postgres on Render is time-limited.** When it lapses, so does the
  data. The expiry is on the database's own page in the dashboard — read it the
  day you create it, not the day it stops. §5 has the alternatives.

  *For this deployment:* `privio-db-frankfurt` was created on 10 September 2026
  on the free plan and **expires on 10 October 2026**. Deciding what happens
  before then — a paid plan, or a fresh free database and a dump restored into
  it — is an open item, not a settled one.

Nothing in this repository deploys anything. `render.yaml` is an offer that
takes effect when you click, and `autoDeploy: false` in it means a later merge
to `main` does not ship — a deploy stays a deliberate act.

---

## 1. What is deployed

One process. It listens on `PORT` (8080), migrates the database at start-up,
and serves the API in `docs/server-api.md`.

It stores, per `docs/security-model.md`: sealed envelopes it cannot open,
public key material, account records, and encrypted blobs on disk. It does not
hold message plaintext, group names, or backup contents in a readable form, and
deploying it on somebody else's infrastructure does not change that — which is
the reason a managed platform is an acceptable place for it at all.

```
   iPhone  ──TLS──▶  Render web service  ──private network──▶  Postgres
                            │
                            └── /data  (disk: attachments, backups)
```

---

## 2. The Blueprint, step by step

Everything below is Safari on the phone.

**2.1 — Sign in to `render.com`** and connect the GitHub account that owns this
repository. Render asks for read access to it; that is enough.

**2.2 — New ▸ Postgres.** The database is created by hand, before the
Blueprint, and this is deliberate — see the note at the top of `render.yaml`
for why. Two things matter and neither can be changed later:

* **The region must be the one the service will use.** `render.yaml` puts the
  service in `frankfurt`, so the database goes in `frankfurt`. Render's
  internal hostnames resolve only within one region; a database anywhere else
  is unreachable, and the failure arrives as `ENOTFOUND` at the first
  connection rather than as anything Render warns about while it is being
  created.
* **The plan.** A free database on Render carries an expiry date, shown on its
  own page. When it lapses, the data goes with it.

Then open the database's page and copy its **internal** connection string —
the one that only works from inside Render's network, not the external one.

**2.3 — New ▸ Blueprint**, pick this repository, branch `main`. Render finds
`render.yaml` and shows what it will create: `privio-server` and the
`privio-media` disk — no database, because this file no longer declares one. If
it shows nothing, the branch is wrong or the file did not parse — Render says
which.

**2.4 — Fill in the values it asks for.** Render prompts for every variable
marked `sync: false`. `DATABASE_URL` is the one that must be filled; the rest
may be left empty. What each does:

| Prompt | Leave empty unless | Where the value comes from |
| --- | --- | --- |
| `DATABASE_URL` | **required** | the internal connection string from §2.2 |
| `LICENSE_HASH_SECRET` | you set `LICENSE_REQUIRED=true` | 32+ random characters, permanent — rotating it invalidates every licence ever issued |
| `LICENSE_ISSUER_TOKEN` | a website issues licences | 32+ random characters |
| `ICE_SERVERS` | you run STUN/TURN | `stun:…,turns:…`, comma-separated |
| `TURN_SECRET` | you run coturn | its `static-auth-secret` |
| `APNS_KEY_P8` … `APNS_TOPIC` | you want iOS push | `docs/notifications.md` §APNs |
| `FCM_PROJECT_ID` … `FCM_PRIVATE_KEY` | you want Android push | the service-account JSON |

Empty is a working configuration. Without APNs and FCM the server delivers over
an open WebSocket and says so at start-up instead of pretending; without TURN,
calls connect on friendly networks and fail behind strict NATs.

`TOTP_SECRET_KEY` is not among the prompts: Render generates a base64-encoded
256-bit value, which is exactly the 32 bytes the TOTP sealing key requires. It
is never typed and never printed into this repository.

`DATABASE_URL` is a prompt rather than something this file derives, and that is
the point: a value entered in the dashboard survives every later Blueprint
sync. When the Blueprint owned it, a sync would have reset it to whatever the
file said — which, after the first database had been replaced by hand, meant a
running service pointed at one that no longer existed.

Render shows what a Blueprint will create before it creates it. Read that
preview rather than confirming it: it lists every resource the sync will add,
change or remove. It should name the service and its disk and nothing else — a
database appearing in it means this file has grown a `databases:` entry again,
and applying that would put the connection back under the Blueprint's control.

**2.5 — Apply.** The first build takes several minutes: it compiles TypeScript
in the image, prunes the dev dependencies, and starts. Then:

* The service log shows `database migrations applied` with the list.
* `https://<your-service>.onrender.com/health` answers
  `{"status":"ok","version":"0.1.0","database":"ok"}`.
* `https://<your-service>.onrender.com/v1/server` answers
  `{"version":"0.1.0","licenseRequired":false}` — this is the one endpoint the
  app calls before anyone has an account.

If the deploy fails instead, §6 has the three failures worth recognising.

**2.6 — Point the app at it.** GitHub ▸ Actions ▸ **iOS signed build** ▸ Run
workflow, and put the URL (`https://…onrender.com`, no trailing slash) into
`api_url`. That value is compiled into the build as `PRIVIO_API_URL`; there is
no server field in the app's UI, and deliberately so — a messenger that can be
repointed at another server from a settings screen is a messenger that can be
repointed by somebody else. `docs/ios-testflight.md` covers the rest of that
run.

---

## 3. Every environment variable

Defaults in bold are what you get by not setting it. The full commentary, on why
each exists, is in `server/src/config.ts`.

| Variable | Default | What it does |
| --- | --- | --- |
| `NODE_ENV` | **development** | `production` turns on the start-up guards below |
| `PORT` | **8080** | listening port |
| `HOST` | **0.0.0.0** | listening address |
| `DATABASE_URL` | **localhost** — refused in production | Postgres connection string |
| `REDIS_URL` | **unset** | required only for more than one instance |
| `MEDIA_DIR` | **./.data/media** | where sealed attachments are written |
| `MEDIA_TTL_DAYS` | **30** | attachments are deleted after this, unconditionally |
| `ENVELOPE_TTL_DAYS` | **30** | undelivered envelopes are purged after this |
| `SESSION_TTL_DAYS` | **365** | a session older than this stops working |
| `WS_REVALIDATE_MS` | **60000** | worst-case delay between "session revoked" and "socket closed" |
| `MAX_ENVELOPE_BYTES` | **65536** | per-message ciphertext limit |
| `MAX_MEDIA_BYTES` | **100 MB** | per-attachment limit |
| `MAX_BACKUP_BYTES` | **512 MB** | per-backup limit |
| `CORS_ORIGINS` | **empty** | browser origins allowed; the mobile apps do not need it |
| `LOG_LEVEL` | **info** | pino level |
| `ICE_SERVERS` | **empty** | STUN/TURN offered to clients |
| `TURN_SECRET` | unset | coturn shared secret for time-limited credentials |
| `TURN_TTL_SECONDS` | **43200** | lifetime of a minted TURN credential |
| `LICENSE_REQUIRED` | **false** | whether this deployment sells access |
| `LICENSE_HASH_SECRET` | unset | required when the above is true |
| `LICENSE_ISSUER_TOKEN` | unset | bearer token for issuing licences |
| `TOTP_SECRET_KEY` | unset | base64 of exactly 32 bytes; without it, two-factor enrolment is refused |
| `UNIFIEDPUSH_ALLOWED_HOSTS` | **empty** = any HTTPS host | narrows which distributors may be registered |
| `APNS_KEY_P8` / `_KEY_ID` / `_TEAM_ID` / `_TOPIC` | unset | all four together or none |
| `APNS_ENVIRONMENT` | **production** | a TestFlight build needs `sandbox` |
| `FCM_PROJECT_ID` / `_CLIENT_EMAIL` / `_PRIVATE_KEY` | unset | all three together or none |

### What production refuses, and what it merely warns about

With `NODE_ENV=production` the server **refuses to start** when `DATABASE_URL`
is not set. The development default points at `localhost`, and inheriting it on
a server means migrating an empty database that nobody uses while every request
fails — a failure that looks like a successful deploy. Setting it explicitly to
a localhost address is still allowed: a database beside the server is a real
deployment, and what is refused is the unstated default, not the value.

It **warns, and runs**, when:

* `MEDIA_DIR` is unset — attachments go into the container's own filesystem and
  are discarded on the next deploy;
* `TOTP_SECRET_KEY` is unset — the server runs and refuses to enrol anyone in
  two-factor authentication;
* `REDIS_URL` is unset — correct for one instance, wrong the moment a second is
  started, because the two would not see each other's deliveries or revocations.

Half-configured push credentials are refused outright, at start-up: a set of
APNs values with one missing does not deliver, and looking configured is worse
than being unconfigured.

---

## 4. `GET /health`

```
200  {"status":"ok","version":"0.1.0","database":"ok"}
503  {"status":"unhealthy","version":"0.1.0","database":"unreachable"}
```

It performs one round trip to Postgres, bounded at two seconds, and answers 503
when that fails. This matters more than it sounds: until this milestone the
endpoint returned 200 unconditionally, so a platform health check would keep an
instance with a dead database in the load balancer and report a green deploy
while every real request failed. A health check that cannot fail only certifies
that Node is running.

Redis is deliberately not checked. The server degrades to an in-process bus
without it, and failing health on a degradation would remove a serving instance
for no gain. The failure detail stays in the logs — the body says `unreachable`
and nothing more, because this endpoint is reachable without authentication.

Reporting 503 requires surviving the outage, and the server did not: `pg` raises
an `error` event on the pool when an idle client's connection breaks, Node
throws on an `error` event nobody listens to, and the process died. The CI job
below is what found it — the container stopped answering entirely instead of
answering 503. A database restart, a failover, or a managed-database maintenance
window would have crash-looped the service. The pool now reports the failure and
keeps serving; the broken client is discarded and the next request opens a new
one, so the server recovers by itself when Postgres comes back.

---

## 5. Somewhere other than Render

The image is plain Docker and the Blueprint is a convenience, not a dependency.
On any host with a Docker daemon:

```sh
docker build -t privio-server .
docker run -d --name privio \
  -p 8080:8080 \
  -v /srv/privio/media:/data/media \
  -e NODE_ENV=production \
  -e DATABASE_URL=postgres://privio:…@db:5432/privio \
  -e TOTP_SECRET_KEY="$(openssl rand -base64 32)" \
  privio-server
```

Notes that are easy to get wrong:

* **Terminate TLS in front of it.** The server speaks plain HTTP; put nginx,
  Caddy or the platform's own proxy ahead of it. It already trusts
  `X-Forwarded-For` for rate limiting, so the proxy must set it.
* **The volume must be the one `MEDIA_DIR` names.** The image defaults it to
  `/data/media`.
* **Migrations run at start-up, inside the process.** There is no separate
  release command to configure, and nothing to run by hand.
* **Back up Postgres and the media directory together.** Neither is
  reconstructible from the other, and a client's local archive is sealed with a
  key the server does not have.
* **One instance, unless you add Redis.** Two processes without `REDIS_URL` do
  not share deliveries or revocations.

Any platform that runs a container from a repository — Fly, Railway, a VPS with
Docker Compose, Kubernetes — works the same way: build the `Dockerfile`, set
the variables in §3, mount a volume, health-check `/health`.

---

## 6. When it does not come up

**The service starts and immediately exits, with `DATABASE_URL` in the log.**
The production guard, working as intended: nothing set the variable. On Render
this means the prompt in §2.4 was left empty, or the value was entered on the
wrong service. Set it in the service's Environment tab and redeploy.

**The log shows `ENOTFOUND` on the database host.** The database and the
service are in different regions. Render's internal hostnames resolve only
within one region, and nothing objects while either is being created — the
failure arrives at the first connection attempt. This is not hypothetical: the
first real deploy hit it, because `render.yaml` then declared the database
without a `region` and Render created it in its own default region rather than
beside the service. That is why §2.2 creates the database by hand, region
first.

A region cannot be changed after the fact. Fixing it means creating a new
database in the service's region, updating `DATABASE_URL` on the service, and
moving the contents if there are any worth moving.

**`DATABASE_URL` changed back on its own after a Blueprint sync.** It should
not be possible any more — the variable is `sync: false` and this file declares
no database. If it happens, `render.yaml` has regained a `databases:` entry or
a `fromDatabase` reference; `tools/render-blueprint.test.mjs` fails on both.

**The deploy hangs and is marked unhealthy.** `/health` is answering 503, so
the database is not reachable from the service. On Render, check that the
database finished provisioning and is in the same region as the service;
elsewhere, that the connection string is right and the host reachable from
inside the container.

**It comes up, and attachments vanish after the next deploy.** The start-up
warning about `MEDIA_DIR` was correct: the disk is not mounted, or `MEDIA_DIR`
points outside it. `render.yaml` mounts `/data` and sets `MEDIA_DIR=/data/media`
— a test in `tools/render-blueprint.test.mjs` keeps those two consistent.

**The app cannot reach the server.** The URL is compiled into the build. A
build made with the wrong `api_url` has to be rebuilt; there is no setting in
the app to change it.

---

## 7. What has actually been verified

Being precise about this is the point of the milestone, so:

**Verified in CI, on every pull request** (`.github/workflows/ci.yml`, job
*Server — image builds and serves*): the image builds; a container without
`DATABASE_URL` refuses to start; a container with one applies migrations and
answers `/health` with 200; stopping Postgres leaves the process running and
turns that same endpoint into a 503.

**Verified by the test suite**: the production configuration guard, the
warnings, both health responses, and that a pool-level connection failure is
reported instead of terminating the process
(`server/test/deployment.test.ts`); the
consistency of `render.yaml` with the `Dockerfile` (`tools/render-blueprint.test.mjs`).

**Not verified, and not claimable until somebody does it:** that a Render
Blueprint deploy of this file succeeds. Nobody has run one. The YAML is
consistent with Render's documented Blueprint schema and with this repository,
and Render validates it before creating anything — but a green CI run is not a
deploy, and this document does not pretend otherwise. The first real deploy is
yours to click, and if Render rejects something in the file, that is a fix to
make, not a surprise about the server.

**Also not verified:** performance, capacity, or behaviour under load of any
kind. Nothing here has served two users at once.
