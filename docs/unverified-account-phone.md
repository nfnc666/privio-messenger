# Optional unverified phone annotation

Account → Phone number (optional) opens a private editor using the existing
PhoneField, theme/accent, international normalization and phone keyboard. It
supports country-code selection, international paste, saving, changing and
removal. All new labels are provided in EN/DE/ES/FR/IT.

## Security boundary

- This is an **unverified annotation**, not an identity or phone ownership claim.
- Only authenticated `/v1/accounts/me/phone-note` reads/writes this data. The
  account comes from the session; accountId/verified/discoverable request flags
  are rejected. Read responses explicitly state `verified: false` and
  `usedForDiscovery: false`.
- `account_phone_notes` is separate from `phone_links`. Neither contact discovery,
  authentication, password recovery nor merging queries the new table. Multiple
  accounts may enter the same number without affecting each other.
- An existing verified number and its discovery choice remain unchanged. The UI
  tells the owner to manage that separate number in Privacy → Phone number &
  contacts. Removing this annotation does **not** remove that verified link.
- The full number is stored in the private database table and sent over the
  authenticated TLS API. It is **not end-to-end encrypted from the server**;
  server/database administrators can read it. Public profile/contact/group/
  channel projections do not include the annotation. Protect database access and
  backups accordingly. No phone number is placed in URLs or application logs;
  the existing request logger excludes request bodies.
- No SMS is sent and no SMS/discovery provider or key is required by this field.
  Format normalization is not proof that a number exists or belongs to the user.
- Controller state and pending responses belong to an API session generation;
  account switches (including re-login to the same account) invalidate them.
- Removal deletes the live row; account wipe/deletion also removes it. Existing
  database backups remain subject to the operator's backup-retention policy.

## Deployment

Deploy the backend first. Migration `033_unverified_account_phone.sql` runs through
the existing migration runner. Then distribute new Flutter iOS/Android builds.
There are no new dependencies, permissions, SMS settings or provider charges.
Keep this change separate from the unfinished disappearing-timer worktree.

## Validation

Added backend tests: optional/unauthenticated reads, international normalization,
save/change/removal, malformed input, forbidden authority fields, persistence
across an app-server restart, same-number account isolation, public/discovery
non-disclosure, preservation of verified links, and account wipe. The no-SMS test
disables SMS and discovery configuration while using the annotation endpoint.

Added Flutter tests: save/change/reload/removal, failed save, invalid/empty input,
late response after account switch, old-route write prevention, actual editor
save/removal, and country-code/paste/keyboard behavior in iOS/Android themes.

Local typecheck and source/localization checks are recorded in the PR. Flutter
and PostgreSQL runtime tests require CI in this environment; do not confuse the
source checks with device testing. Real iPhone/Android tests remain necessary:
enter and change a number, remove it, restart/re-login, switch accounts during a
slow save, and verify the keyboard and selected accent on a small screen.
