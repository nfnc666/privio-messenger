#!/usr/bin/env node
/**
 * What App Store Connect thinks of the builds that were uploaded.
 *
 * `UPLOAD SUCCEEDED` from altool means Apple accepted the delivery, and nothing
 * more. Processing happens afterwards, out of sight, and it can end in a build
 * that never appears in TestFlight — a rejected binary, a missing declaration —
 * with the only notice an email. Waiting and reloading is not a diagnosis.
 *
 * So this asks. It prints every build Apple holds for the bundle identifier,
 * with its processing state, its expiry, and whether the export compliance
 * question is still open, which is the commonest reason a processed build
 * cannot be installed by anybody.
 *
 * Read-only: it makes GET requests and changes nothing.
 */
import { AppStoreConnect, ascJwt, parseArgs } from './ios-signing-setup.mjs';

/** The app record, found by bundle identifier rather than by a numeric id. */
async function findApp(api, bundleId) {
  const found = await api.request(
    'GET',
    `/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=10`,
  );
  const app = found?.data?.[0];
  if (!app) {
    throw new Error(
      `No app record for bundle id ${bundleId}. TestFlight needs one before a build can appear.`,
    );
  }
  return app;
}

async function buildsFor(api, appId) {
  const result = await api.request(
    'GET',
    `/v1/builds?filter[app]=${appId}&limit=20&sort=-uploadedDate`
      + '&fields[builds]=version,processingState,uploadedDate,expired,expirationDate,usesNonExemptEncryption',
  );
  return result?.data ?? [];
}

/**
 * Why a processed build might still not be installable.
 *
 * `usesNonExemptEncryption` being null is Apple saying nobody has answered the
 * export compliance question for this build. Until somebody does, internal
 * testers do not get it — which looks exactly like a build that never arrived.
 */
function complianceNote(attributes) {
  if (attributes.usesNonExemptEncryption === null
    || attributes.usesNonExemptEncryption === undefined) {
    return 'export compliance UNANSWERED — testers cannot install until it is';
  }
  return `export compliance answered: usesNonExemptEncryption=${attributes.usesNonExemptEncryption}`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const bundleId = args.bundle_id;
  if (!bundleId) throw new Error('Missing --bundle-id');

  const { APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_PRIVATE_KEY } = process.env;
  for (const [name, value] of Object.entries({
    APPSTORE_KEY_ID,
    APPSTORE_ISSUER_ID,
    APPSTORE_PRIVATE_KEY,
  })) {
    if (!value) throw new Error(`Missing environment variable ${name}`);
  }

  const api = new AppStoreConnect({
    token: ascJwt({
      keyId: APPSTORE_KEY_ID,
      issuerId: APPSTORE_ISSUER_ID,
      privateKey: APPSTORE_PRIVATE_KEY,
    }),
  });

  const app = await findApp(api, bundleId);
  console.log(`App: ${app.attributes?.name ?? '(unnamed)'} — ${bundleId} (id ${app.id})`);

  const builds = await buildsFor(api, app.id);
  if (builds.length === 0) {
    console.log('');
    console.log('Apple holds NO builds for this app.');
    console.log('An accepted upload that produced no build means processing rejected it.');
    console.log('The reason is in the email Apple sends to the account holder; it is not in this API.');
    return;
  }

  console.log('');
  console.log(`Apple holds ${builds.length} build(s), newest first:`);
  for (const build of builds) {
    const a = build.attributes ?? {};
    console.log('');
    console.log(`  Build ${a.version ?? '?'}`);
    console.log(`    processing : ${a.processingState ?? 'unknown'}`);
    console.log(`    uploaded   : ${a.uploadedDate ?? 'unknown'}`);
    console.log(`    expired    : ${a.expired === true ? 'yes' : 'no'}`);
    console.log(`    ${complianceNote(a)}`);
  }
}

const invokedDirectly = process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop());
if (invokedDirectly) {
  main().catch((err) => {
    console.error(String(err.message ?? err));
    process.exit(1);
  });
}
