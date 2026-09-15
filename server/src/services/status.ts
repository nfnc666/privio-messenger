/**
 * The profile status: what somebody chose to publish about themselves.
 *
 * Deliberately its own module and its own privacy key, sitting beside
 * `presence.ts` rather than inside it. The two are not the same thing and must
 * not be decided together:
 *
 * * **Last seen** is produced *by* the user — a timestamp the server writes
 *   whenever they connect. Hiding it is hiding an observation.
 * * **A status** is written *by* the user, on purpose, to be read. Hiding it
 *   is withholding something they published.
 *
 * Wiring the status to `privacy.lastSeen` would mean someone who hides when
 * they were last online silently loses the line they typed for their friends
 * to see — two unrelated decisions collapsed into one switch. So `profileStatus`
 * is separate, and a client that wants both has to ask for both.
 */

/** A status as it goes over the wire, or null where there is none to show. */
export interface VisibleStatus {
  text: string | null;
  emoji: string | null;
  expiresAt: string | null;
  updatedAt: string | null;
}

/** The columns this module needs from an account row. */
export interface StatusColumns {
  privacy?: { profileStatus?: string } | null;
  status_text: string | null;
  status_emoji: string | null;
  status_expires_at: Date | null;
  status_updated_at: Date | null;
}

/** Nothing to show, as the shape every caller can hand straight to a client. */
export const NO_STATUS: VisibleStatus = {
  text: null,
  emoji: null,
  expiresAt: null,
  updatedAt: null,
};

/**
 * Whether a stored status has run out.
 *
 * Checked on every read rather than swept on a schedule, and that ordering is
 * the whole guarantee: a user who sets "back at 5" until 17:00 has it disappear
 * at 17:00 even if no cleanup job ever runs, the sweeper is wedged, or the row
 * is read a millisecond after the deadline. A sweeper that deleted expired rows
 * would be an optimisation on top of this, never the thing that makes it true —
 * because the failure mode of a missed sweep is a status coming back from the
 * dead, which is exactly what must not happen.
 */
export function hasExpired(row: StatusColumns, now: Date = new Date()): boolean {
  return row.status_expires_at !== null && row.status_expires_at.getTime() <= now.getTime();
}

/** The owner's own status. No privacy check: this is them looking at themselves. */
export function ownStatus(row: StatusColumns, now: Date = new Date()): VisibleStatus {
  if (hasExpired(row, now)) return NO_STATUS;
  if (row.status_text === null && row.status_emoji === null) return NO_STATUS;
  return {
    text: row.status_text,
    emoji: row.status_emoji,
    expiresAt: row.status_expires_at?.toISOString() ?? null,
    updatedAt: row.status_updated_at?.toISOString() ?? null,
  };
}

/**
 * What a particular viewer may see of somebody else's status.
 *
 * `everyone` is the default, and it is the one place this module's default
 * differs from `presence.ts`. The reason is the distinction at the top of this
 * file: a status only exists because its owner typed it and pressed save, and
 * defaulting a published line to hidden would mean the feature silently does
 * nothing for everybody who never visits the privacy screen. Someone who wants
 * it narrower says so, in the same place they narrow last-seen.
 *
 * `contacts` means the *owner's* address book, not the viewer's — the same rule
 * `lastSeenFor` applies, and for the same reason: adding somebody must not
 * entitle you to read them.
 */
export function statusFor(
  row: StatusColumns,
  viewerIsContactOfTarget: boolean,
  now: Date = new Date(),
): VisibleStatus {
  const setting = row.privacy?.profileStatus ?? 'everyone';
  if (setting === 'nobody') return NO_STATUS;
  if (setting === 'contacts' && !viewerIsContactOfTarget) return NO_STATUS;
  return ownStatus(row, now);
}

/**
 * Deletes statuses whose moment has passed.
 *
 * Housekeeping, not correctness — see [hasExpired]. Its only job is to stop the
 * table carrying text nobody will ever be shown again, which matters because
 * that text is the one thing on an account row the owner asked to be temporary.
 */
export const DELETE_EXPIRED_STATUSES = `
  UPDATE accounts
  SET status_text = NULL, status_emoji = NULL, status_expires_at = NULL
  WHERE status_expires_at IS NOT NULL AND status_expires_at <= now()
`;
