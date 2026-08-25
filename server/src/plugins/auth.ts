import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import type { AuthContext } from '../services/sessions.js';
import { resolveSession } from '../services/sessions.js';
import { ApiError } from '../util/errors.js';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthContext;
  }
  interface FastifyInstance {
    requireAuth: (request: FastifyRequest) => Promise<void>;
  }
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

const authPlugin: FastifyPluginAsync = async (app) => {
  app.decorateRequest('auth', undefined);

  app.decorate('requireAuth', async (request: FastifyRequest) => {
    const token = bearerToken(request);
    if (!token) throw ApiError.unauthorized('missing_token', 'Bearer token required');
    const auth = await resolveSession(token);
    if (!auth) throw ApiError.unauthorized('invalid_token', 'Session is invalid or expired');
    request.auth = auth;
  });
};

export default fp(authPlugin, { name: 'privio-auth' });

/** Narrows `request.auth` for handlers registered behind `requireAuth`. */
export function auth(request: FastifyRequest): AuthContext {
  if (!request.auth) throw ApiError.unauthorized();
  return request.auth;
}
