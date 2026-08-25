import { config } from './config.js';
import { buildApp } from './app.js';
import { migrate } from './db/migrate.js';
import { pool } from './db/pool.js';
import { createBus } from './services/bus.js';
import { LocalFileStorage } from './services/storage.js';
import { startRetentionSweeper } from './services/cleanup.js';

const applied = await migrate();
const bus = await createBus();
const storage = new LocalFileStorage();
const app = await buildApp({ bus, storage });

if (applied.length > 0) app.log.info({ applied }, 'database migrations applied');

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
