import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { config } from '../config.js';
import { isLicensed } from '../services/licenses.js';
import type { AuthContext } from '../services/sessions.js';
import { resolveSession } from '../services/sessions.js';
import { ApiError } from '../util/errors.js';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthContext;
  }
  interface FastifyInstance {
    requireAuth: (request: FastifyRequest) => Promise<void>;
    requireLicense: (request: FastifyRequest) => Promise<void>;
  }
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

/**
 * A key request belongs to the device that is waiting for the key.
 *
 * Historically the holder that *sent* a key deleted the request. Because every
 * member can see pending requests, that also meant every member could delete a
 * request without sending anything and permanently starve a new device of the
 * E2EE group/channel key. Clearing is now an acknowledgement by the requesting
 * device itself. The route shape is kept for compatibility, but a session may
 * acknowledge only its own device id.
 */
function enforceOwnKeyRequestAck(request: FastifyRequest, context: AuthContext): void {
  if (request.method !== 'DELETE') return;
  const path = request.url.split('?', 1)[0] ?? '';
  const match = path.match(/^\/v1\/(?:groups|channels)\/[^/]+\/key-requests\/([^/]+)$/);
  if (!match) return;

  let requestedDeviceId: string;
  try {
    requestedDeviceId = decodeURIComponent(match[1]!);
  } catch {
    throw ApiError.badRequest('invalid_device', 'Invalid device id');
  }
  if (requestedDeviceId !== context.deviceId) {
    throw ApiError.forbidden(
      'key_request_not_owned',
      'Only the device waiting for this key may acknowledge its request',
    );
  }
}

const authPlugin: FastifyPluginAsync = async (app) => {
  app.decorateRequest('auth', undefined);

  app.decorate('requireAuth', async (request: FastifyRequest) => {
    const token = bearerToken(request);
    if (!token) throw ApiError.unauthorized('missing_token', 'Bearer token required');
    const context = await resolveSession(token);
    if (!context) throw ApiError.unauthorized('invalid_token', 'Session is invalid or expired');
    request.auth = context;
    enforceOwnKeyRequestAck(request, context);
  });

  /**
   * Gate for the routes that put something new into the system.
   *
   * Runs after `requireAuth`. Only sending is gated: an unlicensed account can
   * still sign in, read what was already delivered and activate a key, which
   * is the difference between a paywall and a locked door. On a deployment
   * that does not sell access this is a no-op.
   */
  app.decorate('requireLicense', async (request: FastifyRequest) => {
    if (!config.LICENSE_REQUIRED) return;
    const { accountId } = auth(request);
    if (!(await isLicensed(accountId))) {
      throw ApiError.forbidden(
        'license_required',
        'This server requires an activated Privio license',
      );
    }
  });
};

export default fp(authPlugin, { name: 'privio-auth' });

/** Narrows `request.auth` for handlers registered behind `requireAuth`. */
export function auth(request: FastifyRequest): AuthContext {
  if (!request.auth) throw ApiError.unauthorized();
  return request.auth;
}
