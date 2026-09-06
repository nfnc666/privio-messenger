import type { FastifyBaseLogger } from 'fastify';
import { assertResolvesPublicly } from '../util/outbound.js';

export type PushProvider = 'apns' | 'fcm' | 'unifiedpush';

export interface PushTarget {
  deviceId: string;
  provider: PushProvider;
  /** APNs/FCM: the vendor token. UnifiedPush: the distributor endpoint URL. */
  token: string;
  /**
   * What kind of wake-up this is.
   *
   * Not content — it says nothing about who or what — but it does change how
   * hard the operating system tries. A message may wait for a batching window;
   * a ringing phone may not, and on iOS a call arrives on a different token
   * and a different push type entirely (see [voipToken]).
   */
  urgency?: 'normal' | 'call';
  /**
   * iOS only: the PushKit token, which is not the same token as the one used
   * for everything else and has its own APNs topic.
   *
   * Apple gives VoIP pushes their own registry precisely because they are
   * allowed to launch a killed app — and requires, in exchange, that every one
   * of them reports an incoming call to CallKit. So it is used for calls and
   * for nothing else: sending a message wake-up on it would mean either lying
   * to CallKit or having the app terminated.
   */
  voipToken?: string | null;
}

/**
 * What became of a wake-up.
 *
 * `gone` is the answer worth having: the vendor is saying this token is dead —
 * the app was uninstalled, or the token was reissued and this is the old one.
 * A relay that keeps it goes on making a request per message forever, for a
 * device that will never hear it.
 */
export type PushOutcome = 'sent' | 'gone';

/**
 * Push payloads carry no content — only a wake-up. The device connects and
 * pulls its envelopes over TLS, so neither Apple nor Google, nor whoever runs
 * a UnifiedPush distributor, ever sees who is messaging whom, let alone what
 * was said.
 */
export interface PushSender {
  notify(target: PushTarget): Promise<PushOutcome>;
}

/** Default sender for development and tests: records intent, sends nothing. */
export class LoggingPushSender implements PushSender {
  readonly sent: PushTarget[] = [];

  constructor(private readonly log?: FastifyBaseLogger) {}

  async notify(target: PushTarget): Promise<PushOutcome> {
    this.sent.push(target);
    this.log?.debug({ deviceId: target.deviceId, provider: target.provider }, 'push wake queued');
    return 'sent';
  }
}

/** The `fetch` shape this file needs, so a test can stand in for the network. */
export type FetchLike = (
  input: string,
  init?: { method?: string; headers?: Record<string, string>; body?: string; signal?: AbortSignal; redirect?: 'error' | 'follow' | 'manual' },
) => Promise<{ ok: boolean; status: number; text?: () => Promise<string> }>;

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

  async notify(target: PushTarget): Promise<PushOutcome> {
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
        // 404 and 410 from a distributor mean this endpoint is finished — the
        // app unregistered, or the distributor dropped the topic. Anything
        // else is the distributor having a bad day, and the endpoint is kept.
        if (response.status === 404 || response.status === 410) return 'gone';
      }
      return 'sent';
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

  async notify(target: PushTarget): Promise<PushOutcome> {
    const sender = this.byProvider[target.provider] ?? this.fallback;
    return sender.notify(target);
  }
}

/**
 * Apple Push Notification service.
 *
 * Two things about this are not obvious, and both are why it is written out
 * rather than taken from a library:
 *
 * **The payload is empty on purpose.** A message wake-up is
 * `apns-push-type: background` with `content-available: 1` and no alert, so
 * Apple never carries a word of anyone's conversation. What the user sees is
 * composed on the device after it has fetched and decrypted — which is the
 * only place the plaintext exists. The cost is that iOS decides when to
 * deliver a background push, and may decide "later" or "not at all"; that is a
 * real limit and it is documented rather than papered over.
 *
 * **A call is a different push on a different token.** `apns-push-type: voip`
 * reaches a killed app immediately, which is the only way a phone rings — and
 * in exchange iOS requires the app to report a call to CallKit every single
 * time. So VoIP is used for call signals and nothing else.
 */
export class ApnsSender implements PushSender {
  constructor(
    private readonly options: {
      /** The `<team>.<key-id>` signed JWT, refreshed by the caller. */
      authorization: () => Promise<string>;
      /** The app's bundle identifier. The VoIP topic is this plus `.voip`. */
      topic: string;
      /** `https://api.push.apple.com` or the sandbox host. */
      host?: string;
      fetch?: FetchLike;
      log?: FastifyBaseLogger;
      timeoutMs?: number;
    },
  ) {}

  async notify(target: PushTarget): Promise<PushOutcome> {
    const isCall = target.urgency === 'call';
    // A call goes to the PushKit registry or it does not go at all: sending a
    // call as a background push would arrive whenever iOS felt like it, which
    // for a ringing phone is the same as never.
    const token = isCall ? target.voipToken : target.token;
    if (!token) return 'sent';

    const host = this.options.host ?? 'https://api.push.apple.com';
    const send = this.options.fetch ?? (globalThis.fetch as unknown as FetchLike);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 5000);

    try {
      const response = await send(`${host}/3/device/${token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${await this.options.authorization()}`,
          'apns-topic': isCall ? `${this.options.topic}.voip` : this.options.topic,
          'apns-push-type': isCall ? 'voip' : 'background',
          // 10 is "now". 5 is "when it suits the battery", which is the right
          // answer for a message and the wrong one for a telephone.
          'apns-priority': isCall ? '10' : '5',
          // Nothing here is worth waking a phone for tomorrow: the envelope is
          // on the server and the next launch collects it either way.
          'apns-expiration': String(Math.floor(Date.now() / 1000) + (isCall ? 60 : 3600)),
          'content-type': 'application/json',
        },
        // `content-available` and nothing else. No alert, no badge, no sound,
        // no sender, no count — Apple relays a fact with no subject.
        body: isCall ? JSON.stringify({ aps: {} }) : JSON.stringify({ aps: { 'content-available': 1 } }),
        signal: controller.signal,
      });

      // 410 is Apple's "this token is dead". 400 with BadDeviceToken is the
      // same thing said at registration time, for a token that never was.
      if (response.status === 410) return 'gone';
      if (response.status === 400) {
        const body = (await response.text?.()) ?? '';
        if (body.includes('BadDeviceToken') || body.includes('DeviceTokenNotForTopic')) return 'gone';
      }
      if (!response.ok) {
        this.options.log?.debug(
          { deviceId: target.deviceId, status: response.status },
          'apns refused the wake-up',
        );
      }
      return 'sent';
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * Firebase Cloud Messaging, HTTP v1.
 *
 * Data-only, always. An FCM message with a `notification` block is composed by
 * Google and drawn by the system without the app being consulted — which would
 * mean the text of a notification passing through Google's servers. There is
 * no such block here and there never can be: the payload is one field whose
 * value says nothing, and the app builds what the user sees after it has
 * fetched and decrypted.
 *
 * Only the Play edition ever registers with this. The Libre and direct builds
 * contain no Firebase library at all, which is enforced by the Gradle flavour
 * rather than by anybody remembering.
 */
export class FcmSender implements PushSender {
  constructor(
    private readonly options: {
      /** An OAuth2 access token for the service account, refreshed by the caller. */
      authorization: () => Promise<string>;
      projectId: string;
      host?: string;
      fetch?: FetchLike;
      log?: FastifyBaseLogger;
      timeoutMs?: number;
    },
  ) {}

  async notify(target: PushTarget): Promise<PushOutcome> {
    const host = this.options.host ?? 'https://fcm.googleapis.com';
    const send = this.options.fetch ?? (globalThis.fetch as unknown as FetchLike);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 5000);

    try {
      const response = await send(
        `${host}/v1/projects/${this.options.projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${await this.options.authorization()}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: target.token,
              // One key, one value, and the value is a category rather than a
              // fact about anybody. "A call is waiting" is what the device
              // needs in order to know it must not wait for a batching window.
              data: { privio: target.urgency === 'call' ? 'call' : 'wake' },
              android: {
                // `high` is what reaches a dozing phone. It is spent only on
                // calls; a message can wait for the next maintenance window,
                // and spending it on everything is how an app gets throttled.
                priority: target.urgency === 'call' ? 'HIGH' : 'NORMAL',
                ttl: target.urgency === 'call' ? '60s' : '3600s',
              },
            },
          }),
          signal: controller.signal,
        },
      );

      // 404 is UNREGISTERED: the app was uninstalled or the token replaced.
      // 403 usually means the credentials are wrong, which is the operator's
      // problem and not this device's — the token is kept.
      if (response.status === 404) return 'gone';
      if (response.status === 400) {
        const body = (await response.text?.()) ?? '';
        if (body.includes('INVALID_ARGUMENT') && body.includes('token')) return 'gone';
      }
      if (!response.ok) {
        this.options.log?.debug(
          { deviceId: target.deviceId, status: response.status },
          'fcm refused the wake-up',
        );
      }
      return 'sent';
    } finally {
      clearTimeout(timer);
    }
  }
}
