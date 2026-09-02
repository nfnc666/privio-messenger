import type { FastifyPluginAsync } from 'fastify';
import { iceConfiguration } from '../services/ice.js';

/**
 * What a call needs from the server, which is as little as possible.
 *
 * Signalling is not here: an offer, an answer and every candidate travel as
 * ordinary sealed envelopes, so the server routes a call knowing exactly what
 * it knows about a message. The only thing left to ask for is where to find a
 * STUN or TURN server, and credentials for it.
 */
const callRoutes: FastifyPluginAsync = async (app) => {
  const requireAuth = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  /**
   * Authenticated, because TURN credentials are relay capacity: published
   * openly they would be someone else's bandwidth within a day.
   *
   * Clients are expected to fetch this when they connect and hold it until it
   * expires, not when a call starts. Asking at the moment of a call would tell
   * the server that a call is about to happen, which is a piece of metadata it
   * otherwise does not get.
   */
  app.get('/v1/calls/ice', requireAuth, async () => iceConfiguration());
};

export default callRoutes;
