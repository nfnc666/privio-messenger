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
  /**
   * How often an open WebSocket re-reads its session.
   *
   * The revocation broadcast is what closes a socket promptly; this is the
   * backstop for what a broadcast cannot cover — a session that merely expired,
   * a revocation published while this process was disconnected from Redis, or a
   * row changed by something that never went through the API. It is therefore
   * also the width of the worst-case window between "the session ended" and
   * "the socket stopped", and it is configuration rather than a constant so
   * that a deployment can trade queries for promptness, and so a test can drive
   * the real timer instead of a stand-in for it.
   */
  WS_REVALIDATE_MS: z.coerce.number().int().positive().default(60_000),
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
   * Where the invite pages live, as an absolute origin
   * (`https://privio.channel`). Empty means "wherever this request arrived",
   * which is the right default for a deployment that has no domain of its own
   * yet — the pages then work on the server's own hostname.
   *
   * This is the one constant a registered domain changes. The app's
   * `ChannelService.channelLinkHost` is its twin on the client side, and the
   * two have to agree or a link built by one will not be recognised by the
   * other.
   */
  PUBLIC_WEB_URL: z.string().default(''),

  /**
   * Where to send somebody who does not have the app.
   *
   * All three are empty by default and the page shows only what is set. That
   * is deliberate: a download button that leads to a store listing which does
   * not exist is worse than no button, and this project currently ships
   * through TestFlight and CI artifacts rather than either store.
   */
  APP_STORE_URL: z.string().default(''),
  PLAY_STORE_URL: z.string().default(''),
  APK_DOWNLOAD_URL: z.string().default(''),

  /**
   * What the domain-verification files say, for iOS Universal Links and
   * Android App Links.
   *
   * Unset means the files are not served at all rather than served empty: a
   * malformed `apple-app-site-association` is cached by Apple's CDN for days,
   * and a 404 is the state Apple and Google both handle correctly.
   *
   * `IOS_APP_ID` is `<team id>.<bundle id>`. `ANDROID_CERT_FINGERPRINTS` is a
   * comma-separated list of SHA-256 signing-certificate fingerprints — plural
   * because an app signed by Play App Signing has both an upload certificate
   * and the one Google re-signs with, and a link verified against only one of
   * them fails for half the installs.
   */
  IOS_APP_ID: z.string().default(''),
  ANDROID_PACKAGE: z.string().default(''),
  ANDROID_CERT_FINGERPRINTS: z.string().default(''),

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
   * Base64 of 32 random bytes, used to seal TOTP secrets at rest.
   *
   * A TOTP secret is a bearer credential: whoever reads it can generate the
   * codes forever. Stored in the clear it meant a database leak alone —
   * a stolen backup, a read-only replica, one SQL injection — defeated the
   * second factor for every account on the server, without anyone touching
   * the machine.
   *
   * Sealing them with a key that lives in the environment separates the two:
   * an attacker now needs the database *and* the process configuration. It is
   * not protection against a fully compromised server, which holds the key by
   * definition, and this is not claimed anywhere.
   *
   * Generate one with `openssl rand -base64 32`. Without it the server runs
   * and refuses to enrol anyone in two-factor, rather than quietly storing
   * the next secret in the clear.
   */
  TOTP_SECRET_KEY: z.string().optional(),

  /**
   * Comma-separated hosts that may be registered as UnifiedPush endpoints.
   *
   * Empty means any publicly routable HTTPS host, which is the point of
   * UnifiedPush — the distributor is the user's choice, and often their own.
   * A deployment that would rather not make outbound requests to wherever can
   * narrow it to the distributors it trusts.
   */
  UNIFIEDPUSH_ALLOWED_HOSTS: z.string().default(''),

  /**
   * Apple Push Notification service. All four or none.
   *
   * `APNS_KEY_P8` is the contents of the `.p8` file from the developer portal,
   * not a path: a key on disk is a key in a container image and a key in a
   * backup. Newlines may be written as `\n`, because most secret stores make
   * a literal newline awkward.
   *
   * Without these, APNs is not configured and the server says so at start-up
   * rather than pretending to deliver.
   */
  APNS_KEY_P8: z.string().optional(),
  APNS_KEY_ID: z.string().optional(),
  APNS_TEAM_ID: z.string().optional(),
  /** The app's bundle identifier. The VoIP topic is this plus `.voip`. */
  APNS_TOPIC: z.string().optional(),
  /** `production` or `sandbox`. A TestFlight build needs the sandbox host. */
  APNS_ENVIRONMENT: z.enum(['production', 'sandbox']).default('production'),

  /**
   * Firebase Cloud Messaging, from a service-account key.
   *
   * The three fields taken out of the JSON Google hands you, rather than the
   * whole file, so that what the server holds is exactly what it needs.
   */
  FCM_PROJECT_ID: z.string().optional(),
  FCM_CLIENT_EMAIL: z.string().optional(),
  FCM_PRIVATE_KEY: z.string().optional(),
}).superRefine((env, ctx) => {
  // Half-configured is worse than unconfigured: it looks like it works.
  const apns = [env.APNS_KEY_P8, env.APNS_KEY_ID, env.APNS_TEAM_ID, env.APNS_TOPIC];
  if (apns.some(Boolean) && !apns.every(Boolean)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['APNS_KEY_P8'],
      message:
        'APNs needs APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID and APNS_TOPIC together, or none of them',
    });
  }
  const fcm = [env.FCM_PROJECT_ID, env.FCM_CLIENT_EMAIL, env.FCM_PRIVATE_KEY];
  if (fcm.some(Boolean) && !fcm.every(Boolean)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['FCM_PROJECT_ID'],
      message:
        'FCM needs FCM_PROJECT_ID, FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY together, or none of them',
    });
  }

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

/**
 * Defaults that are useful on a laptop and wrong on a server.
 *
 * Every value in the schema above has a default so that `npm run dev` works
 * with an empty environment. That convenience has a failure mode: a production
 * deployment that forgets `DATABASE_URL` does not fail to start, it starts
 * against `localhost`, creates an empty schema in whatever database happens to
 * be there — or none — and looks healthy while it serves nobody. Refusing to
 * boot is the cheaper outcome, and it is checked against the raw environment
 * rather than the parsed config because after parsing there is no way to tell
 * "unset" from "deliberately localhost", which is a legitimate answer when the
 * database runs beside the server.
 */
function assertProductionEnv(env: NodeJS.ProcessEnv): void {
  if (env.NODE_ENV !== 'production') return;
  if (!env.DATABASE_URL) {
    throw new Error(
      'Invalid environment configuration — DATABASE_URL: must be set explicitly when NODE_ENV=production; '
        + 'the built-in localhost default is a development convenience and would silently point production at the wrong database',
    );
  }
}

/**
 * Configuration that starts but will lose data or capability, as human-readable
 * lines. The caller logs them; nothing here prevents a boot.
 */
export function configWarnings(cfg: Config, env: NodeJS.ProcessEnv = process.env): string[] {
  const warnings: string[] = [];
  if (cfg.NODE_ENV !== 'production') return warnings;

  if (!env.MEDIA_DIR) {
    warnings.push(
      `MEDIA_DIR is unset, so attachments are written to ${cfg.MEDIA_DIR} inside the container. `
        + 'On a platform with an ephemeral filesystem every redeploy discards them. '
        + 'Point it at a persistent volume.',
    );
  }
  if (!cfg.TOTP_SECRET_KEY) {
    warnings.push(
      'TOTP_SECRET_KEY is unset: the server runs but refuses to enrol anyone in two-factor authentication.',
    );
  }
  if (!cfg.REDIS_URL) {
    warnings.push(
      'REDIS_URL is unset: this process runs as a single node with an in-process event bus. '
        + 'Correct for one instance, wrong the moment a second one is started.',
    );
  }
  return warnings;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  assertProductionEnv(env);
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
