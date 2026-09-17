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
- Existing reporting supports **channels only**. This change does not introduce
  a nonfunctional user-report button or repurpose channel reports. User reporting
  needs a separate server/moderation workflow and remains outside this patch.

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
- `npm run test:tools`: all 27 checks passed.

GitHub CI on the first implementation commit (`e2a9b6a`): server typecheck,
PostgreSQL-backed tests, container build/health tests and Flutter analyze passed.
Flutter tests were still running when the additional navigation regression test
was added. This does not count as device testing or as approval of later commits.

Added but not executed here:

- `app/test/contact_profile_test.dart`: ID lookup, response mismatch, hidden
  fields, deleted/error responses, account-switch races, contact operations,
  conversation reuse and sender taps with iOS/Android themes. A further widget
  test checks actual ChatScreen identity, an unsent draft and scroll position
  after opening and closing the profile (including a failed profile lookup).
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
