import { createHmac } from 'node:crypto';
import { config } from '../config.js';

/** One entry of a WebRTC `iceServers` array. */
export interface IceServer {
  urls: string;
  username?: string;
  credential?: string;
}

/**
 * What a client should hand to its peer connection, and when to ask again.
 *
 * A STUN server only tells a device its own public address and relays nothing.
 * A TURN server relays the media — encrypted, since it is DTLS-SRTP between
 * the two devices and the relay holds no key — but it does see both addresses
 * and how much is flowing. That is the trade a relay is: it hides each party's
 * address from the other and shows both to whoever runs it.
 */
export interface IceConfiguration {
  iceServers: IceServer[];
  /** Unix seconds. Null when nothing here expires. */
  expiresAt: number | null;
}

function configuredUrls(): string[] {
  return config.ICE_SERVERS.split(',')
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
}

function isTurn(url: string): boolean {
  return url.startsWith('turn:') || url.startsWith('turns:');
}

/**
 * Mints the ICE servers for one client.
 *
 * TURN credentials are time-limited and follow coturn's `use-auth-secret`
 * scheme: the username is the expiry as a unix timestamp and the password is
 * the base64 HMAC-SHA1 of it under the shared secret. A fixed username and
 * password shipped inside a client is a public TURN server within a day.
 *
 * The username is the expiry and nothing else — deliberately no account id.
 * Putting one in would let the relay operator tie every relayed call to an
 * account, which is precisely the linkage the rest of this server is built to
 * avoid, and it buys only per-account rate limiting.
 */
export function iceConfiguration(now: Date = new Date()): IceConfiguration {
  const urls = configuredUrls();
  if (urls.length === 0) return { iceServers: [], expiresAt: null };

  const secret = config.TURN_SECRET;
  const needsCredentials = urls.some(isTurn) && secret !== undefined;
  if (!needsCredentials) {
    return { iceServers: urls.map((url) => ({ urls: url })), expiresAt: null };
  }

  const expiry = Math.floor(now.getTime() / 1000) + config.TURN_TTL_SECONDS;
  const username = String(expiry);
  const credential = createHmac('sha1', secret!).update(username).digest('base64');

  return {
    iceServers: urls.map((url) =>
      isTurn(url) ? { urls: url, username, credential } : { urls: url },
    ),
    expiresAt: expiry,
  };
}
