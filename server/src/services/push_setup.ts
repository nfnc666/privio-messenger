import type { FastifyBaseLogger } from 'fastify';
import { config } from '../config.js';
import { Http2ApnsTransport } from './apns_transport.js';
import { ApnsTokenSource, FcmTokenSource } from './push_credentials.js';
import {
  ApnsSender,
  FcmSender,
  LoggingPushSender,
  RoutingPushSender,
  UnifiedPushSender,
  type PushOutcome,
  type PushProvider,
  type PushSender,
  type PushTarget,
} from './push.js';

/**
 * A provider nobody configured.
 *
 * The thing this replaces was worse than nothing: unconfigured providers fell
 * through to `LoggingPushSender`, which records the intent and returns `sent`.
 * The relay therefore reported success for every APNs and FCM wake-up it had no
 * means to deliver — quietly, in production, for as long as nobody checked.
 *
 * `skipped` is a third answer alongside `sent` and `gone`, so the delivery path
 * can tell "we could not" from "we did". It does not fail the message: the
 * envelope was stored before any of this ran, and it is still there for the
 * device's next poll or socket.
 */
class UnconfiguredPushSender implements PushSender {
  private warned = false;

  constructor(
    private readonly provider: PushProvider | 'unknown',
    private readonly log?: FastifyBaseLogger,
  ) {}

  async notify(target: PushTarget): Promise<PushOutcome> {
    // Once, not once per message. A misconfiguration is a fact about the
    // deployment, and a line per push would bury everything else.
    if (!this.warned) {
      this.warned = true;
      this.log?.warn(
        { provider: this.provider },
        'push provider is not configured; devices on it are woken only when the app is open',
      );
    }
    this.log?.debug({ deviceId: target.deviceId, provider: this.provider }, 'push skipped');
    return 'skipped';
  }
}

export interface PushSetup {
  sender: PushSender;
  /** Which providers can actually deliver, for the start-up log and /health. */
  configured: PushProvider[];
  close(): Promise<void>;
}

/**
 * Builds the real push senders from configuration.
 *
 * UnifiedPush needs no credentials — the endpoint *is* the credential — so it
 * is always available, which is what lets a self-hosted server with no Apple or
 * Google account wake a phone at all. The other two are wired only when their
 * configuration is complete; `config.ts` refuses a half-filled set, so
 * "complete or absent" is the only shape that reaches here.
 */
export function createPushSender(log?: FastifyBaseLogger): PushSetup {
  const byProvider: Partial<Record<PushProvider, PushSender>> = {
    unifiedpush: new UnifiedPushSender({ log }),
  };
  const configured: PushProvider[] = ['unifiedpush'];
  const closers: (() => Promise<void>)[] = [];

  if (config.APNS_KEY_P8 && config.APNS_KEY_ID && config.APNS_TEAM_ID && config.APNS_TOPIC) {
    const host =
      config.APNS_ENVIRONMENT === 'sandbox'
        ? 'https://api.sandbox.push.apple.com'
        : 'https://api.push.apple.com';
    const transport = new Http2ApnsTransport(host, { log });
    const tokens = new ApnsTokenSource({
      // Secret stores rarely round-trip a literal newline, so the usual
      // escaped form is accepted and unescaped here.
      privateKeyPem: config.APNS_KEY_P8.replace(/\\n/g, '\n'),
      keyId: config.APNS_KEY_ID,
      teamId: config.APNS_TEAM_ID,
    });
    byProvider.apns = new ApnsSender({
      authorization: async () => tokens.token(),
      topic: config.APNS_TOPIC,
      transport,
      log,
    });
    configured.push('apns');
    closers.push(() => transport.close());
  } else {
    byProvider.apns = new UnconfiguredPushSender('apns', log);
  }

  if (config.FCM_PROJECT_ID && config.FCM_CLIENT_EMAIL && config.FCM_PRIVATE_KEY) {
    const tokens = new FcmTokenSource({
      clientEmail: config.FCM_CLIENT_EMAIL,
      privateKeyPem: config.FCM_PRIVATE_KEY.replace(/\\n/g, '\n'),
    });
    byProvider.fcm = new FcmSender({
      authorization: () => tokens.token(),
      projectId: config.FCM_PROJECT_ID,
      log,
    });
    configured.push('fcm');
  } else {
    byProvider.fcm = new UnconfiguredPushSender('fcm', log);
  }

  return {
    // The fallback is only reached by a provider value the enum does not cover,
    // which the database's own CHECK constraint makes impossible. It is not
    // where an unconfigured APNs or FCM lands any more — that was the bug.
    sender: new RoutingPushSender(byProvider, new UnconfiguredPushSender('unknown', log)),
    configured,
    close: async () => {
      await Promise.all(closers.map((close) => close().catch(() => {})));
    },
  };
}

/** Kept for tests and for a development server that wants no push at all. */
export { LoggingPushSender };
