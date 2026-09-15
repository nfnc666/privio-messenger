import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { pool, withTransaction } from '../db/pool.js';
import { auth } from '../plugins/auth.js';
import { lastSeenFor } from '../services/presence.js';
import * as phone from '../services/phone.js';
import { SmsUnavailable, type SmsSender } from '../services/sms.js';
import { hashSecret, verifySecret } from '../util/crypto.js';
import { ApiError } from '../util/errors.js';
import { base64Bytes, parse } from '../util/validate.js';
import { rateLimitFactor } from '../config.js';

/**
 * A phone number somebody chose to attach, and finding contacts by one.
 *
 * Three rules shape every route below, and they are the brief's rather than
 * this file's invention:
 *
 * 1. **The number is never an identity.** Nothing here signs anybody in,
 *    recovers anything, or merges two accounts. A number is a lookup key.
 * 2. **Two separate consents.** Attaching a number and being findable by it are
 *    different decisions, and the second defaults to off.
 * 3. **Nothing anybody submits for matching is stored.** A lookup is answered
 *    and forgotten. The only thing written is the counter that limits how much
 *    looking one account may do.
 *
 * What the hashing does and does not protect is in `services/phone.ts`, in
 * full, including what it is *not* — and none of it claims parity with any
 * other messenger's design.
 */

/** A number's worth of guessing, per address. Codes are six digits. */
const guessable = {
  config: {
    rateLimit: {
      max: 10 * rateLimitFactor,
      timeWindow: '5 minutes',
      keyGenerator: (request: { ip: string }) => request.ip,
    },
  },
};

interface LinkRow {
  account_id: string;
  hint: string;
  discoverable: boolean;
  verified_at: Date;
}

/** What the settings screen shows about this account's own number. */
function linkJson(row: LinkRow | undefined) {
  if (!row) return { linked: false, hint: null, discoverable: false, verifiedAt: null };
  return {
    linked: true,
    // The hint, never the number: this server cannot return the number because
    // it does not have it.
    hint: row.hint,
    discoverable: row.discoverable,
    verifiedAt: row.verified_at.toISOString(),
  };
}

export function phoneRoutes(sms: SmsSender): FastifyPluginAsync {
  return async (app) => {
    const requireAuth = {
      preHandler: (r: Parameters<typeof app.requireAuth>[0]) => app.requireAuth(r),
    };

    /** Refuses early when this deployment cannot do discovery at all. */
    function requireDiscovery(): void {
      if (!phone.discoveryConfigured()) {
        throw ApiError.badRequest(
          'discovery_not_configured',
          'This server has no contact-discovery key configured.',
        );
      }
    }

    // --- The account's own number --------------------------------------------

    app.get('/v1/phone', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const { rows } = await pool.query<LinkRow>(
        'SELECT * FROM phone_links WHERE account_id = $1',
        [accountId],
      );
      const { rows: settings } = await pool.query<{ contact_sync_enabled: boolean }>(
        'SELECT contact_sync_enabled FROM accounts WHERE id = $1',
        [accountId],
      );
      return {
        ...linkJson(rows[0]),
        contactSync: settings[0]?.contact_sync_enabled ?? false,
        // So the app can say "this server cannot send texts" rather than
        // offering a button that always fails.
        smsAvailable: sms.kind !== 'none',
        discoveryAvailable: phone.discoveryConfigured(),
      };
    });

    /**
     * Starts a verification: normalise, store a hashed code, send a text.
     *
     * The plaintext number exists in this process for the length of this
     * request, because a text has to be addressed to something. It is not
     * written to the database, not returned, and not logged.
     */
    app.post('/v1/phone/verifications', { ...requireAuth, ...guessable }, async (request) => {
      const { accountId } = auth(request);
      requireDiscovery();
      const body = parse(z.object({ phone: z.string().min(1).max(32) }), request.body);

      const normalised = phone.normalisePhone(body.phone);
      if (!normalised) {
        throw ApiError.badRequest('invalid_phone', 'That is not a phone number Privio can use.');
      }

      const hash = phone.hashesFor(normalised.e164);

      // A number already verified by *this* account is already done.
      const { rows: mine } = await pool.query<{ discovery_hash: Buffer }>(
        'SELECT discovery_hash FROM phone_links WHERE account_id = $1',
        [accountId],
      );
      if (mine[0] && phone.sameHash(mine[0].discovery_hash, hash)) {
        throw ApiError.badRequest('phone_unchanged', 'That number is already verified.');
      }

      const existing = await liveVerification(accountId);
      if (existing) {
        const sameNumber = phone.sameHash(existing.discovery_hash, hash);
        const waited = Date.now() - existing.last_sent_at.getTime();
        if (sameNumber) {
          if (existing.sends >= phone.PHONE_LIMITS.maxSends) {
            throw ApiError.tooManyRequests(
              'too_many_sends',
              'That code has been sent as many times as Privio will send it. Try again later.',
            );
          }
          if (waited < phone.PHONE_LIMITS.resendAfterSeconds * 1000) {
            throw ApiError.tooManyRequests('resend_too_soon', 'Wait a moment before asking again.');
          }
        }
      }

      const code = phone.generateCode();
      const codeHash = await hashSecret(code);

      // Sent *before* the row is committed, so a provider failure does not leave
      // a verification somebody can never complete. The cost is that a send
      // which succeeds and then fails to store asks for one extra code, which is
      // the better of the two failures.
      try {
        await sms.send(normalised.e164, code);
      } catch (error) {
        if (error instanceof SmsUnavailable) {
          throw ApiError.badRequest('sms_not_configured', error.message);
        }
        throw error;
      }

      const expiresAt = new Date(Date.now() + phone.PHONE_LIMITS.codeTtlSeconds * 1000);
      await withTransaction(async (client) => {
        // One live verification per account: asking for a different number
        // abandons the previous attempt rather than running two.
        await client.query(
          `UPDATE phone_verifications SET consumed_at = now()
            WHERE account_id = $1 AND consumed_at IS NULL
              AND discovery_hash <> $2`,
          [accountId, hash],
        );
        await client.query(
          `INSERT INTO phone_verifications
             (account_id, discovery_hash, hint, code_hash, expires_at)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (account_id) WHERE consumed_at IS NULL
           DO UPDATE SET code_hash = EXCLUDED.code_hash,
                         expires_at = EXCLUDED.expires_at,
                         attempts = 0,
                         sends = phone_verifications.sends + 1,
                         last_sent_at = now()`,
          [accountId, hash, normalised.hint, codeHash, expiresAt],
        );
      });

      return {
        hint: normalised.hint,
        expiresAt: expiresAt.toISOString(),
        attemptsAllowed: phone.PHONE_LIMITS.maxAttempts,
        // Only ever present on a development stub, and named so that nothing
        // reads it as a delivered message. See `services/sms.ts`.
        ...(sms.kind === 'development-echo' ? { developmentStub: true, code } : {}),
      };
    });

    /** Checks a code and, if it is right, links the number. */
    app.post('/v1/phone', { ...requireAuth, ...guessable }, async (request) => {
      const { accountId } = auth(request);
      requireDiscovery();
      const body = parse(z.object({ code: z.string().regex(/^\d{6}$/) }), request.body);

      const pending = await liveVerification(accountId);
      if (!pending) {
        throw ApiError.badRequest('no_verification', 'Ask for a code first.');
      }
      if (pending.expires_at.getTime() <= Date.now()) {
        throw ApiError.badRequest('code_expired', 'That code has expired. Ask for a new one.');
      }
      if (pending.attempts >= phone.PHONE_LIMITS.maxAttempts) {
        throw ApiError.tooManyRequests(
          'too_many_attempts',
          'Too many wrong codes. Ask for a new one.',
        );
      }

      const correct = await verifySecret(pending.code_hash, body.code);
      if (!correct) {
        // Counted before the answer goes out, so a client that hangs up on the
        // response has still spent the attempt.
        await pool.query(
          'UPDATE phone_verifications SET attempts = attempts + 1 WHERE id = $1',
          [pending.id],
        );
        throw ApiError.badRequest('wrong_code', 'That code is not right.');
      }

      const row = await withTransaction(async (client) => {
        await client.query('UPDATE phone_verifications SET consumed_at = now() WHERE id = $1', [
          pending.id,
        ]);

        // A number belongs to whoever proved it *last*. Somebody who took over
        // a recycled number can attach it; the previous holder's link goes.
        // This is not a merge — the other account keeps everything it had and
        // simply stops being findable by that number.
        await client.query(
          'DELETE FROM phone_links WHERE discovery_hash = $1 AND account_id <> $2',
          [pending.discovery_hash, accountId],
        );

        const { rows } = await client.query<LinkRow>(
          `INSERT INTO phone_links (account_id, discovery_hash, hint, verified_at)
           VALUES ($1, $2, $3, now())
           ON CONFLICT (account_id) DO UPDATE
             SET discovery_hash = EXCLUDED.discovery_hash,
                 hint = EXCLUDED.hint,
                 verified_at = now(),
                 -- A changed number is not covered by the consent given for the
                 -- old one. Being findable has to be chosen again.
                 discoverable = false
           RETURNING *`,
          [accountId, pending.discovery_hash, pending.hint],
        );
        return rows[0]!;
      });

      return linkJson(row);
    });

    /** Turns discoverability on or off. Nothing else about the link changes. */
    app.put('/v1/phone/discoverable', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const body = parse(z.object({ discoverable: z.boolean() }), request.body);
      const { rows } = await pool.query<LinkRow>(
        'UPDATE phone_links SET discoverable = $2 WHERE account_id = $1 RETURNING *',
        [accountId, body.discoverable],
      );
      if (!rows[0]) throw ApiError.notFound('no_phone', 'No verified number on this account.');
      return linkJson(rows[0]);
    });

    /** Whether this account syncs its device contacts. */
    app.put('/v1/phone/contact-sync', requireAuth, async (request) => {
      const { accountId } = auth(request);
      const body = parse(z.object({ enabled: z.boolean() }), request.body);
      await pool.query('UPDATE accounts SET contact_sync_enabled = $2 WHERE id = $1', [
        accountId,
        body.enabled,
      ]);
      return { contactSync: body.enabled };
    });

    /**
     * Removes the number.
     *
     * The row goes entirely rather than being marked inactive: the point of
     * removing a number is that the server stops holding the thing that links it
     * to this account, and a soft delete would keep exactly that.
     */
    app.delete('/v1/phone', requireAuth, async (request) => {
      const { accountId } = auth(request);
      await withTransaction(async (client) => {
        await client.query('DELETE FROM phone_links WHERE account_id = $1', [accountId]);
        await client.query('DELETE FROM phone_verifications WHERE account_id = $1', [accountId]);
      });
      return { linked: false };
    });

    // --- Finding contacts ----------------------------------------------------

    /**
     * Matches blinded numbers against accounts that chose to be findable.
     *
     * What arrives is a list of HMACs, never numbers, and **nothing about this
     * request is written** except the counter that limits it. The budget is the
     * real defence against walking the number space: the hashing protects data
     * at rest, not against an account that asks a great many questions.
     *
     * Only accounts with a *verified* number and discoverability *on* can ever
     * be an answer. Both conditions live in the SQL rather than in a filter
     * afterwards, so there is no path that returns somebody who did not ask to
     * be found.
     */
    app.post(
      '/v1/contacts/discover',
      {
        ...requireAuth,
        config: { rateLimit: { max: 20 * rateLimitFactor, timeWindow: '1 hour' } },
      },
      async (request) => {
        const { accountId } = auth(request);
        requireDiscovery();
        const body = parse(
          z.object({
            // 32 bytes each: an HMAC-SHA256, base64. Anything else is refused
            // rather than hashed, so a client cannot submit a plaintext number
            // by accident and have it silently work.
            blinded: z
              .array(base64Bytes(32, 32))
              .min(1)
              .max(phone.PHONE_LIMITS.lookupsPerRequest),
          }),
          request.body,
        );

        const spent = await spendBudget(accountId, body.blinded.length);
        if (!spent) {
          throw ApiError.tooManyRequests(
            'lookup_budget_spent',
            'Privio has matched as many numbers for this account today as it will.',
          );
        }

        // Already Buffers: `base64Bytes` decodes and checks the length, so a
        // plaintext number cannot arrive here dressed as a hash.
        const hashes = body.blinded.map(phone.discoveryHash);

        const { rows } = await pool.query(
          `SELECT a.id, a.username, a.display_name, a.avatar_media_id, a.avatar_updated_at,
                  a.privacy, a.last_seen_at, p.discovery_hash
             FROM phone_links p
             JOIN accounts a ON a.id = p.account_id
            WHERE p.discoverable
              AND p.discovery_hash = ANY($1::bytea[])
              AND a.deleted_at IS NULL
              AND a.id <> $2
              AND NOT a.is_bot
              -- Somebody who blocked you does not turn up in your contacts.
              AND NOT EXISTS (
                SELECT 1 FROM blocks b
                 WHERE b.account_id = a.id AND b.blocked_account_id = $2
              )`,
          [hashes, accountId],
        );

        return {
          matches: rows.map((row) => ({
            // Which of the submitted entries this answers, so the client can put
            // a name to it from its own address book without the server ever
            // being told one.
            blinded: Buffer.from(row.discovery_hash as Buffer).toString('base64'),
            id: row.id,
            username: row.username,
            displayName: row.display_name,
            avatarMediaId: row.avatar_media_id,
            avatarUpdatedAt: (row.avatar_updated_at as Date | null)?.toISOString() ?? null,
            lastSeenAt: lastSeenFor(
              { privacy: row.privacy, last_seen_at: row.last_seen_at as Date },
              false,
            ),
          })),
          budgetRemaining: spent.remaining,
        };
      },
    );
  };
}

/** The verification in flight for this account, if there is one. */
async function liveVerification(accountId: string) {
  const { rows } = await pool.query<{
    id: string;
    discovery_hash: Buffer;
    hint: string;
    code_hash: string;
    expires_at: Date;
    attempts: number;
    sends: number;
    last_sent_at: Date;
  }>(
    'SELECT * FROM phone_verifications WHERE account_id = $1 AND consumed_at IS NULL',
    [accountId],
  );
  return rows[0];
}

/**
 * Takes `count` out of today's lookup budget, or refuses.
 *
 * One statement so two requests in flight cannot both see room for the last
 * hundred: the `WHERE` is part of the same `INSERT … ON CONFLICT` that
 * increments, so a row that would go over simply does not update and the caller
 * is told no.
 */
async function spendBudget(accountId: string, count: number): Promise<{ remaining: number } | null> {
  const { rows } = await pool.query<{ looked_up: number }>(
    `INSERT INTO contact_lookup_budget (account_id, day, looked_up)
     VALUES ($1, current_date, $2)
     ON CONFLICT (account_id, day) DO UPDATE
       SET looked_up = contact_lookup_budget.looked_up + $2
       WHERE contact_lookup_budget.looked_up + $2 <= $3
     RETURNING looked_up`,
    [accountId, count, phone.PHONE_LIMITS.lookupsPerDay],
  );
  const row = rows[0];
  if (!row) return null;
  return { remaining: Math.max(0, phone.PHONE_LIMITS.lookupsPerDay - row.looked_up) };
}

export default phoneRoutes;
