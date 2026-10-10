-- Less of what the server keeps about when and from what people use Privio.
--
-- Two things from `docs/metadata-privacy-review.md` that no feature needed:
--
-- 1. **The browser or app string of every sign-in.** `sessions.user_agent`
--    was written on each new session and never read. A user agent is a
--    fingerprint — model, system version, app build — and keeping it per
--    session made it a history of someone's devices. The column goes, and with
--    it every value already stored.
--
-- 2. **Activity to the second.** `accounts.last_seen_at`, `devices.last_seen_at`
--    and `sessions.last_used_at` were written to the millisecond on every
--    request, which over time is a fine-grained picture of when somebody is
--    awake. From now on they are written to the hour (`services/sessions.ts`),
--    and what is already stored is rounded down to the hour here, so that the
--    old precision does not outlive the change.
--
-- **Irreversible by intent.** The user agents and the minutes are gone, not
-- moved. Nothing reads either, so nothing breaks: "last seen" was shown in
-- coarse words already, and the app now says it by the hour.

ALTER TABLE sessions DROP COLUMN user_agent;

-- Rounded in UTC, here and below, so the hour does not depend on the time zone
-- a connection happens to be set to.
UPDATE accounts SET last_seen_at = date_trunc('hour', last_seen_at, 'UTC')
 WHERE last_seen_at <> date_trunc('hour', last_seen_at, 'UTC');
UPDATE devices SET last_seen_at = date_trunc('hour', last_seen_at, 'UTC')
 WHERE last_seen_at <> date_trunc('hour', last_seen_at, 'UTC');
UPDATE sessions SET last_used_at = date_trunc('hour', last_used_at, 'UTC')
 WHERE last_used_at <> date_trunc('hour', last_used_at, 'UTC');

-- A new account, device or session starts out at the same precision. Without
-- this, the first value of each would still be exact to the microsecond.
ALTER TABLE accounts ALTER COLUMN last_seen_at SET DEFAULT date_trunc('hour', now(), 'UTC');
ALTER TABLE devices ALTER COLUMN last_seen_at SET DEFAULT date_trunc('hour', now(), 'UTC');
ALTER TABLE sessions ALTER COLUMN last_used_at SET DEFAULT date_trunc('hour', now(), 'UTC');
