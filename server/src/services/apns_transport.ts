import http2 from 'node:http2';
import type { FastifyBaseLogger } from 'fastify';

/**
 * What APNs needs and `fetch` cannot give it.
 *
 * Apple's push endpoint speaks HTTP/2 only. Node's global fetch is undici, and
 * undici offers only `http/1.1` in the TLS ALPN handshake — so a request to
 * `api.push.apple.com` does not fail at the HTTP layer with something
 * diagnosable, it fails during the TLS handshake with
 * `tlsv1 alert no application protocol`. Verified against a local HTTP/2-only
 * server: fetch fails that way, `node:http2` gets a 200.
 *
 * That is why this exists rather than another `fetch` wrapper, and why a test
 * that injects a fake fetch proves nothing about it. The test for this one
 * stands up a real HTTP/2 server and talks to it.
 *
 * The session is kept open between pushes, which is what Apple asks for: a new
 * TLS connection per notification is both slow and something they will throttle.
 */
export interface ApnsResponse {
  status: number;
  body: string;
}

export interface ApnsTransport {
  post(path: string, headers: Record<string, string>, body: string): Promise<ApnsResponse>;
  close(): Promise<void>;
}

export class Http2ApnsTransport implements ApnsTransport {
  private session: http2.ClientHttp2Session | null = null;

  constructor(
    private readonly origin: string,
    private readonly options: { log?: FastifyBaseLogger; timeoutMs?: number } = {},
  ) {}

  private connect(): http2.ClientHttp2Session {
    const existing = this.session;
    if (existing && !existing.closed && !existing.destroyed) return existing;

    const session = http2.connect(this.origin);
    // A dead session must not be reused. Clearing the field rather than
    // reconnecting here means the next push reconnects lazily, which is the
    // right moment: reconnecting eagerly on every network blip would hammer
    // Apple during an outage.
    const forget = (): void => {
      if (this.session === session) this.session = null;
    };
    session.on('close', forget);
    session.on('error', (err) => {
      this.options.log?.debug({ err }, 'apns session error');
      forget();
    });
    session.on('goaway', forget);
    // Never keep the process alive for the sake of an idle push connection.
    session.unref();

    this.session = session;
    return session;
  }

  async post(
    path: string,
    headers: Record<string, string>,
    body: string,
  ): Promise<ApnsResponse> {
    const session = this.connect();
    const timeoutMs = this.options.timeoutMs ?? 10_000;

    return new Promise<ApnsResponse>((resolve, reject) => {
      let settled = false;
      const finish = (fn: () => void): void => {
        if (settled) return;
        settled = true;
        fn();
      };

      const request = session.request({
        ':method': 'POST',
        ':path': path,
        ...headers,
      });

      // The stream is what gets a deadline, not the session: one slow
      // notification must not take the connection down for the rest.
      request.setTimeout(timeoutMs, () => {
        request.close(http2.constants.NGHTTP2_CANCEL);
        finish(() => reject(new Error('apns request timed out')));
      });

      let status = 0;
      let payload = '';
      request.on('response', (received) => {
        status = Number(received[':status'] ?? 0);
      });
      request.setEncoding('utf8');
      request.on('data', (chunk: string) => {
        // Apple's error bodies are small JSON objects. A cap in case something
        // else is on the other end.
        if (payload.length < 4096) payload += chunk;
      });
      request.on('end', () => finish(() => resolve({ status, body: payload })));
      request.on('error', (err) => finish(() => reject(err)));

      request.end(body);
    });
  }

  async close(): Promise<void> {
    const session = this.session;
    this.session = null;
    if (session && !session.closed) {
      await new Promise<void>((resolve) => session.close(() => resolve()));
    }
  }
}
