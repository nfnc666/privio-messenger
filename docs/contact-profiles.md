# Contact profiles from chats

The direct-chat header pushes a route identified by the peer's immutable account
ID. Group headers still open group information; message sender names and avatars
open the authenticated sender ID (or the signed-in ID for outgoing messages).
The underlying chat State, composer and positioned list are not replaced.

The route reuses PrivioAvatar, PhotoViewer, ProfileStatus, the current accent,
CallService and MessageStore. Message opens the original direct chat by popping
the profile; from a group it upserts the ID-keyed conversation without replacing
its messages. No username search is involved. Contact add/remove and block/unblock
are account-scoped API operations. Removing or blocking here does not delete chats.

## Privacy and boundaries

- The existing authenticated `/v1/users/id/:accountId` route returns explicit
  public fields plus the requesting account's own contact/block relationships.
- Status and last-seen are filtered server-side using the target's contact list;
  both are withheld when either side blocks the other. Reverse block state is
  never returned. The owner can see their own status.
- No phone field is parsed or displayed. No online inference is made.
- Avatars require the existing E2EE profile key. No key is obtained from the lookup.
  Missing keys/images display initials; the route does not reuse stale peer images.
- Each route/controller belongs to one API session generation, including across
  sign-out/sign-in to the same account. There is no persistent profile cache.
- No edit actions appear in this read-only screen, including for another user.
- There is currently no separate account biography field in PRIVIO. The existing
  permitted status is displayed; no invented biography is added.
- Reporting an account is its own workflow, added on top of this screen rather
  than borrowed from channels — see below.

## Reporting an account

The profile's last action files a report. It is deliberately **not** blocking:
the two are offered together and somebody may well want both, but a report that
silently blocked would turn an accusation into a change to your own account, and
a block that silently reported would send your address book to a moderator.

What a report can carry is limited by what the server knows, which is nothing
about what anybody said. There is no message to attach, because the server never
held one in the clear — so the sheet says that before the reasons rather than
after the fact, and the reasons themselves are a fixed list of five words.
A free-text box is where somebody pastes the message they are reporting, which
is the one thing that must never reach a column the server can read.

`POST /v1/users/:id/report` takes that reason, writes one row per
(reported account, reporter) — the primary key is what makes a second complaint
about the same person a no-op rather than a second entry — and answers whether
this one was already on file, which is the difference between "filed" and "your
earlier report is still on file". Migration `033_account_reports.sql` adds the
table; `GET /v1/admin/reports/accounts` is where a moderator sees the counts,
and `admin-panel.md` states what those counts are and are not.

## Deployment

Deploy the backend changes before distributing the app: the ID profile now
includes isContact/isBlocked and POST /v1/contacts accepts exactly one of username
or accountId. Existing username clients remain compatible. No migration, new
dependency or native permission is needed. Build new iOS and Android app versions.

## Validation

Executed locally:

- `npm ci --ignore-scripts` and server TypeScript typecheck: successful.
- `node --test tools/contact-profile.test.mjs`: source/localization checks only;
  these are not Flutter behavior tests.
- `git diff --check`.

Executed when this branch merged `main` (a Flutter SDK and a PostgreSQL were
available there):

- `flutter analyze`, the whole `flutter test` suite, and the server suite
  including `contact_profile.test.ts`.
- The report route is covered by `server/test/contacts.test.ts`: the fixed
  reason set, the second report as a no-op, and one account's report being
  invisible to another.

Added but not executed here:

- `app/test/contact_profile_test.dart`: ID lookup, response mismatch, hidden
  fields, deleted/error responses, account-switch races, contact operations,
  conversation reuse and sender taps with iOS/Android themes.
- `server/test/contact_profile.test.ts`: authenticated allowlist, target-side
  contact privacy, owner status, viewer isolation, blocks, removal, deletion.
  The local tsx runner was blocked from opening its IPC socket (EPERM).
- Flutter SDK and device simulators are unavailable in this environment.

Before merge/release run CI (Flutter analyze/test and PostgreSQL-backed server
tests). On real iOS and Android test header taps, different group senders with
identical names, own sender, image zoom, audio/video, blocked/unblocked state,
restricted and deleted profiles, offline retry, account switch during load,
and returning to a scrolled chat with an unsent draft. Check that Message does
not create duplicate history. Device checks are still pending.
