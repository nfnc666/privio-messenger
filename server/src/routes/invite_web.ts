import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import QRCode from 'qrcode';
import { pool } from '../db/pool.js';
import { config } from '../config.js';
import type { BlobStorage } from '../services/storage.js';
import {
  appDidNotOpenPage,
  privateInvitePage,
  problemPage,
  publicChannelPage,
  type DownloadLinks,
  type InvitePageOptions,
  type InviteProblem,
} from '../web/invite_page.js';

/**
 * The public web side of a channel link.
 *
 * Everything here answers without authentication, which is the point: a link
 * pasted into WhatsApp is opened by somebody who may never have heard of
 * Privio. None of it touches a post, a key or a member list — a public
 * channel's title, description and subscriber count are already plaintext
 * because discovery needs them, and a private invite's page says nothing about
 * the channel at all.
 *
 * **Three link shapes, and why.**
 *
 *   /houseoftrading   a public channel, named by its handle
 *   /+<code>          a private invitation, carrying its capability
 *   /c/<code>         what the app has always generated
 *
 * The first carries no capability at all: a public channel's handle is how it
 * is searched for, so a link to one is its name and nothing more. That matters
 * — the old form put an invite code into every public link, which meant a link
 * shared on a website was a capability sitting in a search index.
 *
 * The third stays because links built by every shipped build use it, and a
 * link that stops working is a worse link than an old-shaped one.
 *
 * **Nothing here counts a use.** A link preview is fetched by a bot, a page is
 * opened by people who then walk away, and both would spend an invitation that
 * says "let in one person". The counter moves inside the transaction that adds
 * the member, and nowhere else — see migration 021.
 */

const HANDLE = '^[a-z0-9_.]{3,32}$';

/** The logo, read once. 200 KB in memory beats a disk read per request. */
let markBytes: Buffer | null = null;

async function readMark(): Promise<Buffer> {
  if (markBytes) return markBytes;
  // `dist/` mirrors `src/`, so this resolves from either, and `assets/` sits
  // beside both after the Docker build copies it.
  const here = dirname(fileURLToPath(import.meta.url));
  markBytes = await readFile(join(here, '..', '..', 'assets', 'privio-mark.png'));
  return markBytes;
}

/** Reads the opening bytes of a blob without pulling the whole thing in. */
async function firstBytes(storage: BlobStorage, key: string, count: number): Promise<Buffer> {
  const stream = storage.open(key);
  const chunks: Buffer[] = [];
  let total = 0;
  try {
    for await (const chunk of stream) {
      const buf = chunk as Buffer;
      chunks.push(buf);
      total += buf.length;
      if (total >= count) break;
    }
  } finally {
    stream.destroy();
  }
  return Buffer.concat(chunks).subarray(0, count);
}

/**
 * What these bytes are, by their magic number, or null.
 *
 * An allow-list rather than a sniff: the question is not "what might this be"
 * but "is this one of the four things it is safe to hand a browser under a
 * content type of our choosing". SVG is deliberately absent — it is a document
 * that can carry script, and serving one from this origin would put that script
 * on the same origin as the invite pages.
 */
function imageTypeOf(head: Buffer): string | null {
  if (head.length >= 8 && head.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) {
    return 'image/png';
  }
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) {
    return 'image/jpeg';
  }
  if (head.length >= 12 && head.subarray(0, 4).toString('latin1') === 'RIFF'
      && head.subarray(8, 12).toString('latin1') === 'WEBP') {
    return 'image/webp';
  }
  if (head.length >= 6 && /^GIF8[79]a$/.test(head.subarray(0, 6).toString('latin1'))) {
    return 'image/gif';
  }
  return null;
}

/**
 * The URL of a channel's picture on this page, or null for the mark.
 *
 * Only a public channel ever has one. A private channel's picture is sealed
 * with the channel key, so there is nothing here that could be drawn — and the
 * page it would be drawn on is the one that deliberately says nothing about the
 * channel at all.
 *
 * Keyed by handle rather than by media id: the id is a database identifier and
 * putting it in a URL that gets crawled and cached serves no purpose the handle
 * does not already serve.
 */
function avatarUrlFor(request: FastifyRequest, channel: ChannelRow): string | null {
  if (channel.visibility !== 'public' || !channel.handle || !channel.avatar_media_id) return null;
  return `${originOf(request)}/assets/channel/${channel.handle}`;
}

function downloads(): DownloadLinks {
  return {
    appStore: config.APP_STORE_URL,
    playStore: config.PLAY_STORE_URL,
    apk: config.APK_DOWNLOAD_URL,
  };
}

/**
 * Where this deployment lives, as an absolute origin.
 *
 * `PUBLIC_WEB_URL` when it is set, and otherwise whatever host the request
 * arrived on — which is what makes the pages work on a server with no domain
 * of its own. The scheme is taken from the proxy's `x-forwarded-proto` where
 * there is one, because the app talks HTTPS to a platform that terminates TLS
 * in front of it and would otherwise build every absolute URL as `http://`.
 */
export function originOf(request: FastifyRequest): string {
  if (config.PUBLIC_WEB_URL) return config.PUBLIC_WEB_URL.replace(/\/+$/, '');
  const forwarded = request.headers['x-forwarded-proto'];
  const proto = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(',')[0]?.trim();
  const host = request.headers.host ?? 'localhost';
  return `${proto || request.protocol || 'https'}://${host}`;
}

/** An inline SVG QR code, or null if it could not be made. */
async function qrFor(url: string): Promise<string | null> {
  try {
    const svg = await QRCode.toString(url, {
      type: 'svg',
      margin: 1,
      errorCorrectionLevel: 'M',
      color: { dark: '#000000', light: '#ffffff' },
    });
    // Inline rather than a data URI in an <img>: one fewer thing for a strict
    // in-app browser to refuse, and nothing is fetched either way.
    return svg.replace('<svg', '<svg class="qr" width="150" height="150" aria-hidden="true"');
  } catch {
    // A URL too long to encode is not a reason to fail the page.
    return null;
  }
}

/**
 * Headers every page here carries.
 *
 * `Referrer-Policy: no-referrer` is the important one and it is not decoration:
 * a private invite's token is in the URL, and any request the page causes —
 * even one the browser makes for the favicon — would otherwise carry that URL
 * to wherever it went.
 *
 * The CSP says the same thing structurally: this page may load nothing from
 * anywhere, so there is no request for a token to ride on.
 */
function pageHeaders(reply: FastifyReply, indexable: boolean): void {
  reply.header('content-type', 'text/html; charset=utf-8');
  reply.header('referrer-policy', 'no-referrer');
  reply.header('x-content-type-options', 'nosniff');
  reply.header(
    'content-security-policy',
    "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; " +
      "form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
  );
  if (!indexable) reply.header('x-robots-tag', 'noindex, nofollow');
  // A public channel page may be cached briefly; a private one never.
  reply.header('cache-control', indexable ? 'public, max-age=60' : 'private, no-store');
}

interface ChannelRow {
  id: string;
  avatar_media_id: string | null;
  visibility: string;
  handle: string | null;
  title: string | null;
  description: string | null;
  member_count: number;
  deleted_at: Date | null;
  invite_expires_at: Date | null;
  invite_max_uses: number | null;
  invite_uses: number;
  invite_needs_approval: boolean;
}

export const inviteWebRoutes =
  (storage: BlobStorage): FastifyPluginAsync =>
  async (app) => {
  /** The mark, for the page and for every link preview. */
  app.get('/assets/privio-mark.png', async (_request, reply) => {
    reply.header('content-type', 'image/png');
    reply.header('cache-control', 'public, max-age=86400, immutable');
    return reply.send(await readMark());
  });

  /**
   * A public channel's picture, served to anybody.
   *
   * Three conditions, all of them load-bearing:
   *
   *   1. **Public only.** A private channel's picture is sealed and reached
   *      through `/v1/media` with the token from its sealed metadata. It must
   *      never come out of a route that asks for no credential.
   *   2. **Only the object the channel actually points at.** The id is taken
   *      from `channels.avatar_media_id`, never from the URL, so this route
   *      cannot be turned into an unauthenticated reader for any media id
   *      somebody guesses or reads out of a database dump.
   *   3. **Only if the bytes are really an image.** Uploads arrive as opaque
   *      `application/octet-stream` and the server does not know what it was
   *      handed. Serving those bytes back under a content type taken on trust
   *      is how a "picture" becomes an HTML page hosted on this origin, so the
   *      type comes from the first few bytes and anything unrecognised is a
   *      404 — the page then draws the mark, which is the same thing it does
   *      for a channel with no picture at all.
   */
  app.get<{ Params: { handle: string } }>(
    `/assets/channel/:handle(${HANDLE})`,
    async (request, reply) => {
      const { rows } = await pool.query<{ storage_key: string; byte_size: string | number }>(
        `SELECT m.storage_key, m.byte_size
           FROM channels c
           JOIN media_objects m ON m.id = c.avatar_media_id
          WHERE c.handle = $1
            AND c.visibility = 'public'
            AND c.deleted_at IS NULL
            AND m.kind = 'channel_avatar'`,
        [request.params.handle],
      );
      const object = rows[0];
      if (!object) {
        reply.code(404);
        return { error: 'no_picture' };
      }

      const head = await firstBytes(storage, object.storage_key, 16);
      const type = imageTypeOf(head);
      if (!type) {
        reply.code(404);
        return { error: 'no_picture' };
      }

      reply.header('content-type', type);
      reply.header('content-length', String(object.byte_size));
      reply.header('x-content-type-options', 'nosniff');
      // Short, because replacing a picture has to become visible. The page it
      // sits on is cached for 60 seconds for the same reason.
      reply.header('cache-control', 'public, max-age=300');
      return reply.send(storage.open(object.storage_key));
    },
  );

  function options(request: FastifyRequest, path: string): InvitePageOptions {
    const origin = originOf(request);
    return {
      origin,
      // A *different* path from the one that was shared, and that separation is
      // the whole trick: the shared link shows this page, and only `/open/...`
      // is claimed by the app-link files, so tapping the button is what hands
      // the link to the app.
      openUrl: `${origin}/open${path}`,
      shareUrl: `${origin}${path}`,
      downloads: downloads(),
    };
  }

  async function sendProblem(
    request: FastifyRequest,
    reply: FastifyReply,
    problem: InviteProblem,
    path: string,
  ): Promise<string> {
    pageHeaders(reply, false);
    reply.code(problem === 'not_found' || problem === 'deleted' ? 404 : 410);
    return problemPage(problem, options(request, path));
  }

  /** A public channel, by handle. Carries no capability — a handle is a name. */
  app.get<{ Params: { handle: string } }>(
    `/:handle(${HANDLE})`,
    async (request, reply) => {
      const path = `/${request.params.handle}`;
      const { rows } = await pool.query<ChannelRow>(
        `SELECT id, visibility, handle, title, description, member_count, deleted_at,
                avatar_media_id
         FROM channels WHERE handle = $1`,
        [request.params.handle],
      );
      const channel = rows[0];
      if (!channel) return sendProblem(request, reply, 'not_found', path);
      if (channel.deleted_at) return sendProblem(request, reply, 'deleted', path);
      // A handle only ever belongs to a public channel, but the check is here
      // rather than assumed: a private channel must not become nameable by a
      // column that happened to be filled in.
      if (channel.visibility !== 'public') {
        return sendProblem(request, reply, 'not_found', path);
      }

      pageHeaders(reply, true);
      return publicChannelPage(
        {
          title: channel.title ?? 'A channel on Privio',
          handle: channel.handle,
          description: channel.description,
          memberCount: channel.member_count,
          avatarUrl: avatarUrlFor(request, channel),
        },
        options(request, path),
        await qrFor(`${originOf(request)}${path}`),
      );
    },
  );

  /**
   * An invitation by code, in both shapes.
   *
   * A public channel reached this way gets the same page as its handle would
   * give; a private one gets the page that says nothing about it.
   */
  async function byCode(
    request: FastifyRequest,
    reply: FastifyReply,
    code: string,
    path: string,
  ): Promise<string> {
    const { rows } = await pool.query<ChannelRow>(
      `SELECT id, visibility, handle, title, description, member_count, deleted_at,
              avatar_media_id,
              invite_expires_at, invite_max_uses, invite_uses, invite_needs_approval
       FROM channels WHERE invite_code = $1`,
      [code],
    );
    const channel = rows[0];
    // A replaced code and a code that never existed are the same answer. For a
    // private channel that is the point: the existence is the secret.
    if (!channel) return sendProblem(request, reply, 'not_found', path);
    if (channel.deleted_at) return sendProblem(request, reply, 'deleted', path);

    const expired =
      channel.invite_expires_at !== null && channel.invite_expires_at.getTime() <= Date.now();
    const usedUp =
      channel.invite_max_uses !== null && channel.invite_uses >= channel.invite_max_uses;

    if (channel.visibility === 'public') {
      // A public channel's front door is not governed by its link, so a spent
      // link still shows the channel — there is another way in.
      pageHeaders(reply, true);
      return publicChannelPage(
        {
          title: channel.title ?? 'A channel on Privio',
          handle: channel.handle,
          description: channel.description,
          memberCount: channel.member_count,
          avatarUrl: avatarUrlFor(request, channel),
        },
        options(request, path),
        await qrFor(`${originOf(request)}${path}`),
      );
    }

    if (expired) return sendProblem(request, reply, 'expired', path);
    if (usedUp) return sendProblem(request, reply, 'used_up', path);

    pageHeaders(reply, false);
    return privateInvitePage(
      {
        usable: true,
        problem: null,
        needsApproval: channel.invite_needs_approval,
      },
      options(request, path),
      await qrFor(`${originOf(request)}${path}`),
    );
  }

  app.get<{ Params: { code: string } }>('/+:code', async (request, reply) =>
    byCode(request, reply, request.params.code, `/+${request.params.code}`),
  );

  // The shape every shipped build generates. Kept working rather than
  // migrated: a link already pasted somewhere cannot be rewritten.
  app.get<{ Params: { code: string } }>('/c/:code', async (request, reply) =>
    byCode(request, reply, request.params.code, `/c/${request.params.code}`),
  );

  /**
   * The path the app claims.
   *
   * Reaching this in a browser means no app took it — which is either "not
   * installed" or "the in-app browser would not hand it over", and a web page
   * cannot tell the two apart. So it says so and offers both ways on, rather
   * than guessing or bouncing somebody to a store they may not need.
   */
  app.get('/open/*', async (request, reply) => {
    const wildcard = (request.params as { '*': string })['*'];
    pageHeaders(reply, false);
    return appDidNotOpenPage(options(request, `/${wildcard}`));
  });

  /**
   * iOS Universal Links.
   *
   * Served from config, and **404 when unconfigured rather than served empty**.
   * Apple's CDN fetches this file and caches what it gets for days; a
   * placeholder with the wrong team id is a link that opens nothing for a week
   * after the right one is deployed. A 404 is the state both Apple and Android
   * handle correctly — they simply do not verify, and the link falls back to
   * the web page, which is a working outcome.
   *
   * No `.json` extension and `application/json` by hand: Apple fetches this
   * exact path and rejects anything served as something else.
   *
   * The paths list is the design decision, not a detail. Only `/open/*` is
   * claimed, so `/houseoftrading` and `/+token` open the *page* and the button
   * on it opens the app. Claiming the share paths instead would mean the app
   * swallowing every link before anybody ever saw a page, which is exactly the
   * behaviour this whole feature exists to avoid.
   */
  app.get('/.well-known/apple-app-site-association', async (_request, reply) => {
    if (!config.IOS_APP_ID) {
      reply.code(404);
      return { error: 'not_configured' };
    }
    reply.header('content-type', 'application/json');
    reply.header('cache-control', 'public, max-age=3600');
    return {
      applinks: {
        details: [
          {
            appIDs: [config.IOS_APP_ID],
            components: [{ '/': '/open/*', comment: 'channel links, opened deliberately' }],
          },
        ],
      },
    };
  });

  /**
   * Android App Links.
   *
   * Several fingerprints, not one: an app distributed through Play App Signing
   * has an upload certificate and the one Google re-signs with, and this
   * project also ships a directly-downloaded APK signed with a third. A file
   * naming only one of them verifies for some installs and silently fails for
   * the rest, which looks like a broken link on somebody else's phone.
   */
  app.get('/.well-known/assetlinks.json', async (_request, reply) => {
    const fingerprints = config.ANDROID_CERT_FINGERPRINTS.split(',')
      .map((value) => value.trim())
      .filter((value) => value.length > 0);
    if (!config.ANDROID_PACKAGE || fingerprints.length === 0) {
      reply.code(404);
      return { error: 'not_configured' };
    }
    reply.header('content-type', 'application/json');
    reply.header('cache-control', 'public, max-age=3600');
    return [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: config.ANDROID_PACKAGE,
          sha256_cert_fingerprints: fingerprints,
        },
      },
    ];
  });

  /** Where the header's button goes when there is somewhere to send people. */
  app.get('/download', async (request, reply) => {
    pageHeaders(reply, false);
    return appDidNotOpenPage(options(request, '/'));
  });
};

export default inviteWebRoutes;
