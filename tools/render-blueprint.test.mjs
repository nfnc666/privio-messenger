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

  it('takes the database URL from the managed database rather than a literal', () => {
    assert.match(blueprint, /- key: DATABASE_URL\n\s+fromDatabase:\n\s+name: (\S+)\n\s+property: connectionString/);
    // A reference to a database this file does not declare is how a Blueprint
    // sync points a working service at something that no longer exists.
    const referenced = blueprint.match(/fromDatabase:\n\s+name: (\S+)/)?.[1];
    assert.ok(
      new RegExp(`\\n  - name: ${referenced}\\n`).test(blueprint),
      `DATABASE_URL points at "${referenced}", which no databases: entry defines`,
    );
    assert.equal(envValue('DATABASE_URL'), undefined, 'a connection string in this file would be a credential in the repository');
  });

  it('puts the database in the same region as the service', () => {
    // Render creates a database with no `region` in its own default region, not
    // in the region of the service that references it, and a private hostname
    // does not resolve across regions. The first real deploy of this Blueprint
    // died with ENOTFOUND for exactly that reason, and the file's comment had
    // asserted the opposite. Both regions are read, so this catches a mismatch
    // as well as an omission — and a region cannot be changed after the fact.
    const regions = [...blueprint.matchAll(/^\s+region: (\S+)$/gm)].map((m) => m[1]);
    assert.equal(regions.length, 2, `expected a region on both the service and the database, found ${regions.length}`);
    assert.equal(
      regions[0],
      regions[1],
      `service is in ${regions[0]}, database in ${regions[1]} — the private hostname will not resolve`,
    );
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
