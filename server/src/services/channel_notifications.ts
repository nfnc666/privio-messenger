import { pool } from '../db/pool.js';
import type { FastifyBaseLogger } from 'fastify';
import type { PushSender, PushTarget } from './push.js';

/**
 * Waking people up about a new channel post.
 *
 * **Contentless, like every other push in Privio.** The server holds ciphertext
 * and no key; it could not say what a post contains even if it wanted to. What
 * goes out is "something happened, come and look", and the device decrypts what
 * it finds. So there is nothing here that decides what a notification *says* —
 * that is the app's, on the far side of the key.
 *
 * **Who is skipped, and why each one:**
 *
 *   - the author, on every device: publishing something is not news to you;
 *   - anybody who muted the channel, unless their mute has run out — which is
 *     what finally makes the mute from migration 025 do something. Until this
 *     existed, channel posts raised no push at all, so muting one suppressed
 *     nothing;
 *   - anybody silenced in the channel — they can still read, but a channel that
 *     has stopped them speaking does not also buzz their phone;
 *   - a device with no push token, which is most of them in a test.
 *
 * **The one thing to be careful about** is notifying twice. `notified_at` is
 * set in the same statement that selects the row, so a retry, a restart, or the
 * sweeper passing over the same post cannot send a second time.
 */
export class ChannelNotifier {
  constructor(
    private readonly push: PushSender,
    private readonly log?: FastifyBaseLogger,
  ) {}

  /**
   * Sends the wake-ups for one post, if it has not already had them.
   *
   * Returns how many devices were told, which is what the tests assert on and
   * what makes "nobody, because everybody muted it" a visible outcome rather
   * than an invisible one.
   */
  async notifyPost(postId: number): Promise<number> {
    // Claim it first. The UPDATE is the lock: two requests racing to notify the
    // same post cannot both win, because only one of them changes a row.
    const { rows: claimed } = await pool.query<{ channel_id: string; author_account_id: string | null }>(
      `UPDATE channel_posts
          SET notified_at = now()
        WHERE id = $1
          AND notified_at IS NULL
          AND deleted_at IS NULL
          AND (publish_at IS NULL OR publish_at <= now())
        RETURNING channel_id, author_account_id`,
      [postId],
    );
    const post = claimed[0];
    if (!post) return 0;

    return this.wakeMembers(post.channel_id, post.author_account_id);
  }

  /**
   * Sends the wake-ups for posts that have become visible since the last pass.
   *
   * This is the part that revisits migration 018. A scheduled post is visible
   * because its `publish_at` has passed — no worker needed, and that property is
   * kept. Only the notification needs something to happen at a moment, so this
   * runs on a short interval and sends what came due.
   *
   * If it stops running, a scheduled post still publishes on time and only its
   * push is missed. That is the failure this design is willing to have.
   */
  async sweep(limit = 200): Promise<number> {
    const { rows } = await pool.query<{ id: string; channel_id: string; author_account_id: string | null }>(
      `UPDATE channel_posts SET notified_at = now()
        WHERE id IN (
          SELECT id FROM channel_posts
           WHERE notified_at IS NULL
             AND deleted_at IS NULL
             AND publish_at IS NOT NULL
             AND publish_at <= now()
           ORDER BY publish_at
           LIMIT $1
           FOR UPDATE SKIP LOCKED
        )
        RETURNING id, channel_id, author_account_id`,
      [limit],
    );

    let woken = 0;
    for (const post of rows) {
      woken += await this.wakeMembers(post.channel_id, post.author_account_id);
    }
    return woken;
  }

  /** Every device that should hear about something in this channel. */
  private async wakeMembers(channelId: string, authorAccountId: string | null): Promise<number> {
    const { rows } = await pool.query<{
      id: string;
      push_provider: PushTarget['provider'];
      push_token: string;
    }>(
      `SELECT d.id, d.push_provider, d.push_token
         FROM channel_members m
         JOIN devices d ON d.account_id = m.account_id AND d.revoked_at IS NULL
        WHERE m.channel_id = $1
          AND ($2::uuid IS NULL OR m.account_id <> $2)
          AND d.push_provider IS NOT NULL
          AND d.push_token IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM channel_mutes mu
             WHERE mu.channel_id = $1 AND mu.account_id = m.account_id
               AND (mu.until IS NULL OR mu.until > now())
          )
          AND NOT EXISTS (
            SELECT 1 FROM channel_bans b
             WHERE b.channel_id = $1 AND b.account_id = m.account_id
          )`,
      [channelId, authorAccountId],
    );

    await Promise.all(
      rows.map(async (row) => {
        try {
          await this.push.notify({
            deviceId: row.id,
            provider: row.push_provider,
            token: row.push_token,
            urgency: 'normal',
          });
        } catch (err) {
          // A failed wake-up is somebody else's endpoint being wrong, and the
          // post is already published. It must not turn a successful publish
          // into an error the author sees and retries.
          this.log?.debug({ deviceId: row.id, err }, 'channel wake failed');
        }
      }),
    );
    return rows.length;
  }
}

/**
 * Starts the sweep for scheduled posts. Returns a stop function.
 *
 * A minute, because that is the worst a notification should be late by and
 * still be a notification. Visibility is not affected either way.
 */
export function startChannelNotificationSweeper(
  notifier: ChannelNotifier,
  onError: (err: unknown) => void,
  intervalMs = 60_000,
): () => void {
  const timer = setInterval(() => {
    notifier.sweep().catch(onError);
  }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
