import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().default('postgres://postgres@localhost:5432/privio'),
  /** Optional. Without it the server runs single-node with an in-process event bus. */
  REDIS_URL: z.string().optional(),
  /** Where encrypted attachment blobs are written. */
  MEDIA_DIR: z.string().default('./.data/media'),
  /** Attachments are unconditionally deleted after this many days. */
  MEDIA_TTL_DAYS: z.coerce.number().int().positive().default(30),
  SESSION_TTL_DAYS: z.coerce.number().int().positive().default(365),
  /** Undelivered envelopes are purged after this many days. */
  ENVELOPE_TTL_DAYS: z.coerce.number().int().positive().default(30),
  MAX_ENVELOPE_BYTES: z.coerce.number().int().positive().default(64 * 1024),
  MAX_MEDIA_BYTES: z.coerce.number().int().positive().default(100 * 1024 * 1024),
  MAX_BACKUP_BYTES: z.coerce.number().int().positive().default(512 * 1024 * 1024),
  /**
   * Comma-separated origins allowed to call the API from a browser. The mobile
   * apps are not subject to CORS; this exists for local development and for a
   * future web client. Empty means no browser origin is allowed.
   */
  CORS_ORIGINS: z.string().default(''),
  LOG_LEVEL: z.string().default('info'),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ');
    throw new Error(`Invalid environment configuration — ${issues}`);
  }
  return parsed.data;
}

export const config = loadConfig();
