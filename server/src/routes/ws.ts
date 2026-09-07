import type { FastifyPluginAsync } from 'fastify';
import type { DeliveryBus } from '../services/bus.js';
import type { DeliveryService } from '../services/delivery.js';
import { resolveSession } from '../services/sessions.js';

/**
 * Realtime channel. The socket is a doorbell plus a delivery pipe: envelopes are
 * read from the queue and removed only once the client acknowledges them, so a
 * dropped connection never loses a message.
 *
 * Client -> server frames:
 *   { "type": "ack", "upTo": 42 }   acknowledge everything through envelope 42
 *   { "type": "ping" }
 * Server -> client frames:
 *   { "type": "envelopes", "envelopes": [...] }
 *   { "type": "key-request" }   somebody is waiting for a key you hold
 *   { "type": "pong" }
 *
 * The session is checked when the socket opens **and while it stays open**.
 * It used to be checked only at the door: a device that signed out, was revoked
 * from another phone, or whose account changed its password kept its connection
 * and kept receiving envelopes — and its acknowledgements kept deleting them
 * from the queue. Signing out stopped the next connection, not the current one.
 */

/**
 * How often a live connection re-checks that its session is still good.
 *
 * The revocation broadcast is what closes a socket promptly; this is the
 * backstop for the cases a broadcast cannot cover — a session that simply
 * expired, a revocation published while this process was briefly disconnected
 * from Redis, or a row changed by something that never went through the API at
 * all. A minute is short enough that "revoked" does not mean "in an hour" and
 * long enough that ten thousand idle sockets are not ten thousand queries a
 * second.
 */
const REVALIDATE_MS = 60_000;
export function websocketRoutes(delivery: DeliveryService, bus: DeliveryBus): FastifyPluginAsync {
  return async (app) => {
    app.get('/v1/ws', { websocket: true }, async (socket, request) => {
      const header = request.headers.authorization;
      const token =
        (request.query as { token?: string } | undefined)?.token ??
        (header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : undefined);

      const auth = token ? await resolveSession(token) : null;
      if (!auth) {
        socket.send(JSON.stringify({ type: 'error', code: 'unauthorized' }));
        socket.close(4401, 'unauthorized');
        return;
      }

      const BATCH = 100;
      let draining = false;
      let queuedWake = false;

      /**
       * Set the moment this connection stops being entitled to anything.
       *
       * Checked before every send and before every acknowledgement rather than
       * relying on the socket having closed already: `close()` is asynchronous,
       * a drain may be halfway through, and a frame that arrives in that window
       * must not be acted on. Once this is true the connection delivers
       * nothing further and acknowledges nothing further.
       */
      let revoked = false;

      const stop = (reason: string): void => {
        if (revoked) return;
        revoked = true;
        clearInterval(revalidation);
        try {
          if (socket.readyState === socket.OPEN) {
            socket.send(JSON.stringify({ type: 'error', code: reason }));
            socket.close(4401, reason);
          }
        } catch {
          // The socket may already be gone; that is the outcome either way.
        }
      };

      /**
       * Re-reads the session, and closes if it is no longer valid.
       *
       * `resolveSession` is the same query the door uses, so this covers every
       * reason a session can stop being good — revoked, expired, device
       * revoked, account deleted — rather than a list of them maintained here.
       */
      const revalidate = async (): Promise<boolean> => {
        if (revoked) return false;
        try {
          const still = token ? await resolveSession(token) : null;
          if (!still) {
            stop('session_revoked');
            return false;
          }
          return true;
        } catch (err) {
          // A database blip is not a revocation. The connection stays and the
          // next tick tries again; treating an outage as a mass logout would
          // be its own kind of failure.
          request.log.warn({ err }, 'websocket revalidation failed');
          return true;
        }
      };

      const revalidation = setInterval(() => void revalidate(), REVALIDATE_MS);
      // Never hold the process open for the sake of a heartbeat.
      revalidation.unref?.();

      const drain = async (): Promise<void> => {
        // Coalesce overlapping wakeups instead of interleaving reads of the queue.
        if (draining) {
          queuedWake = true;
          return;
        }
        draining = true;
        try {
          do {
            queuedWake = false;
            if (revoked || socket.readyState !== socket.OPEN) return;
            const envelopes = await delivery.fetch(auth.deviceId, BATCH);
            if (envelopes.length > 0) {
              socket.send(JSON.stringify({ type: 'envelopes', envelopes }));
            }
            // Anything beyond this batch waits for the client's ack, which both
            // applies backpressure and keeps redelivery correct after a drop.
          } while (queuedWake);
        } catch (err) {
          request.log.error({ err }, 'websocket drain failed');
        } finally {
          draining = false;
        }
      };

      const unsubscribe = bus.subscribe((wake) => {
        if (wake.deviceId !== auth.deviceId) return;
        if (wake.kind === 'revoked') {
          // Either this exact session ended, or the whole device was revoked
          // and no session id was named. A logout on one of an account's
          // devices must not close the others, which is why the id is checked.
          if (wake.sessionId === undefined || wake.sessionId === auth.sessionId) {
            stop('session_revoked');
          }
          return;
        }
        if (wake.kind === 'key-request') {
          // Nothing to read: somebody in a group or channel this device is in
          // is waiting for its key, and the answer is the client's to send.
          // Without this the request waits for the client's two-minute poll.
          if (socket.readyState === socket.OPEN) {
            socket.send(JSON.stringify({ type: 'key-request' }));
          }
          return;
        }
        void drain();
      });

      socket.on('message', async (raw: Buffer) => {
        if (revoked) return;
        let frame: { type?: string; upTo?: number };
        try {
          frame = JSON.parse(raw.toString('utf8'));
        } catch {
          socket.send(JSON.stringify({ type: 'error', code: 'invalid_frame' }));
          return;
        }
        if (frame.type === 'ping') {
          socket.send(JSON.stringify({ type: 'pong' }));
        } else if (frame.type === 'ack' && Number.isInteger(frame.upTo)) {
          // An acknowledgement deletes envelopes. A revoked connection must not
          // be able to do that — it is the more damaging half of the bug, since
          // a signed-out device was quietly emptying the queue of messages the
          // real one had not read.
          if (revoked) return;
          await delivery.acknowledge(auth.deviceId, frame.upTo!);
          void drain();
        }
      });

      socket.on('close', () => {
        clearInterval(revalidation);
        unsubscribe();
      });
      socket.on('error', () => {
        clearInterval(revalidation);
        unsubscribe();
      });

      // The race the door alone cannot close: a revocation that was published
      // between `resolveSession` above and `bus.subscribe` just now would have
      // been broadcast to nobody, because this connection was not listening
      // yet. Re-reading the session *after* subscribing means the connection is
      // either told by the broadcast or finds out here — there is no ordering
      // in which it learns neither.
      if (!(await revalidate())) {
        unsubscribe();
        return;
      }

      // Deliver whatever accumulated while the device was offline.
      void drain();
    });
  };
}

export default websocketRoutes;
