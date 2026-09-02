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

  /**
   * STUN and TURN servers this deployment offers its clients, comma-separated
   * (`stun:stun.example.org:3478,turns:turn.example.org:5349`).
   *
   * Configured here rather than baked into each build so that a self-hoster
   * sets it once and every client picks it up. Empty is a real answer and the
   * default: the two devices then try only the addresses they can see for
   * themselves, which works on one network and behind simple NATs, and fails
   * behind strict ones.
   */
  ICE_SERVERS: z.string().default(''),
  /**
   * Shared secret for time-limited TURN credentials, as coturn's
   * `use-auth-secret` / `static-auth-secret` expects.
   *
   * A TURN server needs a username and password, and a fixed pair shipped in a
   * client is a public TURN server within a day. With this set, the API mints
   * a username of `<expiry>` and an HMAC-SHA1 password over it, which is the
   * scheme coturn implements. Without it, any TURN URL configured above is
   * offered without credentials — which only works on a server that wants
   * none.
   */
  TURN_SECRET: z.string().min(16).optional(),
  /** How long a minted TURN credential is good for. */
  TURN_TTL_SECONDS: z.coerce.number().int().positive().default(12 * 60 * 60),

  /**
   * Whether this deployment sells access. The hosted server sets it true and
   * refuses to relay for unlicensed accounts; a self-hosted server leaves it
   * false, because a licence for infrastructure you already run means nothing.
   */
  LICENSE_REQUIRED: z
    .enum(['true', 'false'])
    .default('false')
    .transform((value) => value === 'true'),
  /**
   * Key for the HMAC that license keys are stored under. Rotating it orphans
   * every license ever issued, because the stored hashes stop matching — treat
   * it as permanent.
   */
  LICENSE_HASH_SECRET: z.string().min(32).optional(),
  /** Bearer token the website presents to issue and revoke licenses. */
  LICENSE_ISSUER_TOKEN: z.string().min(32).optional(),

  /**
   * Comma-separated hosts that may be registered as UnifiedPush endpoints.
   *
   * Empty means any publicly routable HTTPS host, which is the point of
   * UnifiedPush — the distributor is the user's choice, and often their own.
   * A deployment that would rather not make outbound requests to wherever can
   * narrow it to the distributors it trusts.
   */
  UNIFIEDPUSH_ALLOWED_HOSTS: z.string().default(''),
}).superRefine((env, ctx) => {
  // Better to refuse to boot than to run a paid server that cannot tell who
  // has paid.
  if (env.LICENSE_REQUIRED && !env.LICENSE_HASH_SECRET) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['LICENSE_HASH_SECRET'],
      message: 'must be set when LICENSE_REQUIRED is true',
    });
  }
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

/**
 * Multiplier applied to every rate limit. Tests drive hundreds of requests from
 * one address and are not exercising the limiter; production runs at 1.
 *
 * `RATE_LIMIT_FACTOR=1` puts a test back on the real budget, which is how the
 * limiter itself gets tested.
 */
export const rateLimitFactor = Number(process.env.RATE_LIMIT_FACTOR)
  || (config.NODE_ENV === 'test' ? 1000 : 1);
