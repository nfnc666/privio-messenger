import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import { normalisePhone } from '../services/phone.js';
import { ApiError } from '../util/errors.js';
import { parse } from '../util/validate.js';

/** No SMS, discovery, login or recovery code imports this private annotation. */
const accountPhoneRoutes: FastifyPluginAsync = async (app) => {
  const guard = { preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r) };

  async function ownNote(accountId: string) {
    const { rows } = await pool.query(
      `SELECT (SELECT phone_number FROM account_phone_notes WHERE account_id=$1) AS "phoneNumber",
              EXISTS(SELECT 1 FROM phone_links WHERE account_id=$1) AS "hasVerifiedNumber"`,
      [accountId],
    );
    return { ...rows[0], verified: false, usedForDiscovery: false };
  }

  app.get('/v1/accounts/me/phone-note', guard, async (request) => ownNote(auth(request).accountId));

  app.put('/v1/accounts/me/phone-note', guard, async (request) => {
    const { accountId } = auth(request);
    // Strict: caller-supplied accountId / verified / discoverable flags are not accepted.
    const body = parse(z.object({ phoneNumber: z.string().trim().max(64).nullable() }).strict(), request.body);
    const input = body.phoneNumber;
    if (input === null || input.length === 0) {
      await pool.query('DELETE FROM account_phone_notes WHERE account_id=$1', [accountId]);
    } else {
      const parsed = normalisePhone(input);
      if (!parsed) throw ApiError.badRequest('phone_invalid', 'Use an international phone number with a calling code');
      await pool.query(
        `INSERT INTO account_phone_notes(account_id,phone_number) VALUES($1,$2)
         ON CONFLICT(account_id) DO UPDATE SET phone_number=EXCLUDED.phone_number,updated_at=now()`,
        [accountId, parsed.e164],
      );
    }
    return ownNote(accountId);
  });

  app.delete('/v1/accounts/me/phone-note', guard, async (request) => {
    const { accountId } = auth(request);
    await pool.query('DELETE FROM account_phone_notes WHERE account_id=$1', [accountId]);
    return ownNote(accountId);
  });
};
export default accountPhoneRoutes;
