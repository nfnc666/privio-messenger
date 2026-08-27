import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { config, rateLimitFactor } from '../config.js';
import { auth } from '../plugins/auth.js';
import * as licenses from '../services/licenses.js';
import { constantTimeEquals, sha256 } from '../util/crypto.js';
import { ApiError } from '../util/errors.js';
import { parse } from '../util/validate.js';

/**
 * The website is the only caller of the internal endpoints, and it holds a
 * token rather than a session: there is no account behind a payment webhook.
 * Compared as digests so the check cannot be timed.
 */
function requireIssuer(request: FastifyRequest): void {
  if (!config.LICENSE_ISSUER_TOKEN) {
    throw ApiError.forbidden('issuing_disabled', 'License issuing is not configured');
  }
  const header = request.headers.authorization;
  const presented = header?.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (!presented || !constantTimeEquals(sha256(Buffer.from(presented)), sha256(Buffer.from(config.LICENSE_ISSUER_TOKEN)))) {
    throw ApiError.unauthorized('invalid_issuer_token', 'Issuer token is missing or wrong');
  }
}

const paymentSchema = z.object({
  paymentProvider: z.string().trim().min(1).max(32),
  paymentReference: z.string().trim().min(1).max(255),
  source: z.enum(['key', 'apple', 'google']).optional(),
});

const licenseRoutes: FastifyPluginAsync = async (app) => {
  /**
   * Redeem a key.
   *
   * Tightly rate limited: the key is the only credential, so this is the one
   * endpoint where guessing would pay off if it were cheap.
   */
  app.post(
    '/v1/licenses/redeem',
    {
      preHandler: (r) => app.requireAuth(r),
      config: { rateLimit: { max: 5 * rateLimitFactor, timeWindow: '10 minutes' } },
    },
    async (request) => {
      const { accountId } = auth(request);
      const body = parse(z.object({ licenseKey: z.string().min(1).max(64) }), request.body);
      return licenses.redeem(body.licenseKey, accountId);
    },
  );

  /**
   * What the app needs to decide what to show. `required` is what tells a
   * client on a self-hosted server not to ask for a key at all.
   */
  app.get('/v1/licenses/me', { preHandler: (r) => app.requireAuth(r) }, async (request) => {
    const { accountId } = auth(request);
    const status = config.LICENSE_HASH_SECRET
      ? await licenses.statusFor(accountId)
      : { licensed: false };
    return { ...status, required: config.LICENSE_REQUIRED };
  });

  /**
   * Issue a license for a confirmed order. Called by the website from a
   * verified payment webhook — never from a browser.
   *
   * The key comes back exactly once. A retry of the same order is a conflict,
   * not a second key: the caller has to keep what it was given.
   */
  app.post('/v1/internal/licenses', async (request, reply) => {
    requireIssuer(request);
    const body = parse(paymentSchema, request.body);
    const result = await licenses.issueLicense(body);

    if (result.status === 'already_issued') {
      return reply.code(409).send({
        error: 'license_already_issued',
        message: 'This order already has a license; its key cannot be shown again',
        licenseId: result.licenseId,
      });
    }

    reply.code(201);
    return { licenseKey: result.licenseKey, licenseId: result.licenseId };
  });

  /** Chargeback or refund. */
  app.post('/v1/internal/licenses/revoke', async (request) => {
    requireIssuer(request);
    const body = parse(paymentSchema.pick({ paymentProvider: true, paymentReference: true }), request.body);
    const revoked = await licenses.revokeByPayment(body.paymentProvider, body.paymentReference);
    if (!revoked) throw ApiError.notFound('license_not_found', 'No active license for that order');
    return { revoked: true };
  });
};

export default licenseRoutes;
