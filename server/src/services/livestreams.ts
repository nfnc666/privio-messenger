import { createHmac, randomBytes } from 'node:crypto';
import { config } from '../config.js';

/**
 * Channel livestreams, against an SFU.
 *
 * **Why this cannot be done with the call code already here.** A 1:1 call is
 * two devices and a TURN relay: each sends its own media to the other. A
 * channel broadcast is one publisher and every subscriber who opens it, and a
 * publisher cannot upload the same stream three hundred times. That needs a
 * server that takes one stream in and fans it out — an SFU — and no amount of
 * client code substitutes for one.
 *
 * So this module is the whole server side of livestreams, and it is honest
 * about the hole: with no SFU configured, [available] is false, every route
 * refuses with `livestream_unconfigured`, and the app draws the control as
 * unavailable with the reason rather than as a button that does nothing.
 *
 * **What is deliberately not here.** The media never passes through Privio's
 * own server, and the SFU is not part of the end-to-end encrypted path: a
 * livestream is not E2EE, and the operator of the SFU can see it. That is a
 * genuine step down from everything else in this codebase, which is why
 * starting one is an explicit act by an admin rather than a setting, and why
 * `docs/channels.md` says so in as many words.
 */
export interface LivestreamAccess {
  /** Where the client connects. */
  url: string;
  /** The room on that server. */
  room: string;
  /** A short-lived join token, scoped to one room and one identity. */
  token: string;
  /** Whether this token may send media, or only receive it. */
  canPublish: boolean;
  expiresAt: string;
}

/** Whether the deployment has an SFU at all. */
export function available(): boolean {
  return Boolean(config.LIVEKIT_URL && config.LIVEKIT_API_KEY && config.LIVEKIT_API_SECRET);
}

/** A fresh room name. Random rather than derived from the channel id, so a room
 * name is not a channel identifier leaked to the media server. */
export function newRoom(): string {
  return `live-${randomBytes(16).toString('hex')}`;
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64url');
}

/**
 * A LiveKit access token: a plain JWT, HS256, signed with the API secret.
 *
 * Written out rather than pulled from a vendor SDK because it is twenty lines
 * and the alternative is a dependency in the signing path.
 */
export function accessToken(options: {
  room: string;
  identity: string;
  canPublish: boolean;
  ttlSeconds?: number;
}): LivestreamAccess {
  const url = config.LIVEKIT_URL;
  const key = config.LIVEKIT_API_KEY;
  const secret = config.LIVEKIT_API_SECRET;
  if (!url || !key || !secret) {
    throw new Error('accessToken called with no SFU configured; check available() first');
  }

  const now = Math.floor(Date.now() / 1000);
  const ttl = options.ttlSeconds ?? 3600;
  const payload = {
    iss: key,
    sub: options.identity,
    // The identity the SFU shows other participants. An account id rather than
    // a username: the media server has no business learning who people are.
    nbf: now - 30,
    exp: now + ttl,
    video: {
      room: options.room,
      roomJoin: true,
      canPublish: options.canPublish,
      canSubscribe: true,
      // Nobody uploads files through the media server.
      canPublishData: false,
    },
  };

  const header = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64url(JSON.stringify(payload));
  const signature = base64url(
    createHmac('sha256', secret).update(`${header}.${body}`).digest(),
  );

  return {
    url,
    room: options.room,
    token: `${header}.${body}.${signature}`,
    canPublish: options.canPublish,
    expiresAt: new Date((now + ttl) * 1000).toISOString(),
  };
}
