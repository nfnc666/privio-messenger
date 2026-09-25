import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { pool } from '../db/pool.js';
import { assertResolvesPublicly } from '../util/outbound.js';
import { takeUpdates } from './bots.js';

/**
 * Posting a bot's updates to a URL instead of making it poll for them.
 *
 * **One delivery, two possible paths.** An update is taken from `bot_messages`
 * exactly once — the same `UPDATE … RETURNING` over `FOR UPDATE SKIP LOCKED`
 * that the long poll uses — so a bot with a webhook registered cannot also
 * receive that message by polling. Whichever asks first gets it, and there is
 * no arrangement in which both do.
 *
 * That also decides what happens when a webhook is failing: nothing is lost.
 * A delivery that never succeeded never took the rows, so they are still there
 * for the next attempt or for a poller.
 */

/** How the delivery loop behaves. */
export const WEBHOOK_LIMITS = {
  /** Updates per delivery. A receiver gets a batch, not one request each. */
  batch: 50,
  /** How long a receiver has to answer before the attempt is abandoned. */
  timeoutMs: 8_000,
  /**
   * Consecutive failures before the webhook is switched off.
   *
   * Switched off rather than retried forever: a URL that has refused a hundred
   * times in a row is not coming back on its own, and a server that keeps
   * trying is a server making requests somebody else has to absorb. The bot
   * falls back to polling, which still works.
   */
  maxFailures: 20,
  /** The loop's interval. */
  tickMs: 1_000,
} as const;

export interface WebhookRow {
  bot_id: string;
  url: string;
  secret: Buffer;
  failures: number;
  disabled_at: Date | null;
}

/** A new signing secret. Shown to the owner once and never again. */
export function newSecret(): Buffer {
  return randomBytes(32);
}

/**
 * The signature a receiver should check.
 *
 * Over `${timestamp}.${body}` rather than the body alone, so a delivery
 * captured off the wire cannot be replayed against the receiver a day later
 * and still verify. The receiver is expected to reject a timestamp that is far
 * from now; `docs/bot-api.md` says so and the Python client does it.
 */
export function signatureFor(secret: Buffer, timestamp: string, body: string): string {
  return createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
}

/**
 * Whether a signature matches, compared in constant time.
 *
 * Exported because the Python client is not the only possible receiver and a
 * test has to be able to check the same way a receiver would.
 */
export function signatureMatches(
  secret: Buffer,
  timestamp: string,
  body: string,
  provided: string,
): boolean {
  const expected = Buffer.from(signatureFor(secret, timestamp, body), 'utf8');
  const given = Buffer.from(provided, 'utf8');
  if (expected.length !== given.length) return false;
  return timingSafeEqual(expected, given);
}

/** Registers or replaces a bot's webhook, returning the secret to show once. */
export async function setWebhook(botId: string, url: string): Promise<Buffer> {
  const secret = newSecret();
  await pool.query(
    `INSERT INTO bot_webhooks (bot_id, url, secret)
     VALUES ($1, $2, $3)
     ON CONFLICT (bot_id) DO UPDATE
        SET url = EXCLUDED.url,
            secret = EXCLUDED.secret,
            failures = 0,
            disabled_at = NULL,
            last_status = NULL,
            last_error = NULL`,
    [botId, url, secret],
  );
  return secret;
}

export async function clearWebhook(botId: string): Promise<void> {
  await pool.query('DELETE FROM bot_webhooks WHERE bot_id = $1', [botId]);
}

/** What the owner is shown: everything except the secret. */
export async function webhookStatus(botId: string): Promise<{
  url: string;
  failures: number;
  disabled: boolean;
  lastAttemptAt: string | null;
  lastStatus: number | null;
  lastError: string | null;
} | null> {
  const { rows } = await pool.query(
    `SELECT url, failures, disabled_at, last_attempt_at, last_status, last_error
       FROM bot_webhooks WHERE bot_id = $1`,
    [botId],
  );
  const row = rows[0];
  if (!row) return null;
  return {
    url: row.url as string,
    failures: row.failures as number,
    disabled: row.disabled_at !== null,
    lastAttemptAt: (row.last_attempt_at as Date | null)?.toISOString() ?? null,
    lastStatus: row.last_status as number | null,
    lastError: row.last_error as string | null,
  };
}

/**
 * Delivers one batch to one webhook.
 *
 * Returns whether anything was sent, so the loop can tell a quiet tick from a
 * busy one. Failures are recorded and counted; they never throw out of here,
 * because one bot's broken receiver must not stop the loop for every other.
 */
export async function deliverOnce(hook: WebhookRow): Promise<boolean> {
  // Re-checked before every delivery, not only at registration: a name that
  // resolved publicly last week may resolve to 10.0.0.5 today, and this is
  // the request that would go there.
  let url: URL;
  try {
    url = new URL(hook.url);
    await assertResolvesPublicly(url);
  } catch (error) {
    await noteFailure(hook.bot_id, null, describe(error));
    return false;
  }

  const updates = await takeUpdates(hook.bot_id, WEBHOOK_LIMITS.batch);
  if (updates.length === 0) return false;
  return postDelivery(hook, url, updates);
}

/**
 * Signs and POSTs one batch that has already been taken.
 *
 * Separate from [deliverOnce] so each half can be tested for what it actually
 * does: the address check above refuses every address a test could listen on —
 * correctly, and it must keep doing so — while this half can be pointed at a
 * receiver a test runs, and the signature it produces checked by hand. Nothing
 * outside this module and its test calls it: the loop goes through
 * [deliverOnce], so the guard is never skipped in production.
 */
export async function postDelivery(
  hook: WebhookRow,
  url: URL,
  updates: unknown[],
): Promise<boolean> {
  const timestamp = String(Date.now());
  const body = JSON.stringify({ updates });
  const signature = signatureFor(hook.secret, timestamp, body);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), WEBHOOK_LIMITS.timeoutMs);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // Not the bot's token. A receiver learns how to verify a delivery and
        // nothing that would let it act as the bot.
        'x-privio-timestamp': timestamp,
        'x-privio-signature': `sha256=${signature}`,
      },
      body,
      signal: controller.signal,
      redirect: 'error',
    });
    if (!response.ok) {
      await noteFailure(hook.bot_id, response.status, `HTTP ${response.status}`);
      return true;
    }
    await pool.query(
      `UPDATE bot_webhooks
          SET failures = 0, disabled_at = NULL,
              last_attempt_at = now(), last_status = $2, last_error = NULL
        WHERE bot_id = $1`,
      [hook.bot_id, response.status],
    );
    return true;
  } catch (error) {
    await noteFailure(hook.bot_id, null, describe(error));
    return true;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * What went wrong, in at most two hundred characters and with nothing secret
 * in it.
 *
 * An error from `fetch` can carry the URL, which is the owner's own and safe,
 * but never a header — and headers are where the signature lives. Truncated
 * because this is shown back to the owner and stored.
 */
function describe(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.slice(0, 200);
}

async function noteFailure(botId: string, status: number | null, error: string): Promise<void> {
  await pool.query(
    `UPDATE bot_webhooks
        SET failures = failures + 1,
            last_attempt_at = now(),
            last_status = $2,
            last_error = $3,
            disabled_at = CASE
              WHEN failures + 1 >= $4 THEN now()
              ELSE disabled_at
            END
      WHERE bot_id = $1`,
    [botId, status, error, WEBHOOK_LIMITS.maxFailures],
  );
}

/**
 * One pass over every live webhook.
 *
 * Backoff is by failure count rather than a timer per hook: a hook that has
 * failed n times is skipped on all but every 2^n-th tick, capped, which costs
 * nothing to store and slows a broken receiver down without a scheduler.
 */
export async function webhookTick(): Promise<number> {
  const { rows } = await pool.query<WebhookRow>(
    `SELECT bot_id, url, secret, failures, disabled_at
       FROM bot_webhooks
      WHERE disabled_at IS NULL`,
  );

  let delivered = 0;
  for (const hook of rows) {
    if (!dueNow(hook.failures)) continue;
    if (await deliverOnce(hook)) delivered += 1;
  }
  return delivered;
}

/** Whether a hook with this many consecutive failures should be tried now. */
export function dueNow(failures: number, now: number = Date.now()): boolean {
  if (failures === 0) return true;
  const everyTicks = Math.min(2 ** failures, 300);
  const tick = Math.floor(now / WEBHOOK_LIMITS.tickMs);
  return tick % everyTicks === 0;
}

/** Runs [webhookTick] on an interval. Returns the stopper, like the sweeper. */
export function startWebhookLoop(onError: (error: unknown) => void): () => void {
  const timer = setInterval(() => {
    void webhookTick().catch(onError);
  }, WEBHOOK_LIMITS.tickMs);
  timer.unref?.();
  return () => clearInterval(timer);
}
