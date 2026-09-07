import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { migrate } from '../src/db/migrate.js';
import { pool } from '../src/db/pool.js';
import { InProcessBus, type DeliveryBus } from '../src/services/bus.js';
import { LoggingPushSender, type PushSender } from '../src/services/push.js';
import { LocalFileStorage } from '../src/services/storage.js';
import { deviceRegistrationSchema } from '../src/services/devices.js';

export interface TestHarness {
  app: FastifyInstance;
  push: LoggingPushSender;
  storage: LocalFileStorage;
  /**
   * The in-process bus, or whatever was passed in its place. Typed as the
   * interface so a test can hand in a bus that fails on purpose — what a Redis
   * outage looks like from the API's side.
   */
  bus: DeliveryBus;
  close: () => Promise<void>;
}

let counter = 0;

/** Boots the API against the test database with an in-process bus and temp storage. */
export async function createHarness(
  overrides: { push?: PushSender; bus?: DeliveryBus } = {},
): Promise<TestHarness> {
  await migrate();
  await truncateAll();
  const dir = await mkdtemp(join(tmpdir(), 'privio-test-'));
  const bus = overrides.bus ?? new InProcessBus();
  const push = new LoggingPushSender();
  const storage = new LocalFileStorage(dir);
  const app = await buildApp({ bus, push: overrides.push ?? push, storage });
  await app.ready();
  return {
    app,
    push,
    storage,
    bus,
    close: async () => {
      await app.close();
      await bus.close();
      await rm(dir, { recursive: true, force: true });
    },
  };
}

export async function truncateAll(): Promise<void> {
  await pool.query(
    'TRUNCATE accounts, devices, sessions, contacts, blocks, groups, group_members, envelopes, media_objects, backups, licenses RESTART IDENTITY CASCADE',
  );
}

export async function closePool(): Promise<void> {
  await pool.end();
}

/** Plausible X3DH registration material. The bytes are opaque to the server. */
export function deviceFixture(overrides: Partial<Record<string, unknown>> = {}) {
  counter += 1;
  const bytes = (seed: number, length = 32) =>
    Buffer.from(Array.from({ length }, (_, i) => (seed * 31 + i * 7) % 256)).toString('base64');
  return deviceRegistrationSchema.parse({
    name: `Test Device ${counter}`,
    platform: 'ios',
    registrationId: 1000 + counter,
    identityKey: bytes(counter),
    signedPreKey: { keyId: counter, publicKey: bytes(counter + 1), signature: bytes(counter + 2, 64) },
    oneTimePreKeys: [
      { keyId: counter * 10 + 1, publicKey: bytes(counter + 3) },
      { keyId: counter * 10 + 2, publicKey: bytes(counter + 4) },
    ],
    ...overrides,
  });
}

/** The API takes base64, but the fixture schema decodes to Buffers — re-encode. */
export function deviceBody(device: ReturnType<typeof deviceFixture>) {
  return {
    name: device.name,
    platform: device.platform,
    registrationId: device.registrationId,
    identityKey: device.identityKey.toString('base64'),
    signedPreKey: {
      keyId: device.signedPreKey.keyId,
      publicKey: device.signedPreKey.publicKey.toString('base64'),
      signature: device.signedPreKey.signature.toString('base64'),
    },
    oneTimePreKeys: device.oneTimePreKeys.map((k) => ({
      keyId: k.keyId,
      publicKey: k.publicKey.toString('base64'),
    })),
  };
}

export interface TestUser {
  accountId: string;
  deviceId: string;
  username: string;
  token: string;
}

export async function registerUser(
  app: FastifyInstance,
  username: string,
  password = 'correct-horse-battery',
): Promise<TestUser> {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/accounts',
    payload: { username, password, device: deviceBody(deviceFixture()) },
  });
  if (response.statusCode !== 201) throw new Error(`register failed: ${response.body}`);
  return response.json() as TestUser;
}

export function bearer(user: TestUser) {
  return { authorization: `Bearer ${user.token}` };
}
