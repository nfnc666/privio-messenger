import type { DeliveryBus } from './bus.js';
import type { EndedSession } from './sessions.js';

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
): Promise<void> {
  if (!ended) return;
  const list = Array.isArray(ended) ? ended : [ended];
  await Promise.all(
    list.map((session) =>
      bus
        .publish({ deviceId: session.deviceId, kind: 'revoked', sessionId: session.sessionId })
        .catch(() => {}),
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
): Promise<void> {
  await Promise.all(
    deviceIds.map((deviceId) =>
      bus.publish({ deviceId, kind: 'revoked' }).catch(() => {}),
    ),
  );
}
