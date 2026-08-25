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
 *   { "type": "pong" }
 */
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
            if (socket.readyState !== socket.OPEN) return;
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

      const unsubscribe = bus.subscribe((deviceId) => {
        if (deviceId === auth.deviceId) void drain();
      });

      socket.on('message', async (raw: Buffer) => {
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
          await delivery.acknowledge(auth.deviceId, frame.upTo!);
          void drain();
        }
      });

      socket.on('close', unsubscribe);
      socket.on('error', unsubscribe);

      // Deliver whatever accumulated while the device was offline.
      void drain();
    });
  };
}

export default websocketRoutes;
