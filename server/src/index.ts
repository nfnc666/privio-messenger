import { config, configWarnings } from './config.js';
import { buildApp } from './app.js';
import { migrate } from './db/migrate.js';
import { onPoolError, pool } from './db/pool.js';
import { createBus } from './services/bus.js';
import { LocalFileStorage } from './services/storage.js';
import { startRetentionSweeper } from './services/cleanup.js';

const applied = await migrate();
const bus = await createBus();
const storage = new LocalFileStorage();
const app = await buildApp({ bus, storage });

if (applied.length > 0) app.log.info({ applied }, 'database migrations applied');

// Said once, at start-up, where an operator reading the deploy log will see it.
// These are configurations that run and lose something — attachments across a
// redeploy, two-factor enrolment, a second instance — not ones worth refusing.
for (const warning of configWarnings(config)) app.log.warn(warning);

// A dropped connection is survivable and must not be fatal: the pool discards
// the broken client and the next request opens a new one. `/health` is what
// reports the outage while it lasts.
onPoolError((err) => app.log.error({ err }, 'postgres connection lost; the pool will reconnect'));

const stopSweeper = startRetentionSweeper(storage, (err) => app.log.error({ err }, 'retention sweep failed'));

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  stopSweeper();
  await app.close();
  await bus.close();
  await pool.end();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

await app.listen({ port: config.PORT, host: config.HOST });
