import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { configWarnings, loadConfig } from '../src/config.js';
import { closePool, createHarness, type TestHarness } from './helpers.js';

/**
 * The two things that only bite in production, and therefore never got exercised:
 * a health check that could not fail, and a database URL that defaulted to
 * localhost on a machine where nothing listens there.
 */
describe('deployment safety', () => {
  describe('production configuration', () => {
    const productionEnv = (extra: NodeJS.ProcessEnv = {}) => ({
      NODE_ENV: 'production',
      DATABASE_URL: 'postgres://privio:secret@db.example.org:5432/privio',
      ...extra,
    }) as NodeJS.ProcessEnv;

    it('refuses to start in production without an explicit DATABASE_URL', () => {
      assert.throws(
        () => loadConfig({ NODE_ENV: 'production' } as NodeJS.ProcessEnv),
        /DATABASE_URL/,
        'the localhost default must not be inherited by a production boot',
      );
    });

    it('accepts a production environment that names its database', () => {
      const cfg = loadConfig(productionEnv());
      assert.equal(cfg.DATABASE_URL, 'postgres://privio:secret@db.example.org:5432/privio');
    });

    it('still allows localhost when it is stated on purpose', () => {
      // A database beside the server — docker compose, a single VPS — is a real
      // deployment. What is refused is the *unstated* default, not the value.
      const cfg = loadConfig(productionEnv({ DATABASE_URL: 'postgres://privio@localhost:5432/privio' }));
      assert.equal(cfg.DATABASE_URL, 'postgres://privio@localhost:5432/privio');
    });

    it('leaves development alone', () => {
      const cfg = loadConfig({} as NodeJS.ProcessEnv);
      assert.equal(cfg.NODE_ENV, 'development');
      assert.match(cfg.DATABASE_URL, /localhost/);
    });

    it('warns when attachments would be written to an ephemeral path', () => {
      const env = productionEnv();
      const warnings = configWarnings(loadConfig(env), env);
      assert.ok(
        warnings.some((w) => w.includes('MEDIA_DIR')),
        `expected a MEDIA_DIR warning, got: ${JSON.stringify(warnings)}`,
      );
    });

    it('says nothing about MEDIA_DIR once a volume is configured', () => {
      const env = productionEnv({ MEDIA_DIR: '/data/media' });
      const warnings = configWarnings(loadConfig(env), env);
      assert.ok(!warnings.some((w) => w.includes('MEDIA_DIR')), JSON.stringify(warnings));
    });

    it('warns about disabled two-factor and single-node operation', () => {
      const env = productionEnv();
      const warnings = configWarnings(loadConfig(env), env);
      assert.ok(warnings.some((w) => w.includes('TOTP_SECRET_KEY')));
      assert.ok(warnings.some((w) => w.includes('REDIS_URL')));
    });

    it('warns about nothing outside production', () => {
      assert.deepEqual(configWarnings(loadConfig({} as NodeJS.ProcessEnv), {} as NodeJS.ProcessEnv), []);
    });
  });

  describe('GET /health', () => {
    let healthy: TestHarness;

    before(async () => {
      healthy = await createHarness();
    });
    after(async () => {
      await healthy.close();
      await closePool();
    });

    it('reports ok against a reachable database', async () => {
      const res = await healthy.app.inject({ method: 'GET', url: '/health' });
      assert.equal(res.statusCode, 200);
      assert.deepEqual(res.json(), { status: 'ok', version: '0.1.0', database: 'ok' });
    });

    it('reports 503 when the database round trip fails', async () => {
      // Before this existed the same instance answered 200 here, so a platform
      // health check kept a server with a dead database in the load balancer.
      const broken = await createHarness({
        pingDatabase: async () => {
          throw new Error('connect ECONNREFUSED 10.0.0.9:5432');
        },
      });
      try {
        const res = await broken.app.inject({ method: 'GET', url: '/health' });
        assert.equal(res.statusCode, 503);
        assert.equal(res.json().status, 'unhealthy');
        assert.equal(res.json().database, 'unreachable');
      } finally {
        await broken.close();
      }
    });

    it('does not leak the failure detail to an unauthenticated caller', async () => {
      const broken = await createHarness({
        pingDatabase: async () => {
          throw new Error('password authentication failed for user "privio"');
        },
      });
      try {
        const res = await broken.app.inject({ method: 'GET', url: '/health' });
        assert.equal(res.statusCode, 503);
        assert.ok(!res.body.includes('password'), `health body leaked the error: ${res.body}`);
      } finally {
        await broken.close();
      }
    });
  });
});
