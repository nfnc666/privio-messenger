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

export const uuidSchema = z.string().uuid();
