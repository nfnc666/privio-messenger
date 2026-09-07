// Creates an iOS distribution certificate and an App Store provisioning
// profile through the App Store Connect API, so that nobody needs a Mac — or
// any computer — to set up signing.
//
//   node tools/ios-signing-setup.mjs --csr <file> --bundle-id <id> --out <dir>
//
// It is meant to be run by `.github/workflows/ios-signing-setup.yml`, which
// makes the key and the CSR with `openssl` on the runner and turns what this
// writes into repository secrets. Run by hand it does the same thing and needs
// the same three environment variables:
//
//   APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_PRIVATE_KEY
//
// What it writes into --out:
//
//   certificate.cer          the distribution certificate, DER
//   profile.mobileprovision  the App Store profile for the bundle id
//   team-id.txt              the team id, read back from Apple rather than typed
//   summary.json            what it did, for the workflow's log
//
// Nothing here prints a key, a certificate body or a profile body. What is
// printed is what happened.

import { createSign } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const API = 'https://api.appstoreconnect.apple.com';

/** How long a request token is good for. Apple's ceiling is 20 minutes. */
const TOKEN_TTL_SECONDS = 15 * 60;

/**
 * A provider token for the App Store Connect API.
 *
 * ES256 over a `.p8`, the same shape as the APNs token in
 * `server/src/services/push_credentials.ts` — including the part that is easy
 * to get wrong: `ieee-p1363`. Node's default DER encoding produces a signature
 * Apple rejects with a bare 401, which reads like a wrong key.
 */
export function ascJwt({ keyId, issuerId, privateKey, now = Date.now() }) {
  const issued = Math.floor(now / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = {
    iss: issuerId,
    iat: issued,
    exp: issued + TOKEN_TTL_SECONDS,
    aud: 'appstoreconnect-v1',
  };
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  const signingInput = `${encode(header)}.${encode(payload)}`;
  const signature = createSign('SHA256')
    .update(signingInput)
    .sign({ key: privateKey, dsaEncoding: 'ieee-p1363' })
    .toString('base64url');
  return `${signingInput}.${signature}`;
}

/** Thin wrapper: one place that knows how Apple reports an error. */
export class AppStoreConnect {
  constructor({ token, fetchImpl = fetch, baseUrl = API }) {
    this.token = token;
    this.fetch = fetchImpl;
    this.baseUrl = baseUrl;
  }

  async request(method, path, body) {
    const response = await this.fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${this.token}`,
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (response.status === 204) return null;
    const text = await response.text();
    let parsed = null;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      // Apple answers HTML for some failures — a maintenance page, a proxy.
      // The status is the useful part; the body is not worth repeating.
    }
    if (!response.ok) {
      const detail = parsed?.errors
        ?.map((e) => [e.title, e.detail].filter(Boolean).join(': '))
        .join('; ');
      throw new Error(
        `App Store Connect ${method} ${path} failed: ${response.status}${detail ? ` — ${detail}` : ''}`,
      );
    }
    return parsed;
  }
}

/**
 * What to do about certificates before making another one.
 *
 * Apple allows a small number of distribution certificates per account, and a
 * cloud build cannot reuse one it has no private key for: the key stays where
 * it was generated. So each setup makes one, and this decides whether there is
 * room — and, when asked, which one to revoke to make room.
 *
 * Revoking is never implicit. A certificate somebody else's Mac is using would
 * stop working, and that is not a surprise to hand out.
 */
export function planCertificate({ existing, limit = 3, revokeOldest = false }) {
  if (existing.length < limit) return { action: 'create' };
  if (!revokeOldest) {
    return {
      action: 'refuse',
      reason:
        `Apple already holds ${existing.length} distribution certificates, which is the limit. ` +
        'Revoke one at developer.apple.com → Certificates, or re-run this with revoke_oldest set to yes ' +
        '— which will stop the oldest one from signing anything, including builds made elsewhere.',
    };
  }
  const oldest = [...existing].sort(
    (a, b) =>
      new Date(a.attributes?.expirationDate ?? 0).getTime() -
      new Date(b.attributes?.expirationDate ?? 0).getTime(),
  )[0];
  return { action: 'revoke-then-create', revokeId: oldest.id, revoked: oldest };
}

/** The bundle id, made if it is not there, with the team id read back from it. */
export async function ensureBundleId(api, { identifier, name }) {
  const search = await api.request(
    'GET',
    `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200`,
  );
  // Apple's filter is a prefix match on some accounts, so the exact one is
  // picked out rather than assumed to be the only row.
  const found = (search?.data ?? []).find(
    (row) => row.attributes?.identifier === identifier,
  );
  if (found) return { bundleId: found, created: false };

  const created = await api.request('POST', '/v1/bundleIds', {
    data: {
      type: 'bundleIds',
      attributes: { identifier, name, platform: 'IOS' },
    },
  });
  return { bundleId: created.data, created: true };
}

/**
 * Push notifications on the App ID.
 *
 * Without it the profile carries no `aps-environment`, signing fails, and the
 * error names an entitlement rather than a checkbox — which is a long way from
 * the cause.
 */
export async function ensurePushCapability(api, bundleIdId) {
  try {
    await api.request('POST', '/v1/bundleIdCapabilities', {
      data: {
        type: 'bundleIdCapabilities',
        attributes: { capabilityType: 'PUSH_NOTIFICATIONS' },
        relationships: {
          bundleId: { data: { type: 'bundleIds', id: bundleIdId } },
        },
      },
    });
    return { enabled: true, alreadyOn: false };
  } catch (err) {
    // Already enabled is the common answer and is not a failure.
    if (/409|already exists|ENTITY_ERROR/i.test(String(err))) {
      return { enabled: true, alreadyOn: true };
    }
    throw err;
  }
}

/** An App Store profile for exactly this bundle id and this certificate. */
export async function replaceProfile(api, { name, bundleIdId, certificateId }) {
  const existing = await api.request(
    'GET',
    `/v1/profiles?filter[name]=${encodeURIComponent(name)}&limit=200`,
  );
  const stale = (existing?.data ?? []).filter(
    (row) => row.attributes?.name === name,
  );
  // A profile is a snapshot of a certificate list. One made for a certificate
  // that has just been replaced is not repairable, only replaceable.
  for (const row of stale) await api.request('DELETE', `/v1/profiles/${row.id}`);

  const created = await api.request('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundleIdId } },
        certificates: { data: [{ type: 'certificates', id: certificateId }] },
      },
    },
  });
  return { profile: created.data, replaced: stale.length };
}

/**
 * The whole setup, in the order the pieces depend on each other.
 *
 * Returns what it did rather than printing it, so a caller can decide what is
 * worth saying out loud.
 */
export async function setUpSigning(api, options) {
  const {
    identifier,
    appName = 'Privio',
    csr,
    profileName,
    certificateType = 'IOS_DISTRIBUTION',
    revokeOldest = false,
    certificateLimit = 3,
  } = options;

  const { bundleId, created } = await ensureBundleId(api, {
    identifier,
    name: appName,
  });
  const push = await ensurePushCapability(api, bundleId.id);

  const list = await api.request(
    'GET',
    `/v1/certificates?filter[certificateType]=${certificateType}&limit=200`,
  );
  const plan = planCertificate({
    existing: list?.data ?? [],
    limit: certificateLimit,
    revokeOldest,
  });
  if (plan.action === 'refuse') throw new Error(plan.reason);
  if (plan.action === 'revoke-then-create') {
    await api.request('DELETE', `/v1/certificates/${plan.revokeId}`);
  }

  const certificate = await api.request('POST', '/v1/certificates', {
    data: {
      type: 'certificates',
      attributes: { certificateType, csrContent: csr },
    },
  });

  const { profile, replaced } = await replaceProfile(api, {
    name: profileName,
    bundleIdId: bundleId.id,
    certificateId: certificate.data.id,
  });

  return {
    bundleId: bundleId.attributes.identifier,
    bundleIdCreated: created,
    pushAlreadyEnabled: push.alreadyOn,
    teamId: bundleId.attributes.seedId ?? null,
    certificateId: certificate.data.id,
    certificateSerial: certificate.data.attributes.serialNumber ?? null,
    certificateExpires: certificate.data.attributes.expirationDate ?? null,
    certificateContent: certificate.data.attributes.certificateContent,
    revokedCertificateId: plan.revokeId ?? null,
    profileId: profile.id,
    profileName: profile.attributes.name,
    profileExpires: profile.attributes.expirationDate ?? null,
    profileContent: profile.attributes.profileContent,
    profilesReplaced: replaced,
  };
}

/** Reads the flags this is invoked with; unknown ones are a mistake, not a hint. */
export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (!flag?.startsWith('--') || value === undefined) {
      throw new Error(`Unusable argument: ${flag ?? '(nothing)'}`);
    }
    out[flag.slice(2).replace(/-/g, '_')] = value;
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const required = ['csr', 'bundle_id', 'out'];
  for (const name of required) {
    if (!args[name]) throw new Error(`Missing --${name.replace(/_/g, '-')}`);
  }
  const { APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_PRIVATE_KEY } = process.env;
  for (const [name, value] of Object.entries({
    APPSTORE_KEY_ID,
    APPSTORE_ISSUER_ID,
    APPSTORE_PRIVATE_KEY,
  })) {
    if (!value) throw new Error(`Missing environment variable ${name}`);
  }

  const { readFile } = await import('node:fs/promises');
  const csr = await readFile(args.csr, 'utf8');

  const api = new AppStoreConnect({
    token: ascJwt({
      keyId: APPSTORE_KEY_ID,
      issuerId: APPSTORE_ISSUER_ID,
      privateKey: APPSTORE_PRIVATE_KEY,
    }),
  });

  const result = await setUpSigning(api, {
    identifier: args.bundle_id,
    appName: args.app_name ?? 'Privio',
    csr,
    profileName: args.profile_name ?? `Privio App Store (${args.bundle_id})`,
    revokeOldest: args.revoke_oldest === 'yes',
  });

  await mkdir(args.out, { recursive: true });
  await writeFile(
    join(args.out, 'certificate.cer'),
    Buffer.from(result.certificateContent, 'base64'),
  );
  await writeFile(
    join(args.out, 'profile.mobileprovision'),
    Buffer.from(result.profileContent, 'base64'),
  );
  await writeFile(join(args.out, 'team-id.txt'), `${result.teamId ?? ''}`);

  const { certificateContent, profileContent, ...loggable } = result;
  await writeFile(
    join(args.out, 'summary.json'),
    `${JSON.stringify(loggable, null, 2)}\n`,
  );
  console.log(JSON.stringify(loggable, null, 2));
}

// Only when run as a program: importing this from a test must not call Apple.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  main().catch((err) => {
    console.error(`::error::${err.message}`);
    process.exit(1);
  });
}
