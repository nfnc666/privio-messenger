import type { FastifyPluginAsync } from 'fastify';
import { config } from '../config.js';
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
 */

/** Authentication carried as a WebSocket subprotocol rather than in the URL. */
const AUTH_PROTOCOL_PREFIX = 'privio-auth.';

function websocketToken(request: Parameters<FastifyPluginAsync>[0] extends never ? never : any): string | undefined {
  const header = request.headers.authorization as string | undefined;
  if (header?.startsWith('Bearer ')) {
    const value = header.slice('Bearer '.length).trim();
    if (value.length > 0) return value;
  }

  const protocols = request.headers['sec-websocket-protocol'];
  if (typeof protocols !== 'string') return undefined;
  for (const raw of protocols.split(',')) {
    const protocol = raw.trim();
    if (protocol.startsWith(AUTH_PROTOCOL_PREFIX)) {
      const value = protocol.slice(AUTH_PROTOCOL_PREFIX.length);
      if (value.length > 0) return value;
    }
  }
  return undefined;
}

/**
 * How often a live connection re-checks that its session is still good.
 */
const revalidateMs = (): number => config.WS_REVALIDATE_MS;
export function websocketRoutes(delivery: DeliveryService, bus: DeliveryBus): FastifyPluginAsync {
  return async (app) => {
    app.get('/v1/ws', { websocket: true }, async (socket, request) => {
      // Never accept a credential from the query string. URLs are routinely
      // copied into reverse-proxy/access logs before Fastify gets a chance to
      // redact them. Native clients may use Authorization; browser-compatible
      // clients use the Sec-WebSocket-Protocol header.
      const token = websocketToken(request);

      const auth = token ? await resolveSession(token) : null;
      if (!auth) {
        socket.send(JSON.stringify({ type: 'error', code: 'unauthorized' }));
        socket.close(4401, 'unauthorized');
        return;
      }

      const BATCH = 100;
      let draining = false;
      let queuedWake = false;
      let revoked = false;

      const stop = (reason: string): void => {
        if (revoked) return;
        revoked = true;
        clearInterval(revalidation);
        unsubscribe?.();
        try {
          if (socket.readyState === socket.OPEN) {
            socket.send(JSON.stringify({ type: 'error', code: reason }));
            socket.close(4401, reason);
          }
        } catch {
          // The socket may already be gone; that is the outcome either way.
        }
      };

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
          request.log.warn({ err }, 'websocket revalidation failed');
          return true;
        }
      };

      const revalidation = setInterval(() => void revalidate(), revalidateMs());
      revalidation.unref?.();

      const drain = async (): Promise<void> => {
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
            if (revoked || socket.readyState !== socket.OPEN) return;
            if (envelopes.length > 0) {
              socket.send(JSON.stringify({ type: 'envelopes', envelopes }));
            }
          } while (queuedWake);
        } catch (err) {
          request.log.error({ err }, 'websocket drain failed');
        } finally {
          draining = false;
        }
      };

      let unsubscribe: (() => void) | undefined;
      unsubscribe = bus.subscribe((wake) => {
        if (wake.deviceId !== auth.deviceId) return;
        if (wake.kind === 'revoked') {
          if (wake.sessionId === undefined || wake.sessionId === auth.sessionId) {
            stop('session_revoked');
          }
          return;
        }
        if (wake.kind === 'key-request') {
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
          if (revoked) return;
          await delivery.acknowledge(auth.deviceId, frame.upTo!);
          void drain();
        }
      });

      socket.on('close', () => {
        clearInterval(revalidation);
        unsubscribe?.();
      });
      socket.on('error', () => {
        clearInterval(revalidation);
        unsubscribe?.();
      });

      if (!(await revalidate())) {
        unsubscribe?.();
        return;
      }

      void drain();
    });
  };
}

export default websocketRoutes;
