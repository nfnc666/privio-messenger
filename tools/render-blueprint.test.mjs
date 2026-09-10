import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';

/**
 * The deployment blueprint is a file nothing in this repository executes: it is
 * read by Render, in a browser, on the day somebody deploys — which is the
 * worst moment to find out that the disk is mounted somewhere the server does
 * not write, or that the port it publishes is not the port it listens on.
 *
 * These are text-level checks, because the repository has no YAML parser and
 * adding a dependency to lint one file is a poor trade. They therefore prove
 * consistency between `render.yaml`, the `Dockerfile` and the server's config,
 * not that the YAML is valid — Render itself reports that, and it reports it
 * before anything is created.
 */

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const blueprint = readFileSync(join(root, 'render.yaml'), 'utf8');
const dockerfile = readFileSync(join(root, 'Dockerfile'), 'utf8');

/** The value of a `- key: NAME` entry's `value:`, or undefined. */
function envValue(name) {
  const match = blueprint.match(new RegExp(`- key: ${name}\\n\\s+value: (.+)`));
  return match ? match[1].trim().replace(/^["']|["']$/g, '') : undefined;
}

/** True when the named variable is left to the dashboard rather than to this file. */
function isPrompted(name) {
  return new RegExp(`- key: ${name}\\n\\s+sync: false`).test(blueprint);
}

describe('render blueprint', () => {
  it('publishes the port the image exposes', () => {
    const exposed = dockerfile.match(/^EXPOSE (\d+)$/m)?.[1];
    assert.ok(exposed, 'the Dockerfile should EXPOSE a port');
    assert.equal(envValue('PORT'), exposed);
  });

  it('writes attachments inside the mounted disk', () => {
    const mountPath = blueprint.match(/mountPath: (\S+)/)?.[1];
    assert.ok(mountPath, 'the service should mount a disk');
    const mediaDir = envValue('MEDIA_DIR');
    assert.ok(
      mediaDir?.startsWith(`${mountPath}/`) || mediaDir === mountPath,
      `MEDIA_DIR ${mediaDir} is outside the disk at ${mountPath}, so attachments would not survive a redeploy`,
    );
  });

  it('leaves the database connection to the dashboard', () => {
    // The Blueprint must not own DATABASE_URL. When it did, a sync reset the
    // variable to whatever this file declared — and after the real database had
    // been replaced by hand, that meant pointing a running service at one that
    // no longer existed. `sync: false` is what makes a dashboard value survive
    // every later sync.
    assert.ok(isPrompted('DATABASE_URL'), 'DATABASE_URL must be sync: false, not owned by this file');
    assert.equal(envValue('DATABASE_URL'), undefined, 'a connection string in this file would be a credential in the repository');
    assert.doesNotMatch(blueprint, /fromDatabase:/, 'a fromDatabase reference puts the connection back under Blueprint control');
    assert.doesNotMatch(blueprint, /^databases:/m, 'declaring the database here is what this file deliberately stopped doing');
  });

  it('states the service region explicitly', () => {
    // Render's internal hostnames resolve only within one region, so this value
    // is also the region the database has to be created in. The first real
    // deploy died with ENOTFOUND because the two did not match, and a region
    // cannot be changed afterwards — for a service or for a database. The
    // database is no longer declared here, so this file can only state the
    // region it requires; `docs/deployment.md` carries the instruction.
    const regions = [...blueprint.matchAll(/^\s+region: (\S+)$/gm)].map((m) => m[1]);
    assert.equal(regions.length, 1, `expected exactly one region, found ${regions.length}: ${regions.join(', ')}`);
    assert.ok(regions[0], 'the service must name its region rather than take a default');
  });

  it('runs in production mode, which is what makes the config guards apply', () => {
    assert.equal(envValue('NODE_ENV'), 'production');
  });

  it('checks health at the endpoint that asks the database', () => {
    assert.match(blueprint, /healthCheckPath: \/health/);
  });

  it('does not deploy on its own', () => {
    // A merge is not a release. Whoever deploys does it deliberately.
    assert.match(blueprint, /autoDeploy: false/);
  });

  it('leaves every credential to the dashboard', () => {
    for (const key of [
      'LICENSE_HASH_SECRET',
      'LICENSE_ISSUER_TOKEN',
      'TURN_SECRET',
      'APNS_KEY_P8',
      'APNS_KEY_ID',
      'APNS_TEAM_ID',
      'FCM_PRIVATE_KEY',
      'FCM_CLIENT_EMAIL',
    ]) {
      assert.ok(isPrompted(key), `${key} must be entered in the dashboard, never carried in this file`);
      assert.equal(envValue(key), undefined, `${key} must not have a literal value here`);
    }
    // The TOTP sealing key is the one secret the platform may mint, because
    // Render's generated value is base64 of 256 bits — exactly what it must be.
    assert.match(blueprint, /- key: TOTP_SECRET_KEY\n\s+generateValue: true/);
  });

  it('carries no key material of any kind', () => {
    assert.doesNotMatch(blueprint, /-----BEGIN/, 'a private key in a public repository');
    assert.doesNotMatch(blueprint, /postgres:\/\/\S+:\S+@/, 'a connection string with a password');
  });
});
