/**
 * Whether a viewer may see when somebody was last online.
 *
 * `contacts` — the default — means *their* address book, not yours: adding
 * someone must not entitle you to watch them. `everyone` tells anyone who can
 * see the account at all; `nobody` tells no one.
 *
 * It lives here rather than in one route because three places now answer the
 * same question — a profile lookup, the contacts list, and a channel's member
 * list — and a privacy rule with three implementations has two that are wrong.
 * Running a channel is deliberately not a reason to see more: an admin reading
 * their subscriber list gets exactly what any other viewer would.
 */
export function lastSeenFor(
  target: { privacy?: { lastSeen?: string } | null; last_seen_at: Date },
  viewerIsContactOfTarget: boolean,
): string | null {
  const setting = target.privacy?.lastSeen ?? 'contacts';
  if (setting === 'nobody') return null;
  if (setting === 'everyone') return target.last_seen_at.toISOString();
  return viewerIsContactOfTarget ? target.last_seen_at.toISOString() : null;
}
