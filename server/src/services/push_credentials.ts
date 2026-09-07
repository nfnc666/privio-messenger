import { createSign, createPrivateKey } from 'node:crypto';

/**
 * The two credentials the vendor push services want, and when they expire.
 *
 * Both are short-lived bearer tokens minted from a private key we hold. Neither
 * is ever logged and neither is ever returned to a client: the only thing that
 * leaves this file is an `Authorization` header value handed straight to the
 * sender that is about to make the request.
 */

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64url');
}

/**
 * APNs provider tokens, signed ES256 with the `.p8` key from the developer
 * portal.
 *
 * Apple refuses a token older than one hour and refuses one minted more often
 * than every twenty minutes, so it is cached and reissued at forty — comfortably
 * inside both limits and not a moving target that needs tuning.
 */
export class ApnsTokenSource {
  private cached: { token: string; mintedAt: number } | null = null;

  constructor(
    private readonly options: {
      /** The `.p8` contents, PEM, from the Apple developer portal. */
      privateKeyPem: string;
      keyId: string;
      teamId: string;
      /** Injected in tests; real code has no reason to pass it. */
      now?: () => number;
    },
  ) {}

  private static readonly REFRESH_AFTER_MS = 40 * 60 * 1000;

  token(): string {
    const now = this.options.now?.() ?? Date.now();
    const cached = this.cached;
    if (cached && now - cached.mintedAt < ApnsTokenSource.REFRESH_AFTER_MS) {
      return cached.token;
    }

    const header = base64url(JSON.stringify({ alg: 'ES256', kid: this.options.keyId }));
    const claims = base64url(
      JSON.stringify({ iss: this.options.teamId, iat: Math.floor(now / 1000) }),
    );
    const signer = createSign('SHA256');
    signer.update(`${header}.${claims}`);
    // `dsaEncoding: 'ieee-p1363'` is the difference between a token Apple
    // accepts and one it rejects with 403 InvalidProviderToken: JWS wants the
    // raw r||s pair, and Node's default is DER.
    const signature = signer.sign({
      key: createPrivateKey(this.options.privateKeyPem),
      dsaEncoding: 'ieee-p1363',
    });

    const token = `${header}.${claims}.${base64url(signature)}`;
    this.cached = { token, mintedAt: now };
    return token;
  }
}

/** The `fetch` shape the FCM token exchange needs, so a test can stand in. */
export type TokenFetch = (
  input: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>;

/**
 * FCM access tokens, exchanged from a service-account JWT.
 *
 * Google's OAuth2 endpoint is ordinary HTTPS over HTTP/1.1, so `fetch` is fine
 * here — unlike APNs, which is why only one of these two has a bespoke
 * transport.
 *
 * The token is cached until a minute before it expires. A minute rather than
 * nothing because a token that expires while in flight comes back as a 401 that
 * looks like a configuration error.
 */
export class FcmTokenSource {
  private cached: { token: string; expiresAt: number } | null = null;
  private inFlight: Promise<string> | null = null;

  constructor(
    private readonly options: {
      clientEmail: string;
      privateKeyPem: string;
      tokenUri?: string;
      fetch?: TokenFetch;
      now?: () => number;
    },
  ) {}

  async token(): Promise<string> {
    const now = this.options.now?.() ?? Date.now();
    const cached = this.cached;
    if (cached && cached.expiresAt - 60_000 > now) return cached.token;

    // One exchange at a time. Without this a burst of pushes after an expiry
    // starts a dozen identical requests to Google, which is both wasteful and a
    // good way to get rate limited.
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.exchange(now).finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }

  private async exchange(now: number): Promise<string> {
    const uri = this.options.tokenUri ?? 'https://oauth2.googleapis.com/token';
    const issuedAt = Math.floor(now / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(
      JSON.stringify({
        iss: this.options.clientEmail,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: uri,
        iat: issuedAt,
        exp: issuedAt + 3600,
      }),
    );
    const signer = createSign('RSA-SHA256');
    signer.update(`${header}.${claims}`);
    const assertion = `${header}.${claims}.${base64url(
      signer.sign(createPrivateKey(this.options.privateKeyPem)),
    )}`;

    const send = this.options.fetch ?? (globalThis.fetch as unknown as TokenFetch);
    const response = await send(uri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
    });

    if (!response.ok) {
      // Deliberately without the body: an OAuth error can echo the assertion,
      // and the assertion is signed with our private key.
      throw new Error(`FCM token exchange failed with ${response.status}`);
    }
    const payload = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!payload.access_token) throw new Error('FCM token exchange returned no access token');

    this.cached = {
      token: payload.access_token,
      expiresAt: now + (payload.expires_in ?? 3600) * 1000,
    };
    return this.cached.token;
  }
}
