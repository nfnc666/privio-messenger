import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';

/**
 * Phone numbers, and the exact shape of the privacy claim being made.
 *
 * This file is where the contact-discovery design lives, so the claim is stated
 * here in full rather than implied by the code. **None of it is a claim of
 * anonymity, and none of it is equivalent to Signal's enclave-based discovery or
 * to Threema's architecture.** Those comparisons are not made anywhere in this
 * repository because they have not been demonstrated here.
 *
 * ## What actually happens
 *
 * 1. The client normalises a number to E.164 and computes
 *    `blind = HMAC-SHA256(DISCOVERY_CONTEXT, e164)`.
 * 2. It sends **only** blinds. A plaintext address book never reaches this
 *    server.
 * 3. The server computes `stored = HMAC-SHA256(pepper, blind)` and matches that
 *    against `phone_links.discovery_hash`.
 * 4. The submitted blinds are answered and dropped. Nothing is written.
 *
 * Both steps use HMAC-SHA256 from `node:crypto`. Nothing here is a primitive
 * this project invented, and there is no protocol here either — it is keyed
 * hashing, and that is all it is described as.
 *
 * ## What that buys
 *
 * - A dump of `phone_links` without the pepper says nothing. The pepper lives
 *   in the environment, not the database.
 * - The server is never handed a list of somebody's contacts in the clear, so
 *   the ordinary operation of the service does not accumulate address books.
 * - Nothing about the matching is stored, so there is no history of who looked
 *   for whom.
 *
 * ## What it does not buy, stated plainly
 *
 * - **[DISCOVERY_CONTEXT] is public.** It has to be: the client computes with
 *   it, and it ships in the app. Anyone who observes a blind can brute-force it
 *   back to a number, because the phone-number space is about 10^10 — minutes
 *   of work. A blind is *not* an anonymised number and this code never treats
 *   one as though it were.
 * - **The pepper plus the table is the whole table.** Somebody holding both can
 *   enumerate every number in `phone_links` for the same reason.
 * - **An operator could log what it is sent.** This server does not, and
 *   `docs/phone-contacts.md` says which routes that promise covers, but it is a
 *   property of this implementation rather than something the cryptography
 *   enforces. A design where the server *cannot* learn the query is a private
 *   set intersection protocol or a trusted enclave, and neither is here.
 *
 * The defence that actually limits enumeration is therefore the budget in
 * `contact_lookup_budget`, not the hashing. The hashing limits what a leak of
 * data at rest is worth.
 */

/**
 * The public key the client blinds with.
 *
 * A constant rather than configuration, because both sides must agree and the
 * client's copy ships in the app binary — configuration that one side cannot
 * change is not configuration. Its value is not a secret and nothing above
 * assumes it is.
 */
export const DISCOVERY_CONTEXT = 'privio.contact-discovery.v1';

export const PHONE_LIMITS = {
  /** How long a code is good for. */
  codeTtlSeconds: 10 * 60,
  /** Wrong guesses before the code is dead and a new one has to be asked for. */
  maxAttempts: 5,
  /** Sends of a code for one attempt at one number, the first included. */
  maxSends: 3,
  /** The wait between sends, so "resend" is not a way to send somebody 30 texts. */
  resendAfterSeconds: 60,
  /** Numbers one account may look up in a day. */
  lookupsPerDay: 2000,
  /** Numbers in one request. */
  lookupsPerRequest: 200,
} as const;

/** A number that passed the shape check, and the hint to show for it. */
export interface NormalisedPhone {
  e164: string;
  hint: string;
}

/**
 * Calling codes, longest first so `+1` cannot swallow `+1242`.
 *
 * Data, not validation: it is here so a number can be split into "country" and
 * "the rest" for the hint, and so obvious nonsense is refused before an SMS is
 * paid for. **The real check is the code that arrives by text.** A list like
 * this cannot know whether a number is in service, and this file does not
 * pretend it can — which is why there is no attempt at per-country length rules.
 */
const CALLING_CODES = [
  '1242','1246','1264','1268','1284','1340','1345','1441','1473','1649','1664','1670','1671','1684',
  '1721','1758','1767','1784','1809','1829','1849','1868','1869','1876','1939',
  '212','213','216','218','220','221','222','223','224','225','226','227','228','229',
  '230','231','232','233','234','235','236','237','238','239','240','241','242','243','244','245',
  '246','247','248','249','250','251','252','253','254','255','256','257','258','260','261','262',
  '263','264','265','266','267','268','269','290','291','297','298','299',
  '350','351','352','353','354','355','356','357','358','359',
  '370','371','372','373','374','375','376','377','378','379','380','381','382','383','385','386',
  '387','389','420','421','423',
  '500','501','502','503','504','505','506','507','508','509',
  '590','591','592','593','594','595','596','597','598','599',
  '670','672','673','674','675','676','677','678','679','680','681','682','683','685','686','687',
  '688','689','690','691','692',
  '850','852','853','855','856','870','880','886',
  '960','961','962','963','964','965','966','967','968','970','971','972','973','974','975','976',
  '977','992','993','994','995','996','998',
  '20','27','30','31','32','33','34','36','39','40','41','43','44','45','46','47','48','49',
  '51','52','53','54','55','56','57','58','60','61','62','63','64','65','66',
  '81','82','84','86','90','91','92','93','94','95','98',
  '7','1',
].sort((a, b) => b.length - a.length);

/**
 * Turns what somebody typed into E.164, or null.
 *
 * Accepts the shapes people actually write — spaces, dashes, brackets, a
 * leading `00` — and refuses anything that is not a plausible international
 * number. It does **not** guess a country: a number with no calling code is
 * refused rather than assumed to be local, because assuming would silently
 * attach somebody to a number in a country they have never been to.
 */
export function normalisePhone(input: string): NormalisedPhone | null {
  const trimmed = input.trim();
  if (trimmed.length === 0) return null;

  // `00` is how most of the world writes `+` on a keypad.
  const withPlus = trimmed.startsWith('00') ? `+${trimmed.slice(2)}` : trimmed;
  if (!withPlus.startsWith('+')) return null;

  const digits = withPlus.slice(1).replace(/[\s\-().]/g, '');
  if (!/^[0-9]{7,15}$/.test(digits)) return null;

  const code = CALLING_CODES.find((candidate) => digits.startsWith(candidate));
  if (code === undefined) return null;
  // A calling code and nothing after it is not a number.
  const rest = digits.slice(code.length);
  if (rest.length < 4) return null;

  return {
    e164: `+${digits}`,
    // The country, and the last two digits. Enough to recognise which of your
    // own numbers this is; not enough to be anybody's number.
    hint: `+${code} … ${digits.slice(-2)}`,
  };
}

/**
 * What the client sends: the number under the public context key.
 *
 * Here as well as in the app because the server needs it to link *its own*
 * user's number at verification time, where it does hold the plaintext briefly
 * — it has to, in order to send a text to it. The two implementations must
 * agree exactly, which is what `phone.test.ts` pins.
 */
export function blindPhone(e164: string): Buffer {
  return createHmac('sha256', DISCOVERY_CONTEXT).update(e164).digest();
}

/**
 * What is stored and matched: the blind under the server's secret.
 *
 * Throws rather than falling back to an empty key when the pepper is missing.
 * A server that silently hashed under `''` would produce a table that looks
 * protected and is not, and it would do it quietly — which is the failure this
 * whole file is arranged to avoid.
 */
export function discoveryHash(blind: Buffer): Buffer {
  const pepper = config.CONTACT_DISCOVERY_PEPPER;
  if (pepper.length === 0) {
    throw new Error(
      'CONTACT_DISCOVERY_PEPPER is not set. Contact discovery stores keyed hashes ' +
        'and refuses to run without the key — see docs/phone-contacts.md.',
    );
  }
  return createHmac('sha256', pepper).update(blind).digest();
}

/** Whether discovery can run at all on this deployment. */
export function discoveryConfigured(): boolean {
  return config.CONTACT_DISCOVERY_PEPPER.length > 0;
}

/** Both hashes for a number the server is holding in plaintext, briefly. */
export function hashesFor(e164: string): Buffer {
  return discoveryHash(blindPhone(e164));
}

export function sameHash(a: Buffer, b: Buffer): boolean {
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * A six-digit code.
 *
 * `randomInt` rather than `Math.random`, and without a leading-zero problem:
 * the range is 0–999999 padded to six characters, so `000042` is a code that
 * can be issued rather than one that quietly cannot.
 */
export function generateCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}
