import type { DeliveryBus } from './bus.js';
import type { EndedSession } from './sessions.js';

/**
 * Just enough of a logger to report a broadcast that did not go out.
 *
 * Optional, because the announcement must work from anywhere a session can
 * end; where a request logger is at hand it is passed, and a failure becomes
 * something an operator can see rather than something only the clock reveals.
 */
export interface RevocationLog {
  warn(details: Record<string, unknown>, message: string): void;
}

/**
 * What a failed broadcast costs, stated once so both callers can point at it.
 *
 * The session is already revoked in the database — that part is a committed
 * transaction and does not depend on any of this. What is lost is only the
 * promptness: the socket closes at its next revalidation
 * (`WS_REVALIDATE_MS`, a minute by default) instead of within milliseconds.
 * That window is the documented residual exposure of a bus outage, and it is
 * bounded; the alternative, failing the logout when Redis is down, would leave
 * somebody unable to sign out at all.
 */
function reportFailure(log: RevocationLog | undefined, deviceId: string, err: unknown): void {
  // The device id identifies a row, not a person, and no token, session id or
  // key goes anywhere near this line.
  log?.warn(
    { err, deviceId },
    'revocation broadcast failed; the socket closes at its next revalidation instead',
  );
}

/**
 * Tells whatever process is holding the socket that a session has ended.
 *
 * A WebSocket used to check its session exactly once, when it was opened. A
 * device that signed out, was revoked from another phone, or belonged to an
 * account that changed its password kept its connection, kept receiving
 * envelopes, and kept acknowledging them — which deletes them from the queue.
 * Signing out did not stop delivery; it only stopped the *next* connection.
 *
 * The signal goes over the delivery bus rather than a direct call, because the
 * socket is very often not on the process that handled the logout. With Redis
 * configured that makes revocation cross-instance for free; with the in-process
 * bus it is a local event, which is correct when there is one process.
 *
 * Best effort by design, and never allowed to fail the request that caused it.
 * A logout whose broadcast failed still revoked the session in the database,
 * so the socket closes at its next revalidation instead of immediately. The
 * reverse — failing the logout because a bus was down — would leave somebody
 * unable to sign out at all.
 */
export async function announceRevocation(
  bus: DeliveryBus,
  ended: EndedSession[] | EndedSession | null,
  log?: RevocationLog,
): Promise<void> {
  if (!ended) return;
  const list = Array.isArray(ended) ? ended : [ended];
  await Promise.all(
    list.map((session) =>
      bus
        .publish({ deviceId: session.deviceId, kind: 'revoked', sessionId: session.sessionId })
        .catch((err: unknown) => reportFailure(log, session.deviceId, err)),
    ),
  );
}

/**
 * Closes every socket on a device, whichever session it belongs to.
 *
 * For a device revocation and an account deletion, where "which session" is not
 * a useful question: none of them may continue.
 */
export async function announceDeviceRevocation(
  bus: DeliveryBus,
  deviceIds: string[],
  log?: RevocationLog,
): Promise<void> {
  await Promise.all(
    deviceIds.map((deviceId) =>
      bus
        .publish({ deviceId, kind: 'revoked' })
        .catch((err: unknown) => reportFailure(log, deviceId, err)),
    ),
  );
}
