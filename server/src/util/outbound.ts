import { isIP } from 'node:net';
import { lookup } from 'node:dns/promises';
import { ApiError } from './errors.js';

/**
 * Guards the one place this server makes an outbound request to an address a
 * user chose: a UnifiedPush distributor endpoint.
 *
 * That is a server-side request forgery waiting to happen. A device could
 * register `http://169.254.169.254/…` or `https://10.0.0.5/admin` and have the
 * relay fetch it from inside the network, with the relay's own reachability.
 * So an endpoint has to be HTTPS, and has to resolve to a public address —
 * checked on the way in for fast feedback, and again before every send, because
 * a name that resolved publicly last week may not today.
 */

/** Blocked IPv4 ranges, as [first octet mask, predicate] pairs. */
function isPrivateIPv4(address: string): boolean {
  const parts = address.split('.').map(Number);
  if (parts.length !== 4 || parts.some((p) => Number.isNaN(p))) return true;
  const [a, b] = parts as [number, number, number, number];

  if (a === 0) return true; // "this network"
  if (a === 10) return true; // RFC1918
  if (a === 127) return true; // loopback
  if (a === 169 && b === 254) return true; // link-local, incl. cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true; // RFC1918
  if (a === 192 && b === 168) return true; // RFC1918
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a === 198 && (b === 18 || b === 19)) return true; // benchmarking
  if (a >= 224) return true; // multicast, reserved, broadcast
  return false;
}

/**
 * Expands an IPv6 address to its eight 16-bit groups, or null if it is not one.
 *
 * Written out rather than pattern-matched on the text because the text is not
 * stable: `https://[::ffff:127.0.0.1]` comes back out of the URL parser as
 * `::ffff:7f00:1`, and a check that only knew the dotted form would wave the
 * loopback through. Anything a resolver or a URL can produce has to reduce to
 * the same sixteen bytes before it is judged.
 */
function expandIPv6(address: string): number[] | null {
  const value = address.toLowerCase().split('%')[0]!;
  const halves = value.split('::');
  if (halves.length > 2) return null;

  const toGroups = (part: string): number[] | null => {
    if (part === '') return [];
    const groups: number[] = [];
    for (const piece of part.split(':')) {
      if (piece.includes('.')) {
        // A trailing dotted quad is two groups.
        const octets = piece.split('.').map(Number);
        if (octets.length !== 4 || octets.some((o) => Number.isNaN(o) || o < 0 || o > 255)) {
          return null;
        }
        groups.push((octets[0]! << 8) | octets[1]!, (octets[2]! << 8) | octets[3]!);
        continue;
      }
      if (!/^[0-9a-f]{1,4}$/.test(piece)) return null;
      groups.push(parseInt(piece, 16));
    }
    return groups;
  };

  const head = toGroups(halves[0]!);
  const tail = halves.length === 2 ? toGroups(halves[1]!) : [];
  if (head === null || tail === null) return null;

  if (halves.length === 1) return head.length === 8 ? head : null;
  const gap = 8 - head.length - tail.length;
  if (gap < 1) return null;
  return [...head, ...Array<number>(gap).fill(0), ...tail];
}

function isPrivateIPv6(address: string): boolean {
  const groups = expandIPv6(address);
  if (groups === null) return true;

  const [g0, g1, g2, g3, g4, g5, g6, g7] = groups as [
    number, number, number, number, number, number, number, number,
  ];

  // Loopback and unspecified.
  if (g0 === 0 && g1 === 0 && g2 === 0 && g3 === 0 && g4 === 0 && g5 === 0 && g6 === 0) {
    return g7 === 1 || g7 === 0;
  }

  // An IPv4 address wearing a hat: v4-mapped (::ffff:a.b.c.d), the deprecated
  // v4-compatible form, and NAT64's 64:ff9b::/96. Each is judged as the IPv4
  // address it carries, or ::ffff:127.0.0.1 walks past every check above.
  const embedded = (): boolean => isPrivateIPv4(`${g6 >> 8}.${g6 & 255}.${g7 >> 8}.${g7 & 255}`);
  if (g0 === 0 && g1 === 0 && g2 === 0 && g3 === 0 && g4 === 0 && (g5 === 0xffff || g5 === 0)) {
    return embedded();
  }
  if (g0 === 0x64 && g1 === 0xff9b && g2 === 0 && g3 === 0 && g4 === 0 && g5 === 0) {
    return embedded();
  }

  if ((g0 & 0xfe00) === 0xfc00) return true; // unique-local
  if ((g0 & 0xffc0) === 0xfe80) return true; // link-local
  if ((g0 & 0xff00) === 0xff00) return true; // multicast
  return false;
}

export function isPrivateAddress(address: string): boolean {
  const version = isIP(address);
  if (version === 4) return isPrivateIPv4(address);
  if (version === 6) return isPrivateIPv6(address);
  return true; // not an address at all: treat as unusable
}

export interface EndpointPolicy {
  /** Empty means any public host. A non-empty list is an exact-host allowlist. */
  allowedHosts?: string[];
}

/**
 * Shape checks only — no DNS, so this is safe to run inside a request.
 *
 * Throws [ApiError] rather than a plain Error because the one caller is a
 * route, and "your endpoint is not usable" is a 400, not a 500.
 */
export function parsePushEndpoint(raw: string, policy: EndpointPolicy = {}): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw ApiError.badRequest('invalid_push_config', 'The endpoint is not a URL');
  }

  if (url.protocol !== 'https:') {
    throw ApiError.badRequest('invalid_push_config', 'The endpoint must be https');
  }
  if (url.username || url.password) {
    throw ApiError.badRequest('invalid_push_config', 'The endpoint must not carry credentials');
  }

  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (isIP(host) && isPrivateAddress(host)) {
    throw ApiError.badRequest('invalid_push_config', 'The endpoint must be publicly routable');
  }

  const allowed = policy.allowedHosts ?? [];
  if (allowed.length > 0 && !allowed.includes(url.hostname.toLowerCase())) {
    throw ApiError.badRequest('invalid_push_config', 'That distributor is not allowed here');
  }

  return url;
}

/**
 * Resolves the host and refuses if anything it answers with is private.
 *
 * Every address is checked, not just the first: a name that resolves to one
 * public and one loopback address is a name that gets to pick at connect time.
 *
 * What this does not close is the window between resolving and connecting — a
 * name can change its answer in between. Closing it properly means connecting
 * to a pinned address with the hostname carried separately for TLS, which is
 * more machinery than a wake-up ping justifies. It is written down rather than
 * left to be discovered.
 */
export async function assertResolvesPublicly(url: URL): Promise<void> {
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (isIP(host)) {
    if (isPrivateAddress(host)) throw new Error(`endpoint resolves privately: ${host}`);
    return;
  }

  const addresses = await lookup(host, { all: true });
  if (addresses.length === 0) throw new Error(`endpoint does not resolve: ${host}`);
  for (const { address } of addresses) {
    if (isPrivateAddress(address)) {
      throw new Error(`endpoint resolves privately: ${host} -> ${address}`);
    }
  }
}
