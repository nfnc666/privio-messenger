import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import rateLimit from '@fastify/rate-limit';
import { config, rateLimitFactor } from './config.js';
import authPlugin from './plugins/auth.js';
import accountRoutes from './routes/accounts.js';
import contactRoutes from './routes/contacts.js';
import deviceRoutes from './routes/devices.js';
import { messageRoutes } from './routes/messages.js';
import groupRoutes from './routes/groups.js';
import channelRoutes from './routes/channels.js';
import licenseRoutes from './routes/licenses.js';
import { mediaRoutes } from './routes/media.js';
import { backupRoutes } from './routes/backup.js';
import { websocketRoutes } from './routes/ws.js';
import type { DeliveryBus } from './services/bus.js';
import { DeliveryService } from './services/delivery.js';
import type { PushSender } from './services/push.js';
import { LoggingPushSender } from './services/push.js';
import type { BlobStorage } from './services/storage.js';
import { LocalFileStorage } from './services/storage.js';
import { ApiError } from './util/errors.js';

export interface AppDependencies {
  bus: DeliveryBus;
  push?: PushSender;
  storage?: BlobStorage;
}

/** Replaces the value of any credential-bearing query parameter with a marker. */
export function redactSecrets(url: string): string {
  return url.replace(/([?&](?:token|access_token)=)[^&]*/gi, '$1REDACTED');
}

export async function buildApp(deps: AppDependencies): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      serializers: {
        // Browsers cannot set headers on a WebSocket handshake, so the session
        // token has to ride in the query string. It must not then be copied into
        // the logs, where it would outlive the request and grant whoever reads
        // them a working session.
        req(request) {
          return {
            method: request.method,
            url: redactSecrets(request.url),
            host: request.headers.host,
            remoteAddress: request.ip,
          };
        },
      },
    },
    // Client IPs matter for rate limiting; trust the reverse proxy in front.
    trustProxy: true,
    bodyLimit: config.MAX_ENVELOPE_BYTES * 300,
  });

  const push = deps.push ?? new LoggingPushSender(app.log);
  const storage = deps.storage ?? new LocalFileStorage();
  const delivery = new DeliveryService(deps.bus, push);

  // Encrypted blobs arrive as raw bytes; everything else is JSON.
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (_req, body, done) =>
    done(null, body),
  );

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ApiError) {
      const extra = error as ApiError & { missingDevices?: string[]; extraDevices?: string[] };
      return reply.code(error.statusCode).send({
        error: error.code,
        message: error.message,
        ...(extra.missingDevices ? { missingDevices: extra.missingDevices } : {}),
        ...(extra.extraDevices ? { extraDevices: extra.extraDevices } : {}),
      });
    }
    if ((error as { statusCode?: number }).statusCode === 429) {
      return reply.code(429).send({ error: 'rate_limited', message: 'Too many requests' });
    }
    if ((error as { statusCode?: number }).statusCode === 413) {
      return reply.code(413).send({ error: 'payload_too_large', message: 'Payload too large' });
    }
    // Never leak internals: log the detail, return a generic failure.
    request.log.error({ err: error }, 'unhandled error');
    return reply.code(500).send({ error: 'internal_error', message: 'Something went wrong' });
  });

  app.setNotFoundHandler((_request, reply) =>
    reply.code(404).send({ error: 'not_found', message: 'No such endpoint' }),
  );

  await app.register(rateLimit, {
    max: 300 * rateLimitFactor,
    timeWindow: '1 minute',
    // Authenticated clients are limited per device, anonymous ones per address.
    keyGenerator: (request) => request.auth?.deviceId ?? request.ip,
  });
  // Browsers only. An empty allowlist means no origin is permitted, which is
  // the right default for a server whose clients are native apps.
  const allowedOrigins = config.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
  await app.register(cors, {
    origin: allowedOrigins.length > 0 ? allowedOrigins : false,
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  });

  await app.register(websocket);
  await app.register(authPlugin);

  // Login and registration are the endpoints worth guessing at, so they get a
  // much tighter budget than the rest of the API.
  await app.register(async (scoped) => {
    await scoped.register(rateLimit, {
      max: 10 * rateLimitFactor,
      timeWindow: '5 minutes',
      keyGenerator: (r) => r.ip,
    });
    await scoped.register(accountRoutes);
  });

  await app.register(deviceRoutes);
  await app.register(contactRoutes);
  await app.register(messageRoutes(delivery));
  await app.register(groupRoutes);
  await app.register(channelRoutes);
  await app.register(licenseRoutes);
  await app.register(mediaRoutes(storage));
  await app.register(backupRoutes(storage));
  await app.register(websocketRoutes(delivery, deps.bus));

  app.get('/health', async () => ({ status: 'ok', version: '0.1.0' }));

  /**
   * What a client has to know before it has an account.
   *
   * `licenseRequired` is the one that matters: the app asks for a key on first
   * launch, and it can only know whether to do that before anyone has signed
   * in — which rules out the authenticated licence endpoint. A self-hosted
   * server answers false here and is never asked for a key at all.
   *
   * Deliberately public and deliberately empty of anything else: this is the
   * one endpoint an unauthenticated caller can reach, so it carries policy, not
   * state, and nothing here is a secret.
   */
  app.get('/v1/server', async () => ({
    version: '0.1.0',
    licenseRequired: config.LICENSE_REQUIRED,
  }));

  return app;
}
