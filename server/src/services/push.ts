import type { FastifyBaseLogger } from 'fastify';
import { assertResolvesPublicly } from '../util/outbound.js';

export type PushProvider = 'apns' | 'fcm' | 'unifiedpush';

export interface PushTarget {
  deviceId: string;
  provider: PushProvider;
  /** APNs/FCM: the vendor token. UnifiedPush: the distributor endpoint URL. */
  token: string;
}

/**
 * Push payloads carry no content — only a wake-up. The device connects and
 * pulls its envelopes over TLS, so neither Apple nor Google, nor whoever runs
 * a UnifiedPush distributor, ever sees who is messaging whom, let alone what
 * was said.
 */
export interface PushSender {
  notify(target: PushTarget): Promise<void>;
}

/** Default sender for development and tests: records intent, sends nothing. */
export class LoggingPushSender implements PushSender {
  readonly sent: PushTarget[] = [];

  constructor(private readonly log?: FastifyBaseLogger) {}

  async notify(target: PushTarget): Promise<void> {
    this.sent.push(target);
    this.log?.debug({ deviceId: target.deviceId, provider: target.provider }, 'push wake queued');
  }
}

/** The `fetch` shape this file needs, so a test can stand in for the network. */
export type FetchLike = (
  input: string,
  init?: { method?: string; headers?: Record<string, string>; body?: string; signal?: AbortSignal; redirect?: 'error' | 'follow' | 'manual' },
) => Promise<{ ok: boolean; status: number }>;

/**
 * UnifiedPush: a wake-up POSTed to an endpoint the device chose.
 *
 * The endpoint belongs to a distributor app on the user's phone — often ntfy,
 * often self-hosted. That makes this the only place the relay makes an outbound
 * request to a user-supplied address, which is why every send re-resolves the
 * host and refuses anything private. See util/outbound.ts.
 *
 * The body is one byte. UnifiedPush hands the POST body to the app, so anything
 * put here would be content leaving the server through a third party — exactly
 * what the one rule forbids. The device learns "something arrived" and fetches
 * the rest over its own TLS connection.
 */
export class UnifiedPushSender implements PushSender {
  constructor(
    private readonly options: {
      fetch?: FetchLike;
      log?: FastifyBaseLogger;
      timeoutMs?: number;
    } = {},
  ) {}

  async notify(target: PushTarget): Promise<void> {
    const url = new URL(target.token);
    await assertResolvesPublicly(url);

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 5000);
    const send = this.options.fetch ?? (globalThis.fetch as unknown as FetchLike);

    try {
      const response = await send(url.toString(), {
        method: 'POST',
        // No identifiers, no counts, no sender. A wake-up is all it is.
        headers: { 'content-type': 'text/plain', 'ttl': '86400' },
        body: '.',
        signal: controller.signal,
        // A redirect to somewhere else is a redirect to somewhere unvalidated.
        redirect: 'error',
      });
      if (!response.ok) {
        this.options.log?.debug(
          { deviceId: target.deviceId, status: response.status },
          'unifiedpush endpoint refused the wake-up',
        );
      }
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * Routes each target to the sender for its provider.
 *
 * A deployment that has APNs and FCM credentials plugs those in; one that has
 * neither still delivers to UnifiedPush, which is the whole point for a build
 * that ships without Firebase.
 */
export class RoutingPushSender implements PushSender {
  constructor(
    private readonly byProvider: Partial<Record<PushProvider, PushSender>>,
    private readonly fallback: PushSender,
  ) {}

  async notify(target: PushTarget): Promise<void> {
    const sender = this.byProvider[target.provider] ?? this.fallback;
    return sender.notify(target);
  }
}
