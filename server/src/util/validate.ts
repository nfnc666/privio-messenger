import { z } from 'zod';
import { ApiError } from './errors.js';

export function parse<T extends z.ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const detail = result.error.issues
      .map((i) => `${i.path.join('.') || 'body'}: ${i.message}`)
      .join('; ');
    throw ApiError.badRequest('invalid_request', detail);
  }
  return result.data;
}

/** Base64 field that decodes to a Buffer within the given size bounds. */
export const base64Bytes = (min: number, max: number) =>
  z
    .string()
    .max(Math.ceil((max * 4) / 3) + 4, `must be at most ${max} bytes`)
    .transform((value, ctx) => {
      const buf = Buffer.from(value, 'base64');
      // Buffer.from silently drops invalid characters, so re-encode to confirm.
      if (buf.toString('base64').replace(/=+$/, '') !== value.replace(/=+$/, '').replace(/-/g, '+').replace(/_/g, '/')) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'must be valid base64' });
        return z.NEVER;
      }
      if (buf.length < min || buf.length > max) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `must decode to between ${min} and ${max} bytes`,
        });
        return z.NEVER;
      }
      return buf;
    });

export const usernameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9_.]{3,32}$/, 'must be 3-32 characters of a-z, 0-9, underscore or dot');

/**
 * Passwords and PINs are stretched with Argon2id server-side, but a short PIN is
 * only ever a *local* lock — the account password must carry real entropy.
 */
export const passwordSchema = z.string().min(10).max(1024);

/**
 * The longest a disappearing message may live: twenty-four hours.
 *
 * One constant rather than a number repeated in three schemas, because the
 * ceiling is the feature. A timer is a promise that a message goes away, and a
 * promise measured in weeks is a different product — long enough that people
 * stop treating the chat as temporary while the server still holds ciphertext
 * for it.
 *
 * Enforced here as well as in the app, and that is the point: the app's list of
 * options is a convenience, this is what a direct API call meets. See
 * `server/test/disappearing.test.ts`.
 */
export const MAX_DISAPPEAR_SECONDS = 86_400;

/** A timer on the wire: a positive number of seconds, at most a day. */
export const disappearSecondsSchema = z
  .number()
  .int()
  .positive()
  .max(MAX_DISAPPEAR_SECONDS);

export const uuidSchema = z.string().uuid();

/**
 * A boolean in a query string.
 *
 * Not `z.coerce.boolean()`, which is `Boolean(value)` and therefore maps the
 * string `"false"` to **true** — every non-empty string is truthy. A filter
 * written as `?open=false` then quietly means the same as `?open=true`, which
 * is the kind of bug that never throws and is only found by noticing the
 * answer was wrong. Only the two words are accepted; anything else is a 400
 * rather than a guess.
 */
export const booleanQuery = (fallback: boolean) =>
  z
    .enum(['true', 'false'])
    .default(fallback ? 'true' : 'false')
    .transform((value) => value === 'true');
