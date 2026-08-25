import type { FastifyBaseLogger } from 'fastify';

export interface PushTarget {
  deviceId: string;
  provider: 'apns' | 'fcm';
  token: string;
}

/**
 * Push payloads carry no content — only a wake-up. The device connects and
 * pulls its envelopes over TLS, so neither Apple nor Google ever sees who is
 * messaging whom, let alone what was said.
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

// Production adapters (APNs token-based JWT auth, FCM HTTP v1) implement this
// same interface; see docs/architecture.md#notifications.
