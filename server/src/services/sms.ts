import { config } from '../config.js';

/**
 * Sending a verification text.
 *
 * The interface exists so the rest of the code does not know or care which
 * service is behind it, and so a test can assert what *would* have been sent
 * without sending anything. What it must never do is make an unconfigured
 * deployment look like a working one, which is why there is no "log it and
 * call it sent" default.
 */
export interface SmsSender {
  /** A short, machine-readable name for what is behind this. */
  readonly kind: 'none' | 'twilio' | 'development-echo';

  /**
   * Sends a code, or throws [SmsUnavailable].
   *
   * Takes the code rather than a finished sentence so the wording stays in one
   * place, and returns nothing: whether the person's phone rang is not
   * something this server can know.
   */
  send(e164: string, code: string): Promise<void>;
}

/** Nothing is configured to send texts. */
export class SmsUnavailable extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SmsUnavailable';
  }
}

/**
 * The default: no provider.
 *
 * It refuses rather than pretending. A verification flow that silently accepts
 * any code, or that "sends" to a log file, is the exact thing the brief for
 * this feature forbids shipping as finished — so the absence of configuration
 * is an error with a name, all the way up to the client, which shows a sentence
 * saying the server cannot send texts yet.
 */
export class NoSmsSender implements SmsSender {
  readonly kind = 'none' as const;

  send(): Promise<void> {
    return Promise.reject(
      new SmsUnavailable(
        'No SMS provider is configured. Set SMS_PROVIDER and its credentials — ' +
          'see docs/phone-contacts.md.',
      ),
    );
  }
}

/**
 * Twilio, over its REST API.
 *
 * `fetch` rather than the SDK: one authenticated form post is not worth a
 * dependency, and a dependency that holds credentials is a dependency worth not
 * having.
 *
 * Note what is *not* here: no logging of the number, the code, or the response
 * body. A failure is reported as a failure; what was in it stays out of the log,
 * because a log line with a one-time code in it is a one-time code somebody else
 * can read.
 */
export class TwilioSmsSender implements SmsSender {
  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly from: string,
  ) {}

  readonly kind = 'twilio' as const;

  async send(e164: string, code: string): Promise<void> {
    const body = new URLSearchParams({
      To: e164,
      From: this.from,
      Body: `${code} is your Privio verification code.`,
    });

    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(this.accountSid)}/Messages.json`,
      {
        method: 'POST',
        headers: {
          authorization: `Basic ${Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64')}`,
          'content-type': 'application/x-www-form-urlencoded',
        },
        body,
      },
    );

    if (!response.ok) {
      // The status, and deliberately not the body: Twilio echoes the recipient
      // number in its errors.
      throw new SmsUnavailable(`The SMS provider refused the message (HTTP ${response.status}).`);
    }
  }
}

/**
 * Hands the code back in the API response instead of sending it.
 *
 * For working on the flow without a paid account. Every response it produces is
 * marked `developmentStub: true` so nothing downstream can mistake it for a
 * delivered message, and [smsSenderFrom] refuses to build one when NODE_ENV is
 * production.
 */
export class DevelopmentEchoSender implements SmsSender {
  readonly kind = 'development-echo' as const;

  send(): Promise<void> {
    return Promise.resolve();
  }
}

/**
 * The sender this deployment is configured for.
 *
 * Throws at start-up rather than at the first verification when the
 * configuration is half-done — a missing token is a deployment mistake, and
 * finding out about it when a user is waiting for a text is finding out too
 * late.
 */
export function smsSenderFrom(): SmsSender {
  if (config.SMS_DEV_ECHO) {
    if (config.NODE_ENV === 'production') {
      throw new Error(
        'SMS_DEV_ECHO returns verification codes in the API response and must ' +
          'never be set in production.',
      );
    }
    return new DevelopmentEchoSender();
  }

  if (config.SMS_PROVIDER === 'twilio') {
    const missing = [
      config.TWILIO_ACCOUNT_SID === '' ? 'TWILIO_ACCOUNT_SID' : null,
      config.TWILIO_AUTH_TOKEN === '' ? 'TWILIO_AUTH_TOKEN' : null,
      config.TWILIO_FROM === '' ? 'TWILIO_FROM' : null,
    ].filter((name): name is string => name !== null);
    if (missing.length > 0) {
      throw new Error(`SMS_PROVIDER=twilio needs ${missing.join(', ')}.`);
    }
    return new TwilioSmsSender(
      config.TWILIO_ACCOUNT_SID,
      config.TWILIO_AUTH_TOKEN,
      config.TWILIO_FROM,
    );
  }

  return new NoSmsSender();
}
