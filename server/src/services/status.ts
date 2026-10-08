import { hostname, loadavg } from 'node:os';
import { config, configWarnings } from '../config.js';
import { pool, pingDatabase } from '../db/pool.js';
import type { DeliveryBus } from './bus.js';
import type { PushProvider } from './push.js';
import type { BlobStorage } from './storage.js';
import * as livestreams from './livestreams.js';
import { canStoreSecrets } from './totp.js';

/**
 * What this deployment is made of, and which parts of it are working.
 *
 * The question an operator actually has at 3am is not "is the server up" — the
 * panel they are reading it on would not have loaded. It is "which piece is
 * broken, and is it a piece I configured". So every subsystem reports one of
 * four states rather than a boolean:
 *
 *   ok        — configured and answering
 *   degraded  — working, but in a way that will cost something
 *   off       — deliberately not configured, which is a real answer
 *   down      — it should be working and it is not
 *
 * The distinction between `off` and `down` is the one that matters and the one
 * a green/red light cannot make. A self-hosted Privio with no Apple developer
 * account has APNs `off`, and that is correct and permanent; a hosted one with
 * APNs `off` has a bug in its environment. Only the deployment knows which,
 * so the panel says what is true and lets the operator judge.
 *
 * NOTHING HERE RETURNS A SECRET. Not a key, not a token, not a password, not a
 * connection string. Where a URL is reported it is reduced to its host, which
 * is what an operator needs to recognise a misconfiguration and is the part
 * that is not a credential. `redactHost` is the only place that decision is
 * made, so there is one line to check.
 */

export type Health = 'ok' | 'degraded' | 'off' | 'down';

export interface Subsystem {
  /** Stable, for the panel to key off. */
  id: string;
  label: string;
  state: Health;
  /** One sentence an operator can act on. Never a stack trace. */
  detail: string;
  /** Round-trip time where the check actually measured one. */
  latencyMs?: number;
}

export interface StatusReport {
  /** The worst state among the subsystems, so a tile can say it in one word. */
  overall: Health;
  checkedAt: string;
  server: {
    version: string;
    environment: string;
    node: string;
    host: string;
    uptimeSeconds: number;
    /** Resident set size in bytes. The number a container's memory limit kills on. */
    memoryBytes: number;
    loadAverage: number[];
  };
  subsystems: Subsystem[];
  /** Configuration that boots but will lose data or capability. */
  warnings: string[];
}

/**
 * The host of a URL, or a marker when it cannot be parsed.
 *
 * The one place a configured URL is allowed to reach an operator's screen, and
 * it is a host rather than the URL because a URL can carry credentials in its
 * userinfo and a query string, and because the host is the whole of what
 * "pointed at the wrong place" looks like.
 */
function redactHost(url: string | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).host;
  } catch {
    return 'unparseable';
  }
}

const SEVERITY: Record<Health, number> = { ok: 0, off: 1, degraded: 2, down: 3 };

function worst(subsystems: Subsystem[]): Health {
  return subsystems.reduce<Health>(
    (acc, s) => (SEVERITY[s.state] > SEVERITY[acc] ? s.state : acc),
    'ok',
  );
}

export interface RuntimeFacts {
  /** Reported by `GET /health` and `GET /v1/server`. */
  version: string;
  /** Which push providers can actually deliver, from `createPushSender`. */
  pushConfigured: PushProvider[];
  bus: DeliveryBus;
  storage: BlobStorage;
  /** Injectable so a test can make the database fail without taking it away. */
  pingDatabase?: () => Promise<void>;
}

/** Times a check and turns a throw into a `down` rather than a 500. */
async function timed(
  id: string,
  label: string,
  check: () => Promise<Omit<Subsystem, 'id' | 'label' | 'latencyMs'>>,
): Promise<Subsystem> {
  const started = Date.now();
  try {
    const result = await check();
    return { id, label, ...result, latencyMs: Date.now() - started };
  } catch (err) {
    return {
      id,
      label,
      state: 'down',
      // The message, not the stack: this goes on a screen, and the stack is
      // already in the process log where the person debugging it is looking.
      detail: err instanceof Error ? err.message : 'The check failed.',
      latencyMs: Date.now() - started,
    };
  }
}

export async function collectStatus(facts: RuntimeFacts): Promise<StatusReport> {
  const ping = facts.pingDatabase ?? (() => pingDatabase());

  const [database, redis, storage] = await Promise.all([
    timed('database', 'PostgreSQL', async () => {
      await ping();
      // The pool's own counters, which is how a connection leak announces
      // itself: `waiting` climbing while `idle` sits at zero.
      const { totalCount, idleCount, waitingCount } = pool;
      return {
        state: (waitingCount > 0 ? 'degraded' : 'ok') as Health,
        detail:
          waitingCount > 0
            ? `${waitingCount} request${waitingCount === 1 ? '' : 's'} waiting for a connection; ${totalCount} open, ${idleCount} idle`
            : `${totalCount} connection${totalCount === 1 ? '' : 's'} open, ${idleCount} idle`,
      };
    }),

    timed('redis', 'Redis', async () => {
      if (!config.REDIS_URL) {
        return {
          state: 'degraded' as Health,
          detail:
            'Not configured, so this process runs as a single node with an in-process bus. Correct for one instance, wrong the moment a second is started.',
        };
      }
      const health = await facts.bus.health?.();
      if (!health) {
        return { state: 'ok' as Health, detail: 'Configured. This bus reports no health of its own.' };
      }
      return {
        state: (health.ok ? 'ok' : 'down') as Health,
        detail: health.detail,
      };
    }),

    timed('storage', 'Media storage', async () => {
      const health = await facts.storage.health?.();
      if (!health) return { state: 'ok' as Health, detail: 'In use.' };
      return { state: (health.ok ? 'ok' : 'down') as Health, detail: health.detail };
    }),
  ]);

  const subsystems: Subsystem[] = [database, redis, storage];

  // --- Push -----------------------------------------------------------------
  // UnifiedPush needs no credentials — the endpoint is the credential — so it
  // works on a server with no Apple or Google account at all, and is listed
  // first for that reason.
  const allowedHosts = config.UNIFIEDPUSH_ALLOWED_HOSTS.split(',').filter((h) => h.trim()).length;
  subsystems.push({
    id: 'unifiedpush',
    label: 'UnifiedPush',
    state: 'ok',
    detail:
      allowedHosts > 0
        ? `Available. Narrowed to ${allowedHosts} allowed distributor host${allowedHosts === 1 ? '' : 's'}.`
        : 'Available. Any publicly routable HTTPS distributor is accepted, which is the point of it.',
  });

  const apns = facts.pushConfigured.includes('apns');
  subsystems.push({
    id: 'apns',
    label: 'Apple Push (APNs)',
    state: apns ? 'ok' : 'off',
    detail: apns
      ? `Configured against the ${config.APNS_ENVIRONMENT} host.`
      : 'Not configured. iOS devices are woken only while the app is open, and the server reports those pushes as skipped rather than sent.',
  });

  const fcm = facts.pushConfigured.includes('fcm');
  subsystems.push({
    id: 'fcm',
    label: 'Firebase Cloud Messaging',
    state: fcm ? 'ok' : 'off',
    detail: fcm
      ? 'Configured from a service-account key.'
      : 'Not configured. Android devices on FCM are woken only while the app is open.',
  });

  // --- Calls ----------------------------------------------------------------
  const iceUrls = config.ICE_SERVERS.split(',').map((u) => u.trim()).filter(Boolean);
  const hasTurn = iceUrls.some((u) => u.startsWith('turn:') || u.startsWith('turns:'));
  subsystems.push({
    id: 'ice',
    label: 'Calls (STUN/TURN)',
    state: iceUrls.length === 0 ? 'off' : hasTurn && !config.TURN_SECRET ? 'degraded' : 'ok',
    detail:
      iceUrls.length === 0
        ? 'No ICE servers offered. Two devices try only the addresses they can see for themselves, which works on one network and fails behind a strict NAT.'
        : hasTurn && !config.TURN_SECRET
          ? `${iceUrls.length} server${iceUrls.length === 1 ? '' : 's'} offered, but TURN_SECRET is unset, so the relay is handed out without credentials. That only works on a TURN server that wants none.`
          : `${iceUrls.length} server${iceUrls.length === 1 ? '' : 's'} offered${hasTurn ? ', with time-limited TURN credentials' : ', STUN only'}.`,
  });

  // --- Livestreams ----------------------------------------------------------
  const sfu = livestreams.available();
  subsystems.push({
    id: 'livestreams',
    label: 'Livestreams (SFU)',
    state: sfu ? 'ok' : 'off',
    detail: sfu
      ? `LiveKit at ${redactHost(config.LIVEKIT_URL)}. A livestream is the one thing in Privio that cannot be peer-to-peer, and it is not end-to-end encrypted.`
      : 'No media server. The client draws the livestream control as unavailable and says why, rather than handing out a room nobody can join.',
  });

  // --- Translation ----------------------------------------------------------
  subsystems.push({
    id: 'translation',
    label: 'Post translation',
    state: config.TRANSLATION_URL ? 'ok' : 'off',
    detail: config.TRANSLATION_URL
      ? `Devices are pointed at ${redactHost(config.TRANSLATION_URL)}. Translation happens on the device, which is the only place the plaintext exists; the server never sends a post anywhere.`
      : 'Off. Channels cannot turn on translation.',
  });

  // --- Licensing ------------------------------------------------------------
  if (config.LICENSE_REQUIRED) {
    subsystems.push({
      id: 'licensing',
      label: 'Licensing',
      state: config.LICENSE_ISSUER_TOKEN ? 'ok' : 'degraded',
      detail: config.LICENSE_ISSUER_TOKEN
        ? 'This server sells access. Unlicensed accounts can sign in and read, and cannot send.'
        : 'This server sells access, but LICENSE_ISSUER_TOKEN is unset, so the website cannot issue a licence for a payment it has taken.',
    });
  } else {
    subsystems.push({
      id: 'licensing',
      label: 'Licensing',
      state: 'off',
      detail: 'This server does not sell access. Clients are never asked for a key.',
    });
  }

  // --- Two-factor -----------------------------------------------------------
  const totp = canStoreSecrets();
  subsystems.push({
    id: 'totp',
    label: 'Two-factor secrets',
    state: totp ? 'ok' : 'degraded',
    detail: totp
      ? 'TOTP_SECRET_KEY is set, so a secret is sealed before it reaches the database.'
      : 'TOTP_SECRET_KEY is unset. The server refuses to enrol anyone in two-factor rather than storing the next secret in the clear — including operators of this panel.',
  });

  // --- Links ----------------------------------------------------------------
  const iosReady = Boolean(config.IOS_APP_ID);
  const androidReady = Boolean(config.ANDROID_PACKAGE && config.ANDROID_CERT_FINGERPRINTS);
  subsystems.push({
    id: 'applinks',
    label: 'Universal and App Links',
    state: iosReady && androidReady ? 'ok' : iosReady || androidReady ? 'degraded' : 'off',
    detail:
      iosReady && androidReady
        ? 'Both verification files are served, so an invite link opens the app on either platform.'
        : iosReady
          ? 'Only the iOS file is served. An invite link opens the browser on Android.'
          : androidReady
            ? 'Only the Android file is served. An invite link opens the browser on iOS.'
            : 'Neither file is served. Invite links open the web page rather than the app, which is the correct state before a domain is verified.',
  });

  return {
    overall: worst(subsystems),
    checkedAt: new Date().toISOString(),
    server: {
      version: facts.version,
      environment: config.NODE_ENV,
      node: process.version,
      host: hostname(),
      uptimeSeconds: Math.floor(process.uptime()),
      memoryBytes: process.memoryUsage().rss,
      loadAverage: loadavg().map((n) => Number(n.toFixed(2))),
    },
    subsystems,
    warnings: configWarnings(config),
  };
}
