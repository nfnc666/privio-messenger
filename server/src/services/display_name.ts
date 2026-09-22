/**
 * The name a person chooses for themselves, and what the server does to it.
 *
 * A display name is the one field here that is *meant* to be free text: spaces,
 * umlauts, scripts of every kind, emoji. So this is deliberately not a filter
 * on what somebody may be called — it removes only characters that are invisible
 * and therefore cannot be part of what anybody meant to type.
 *
 * Why the server does it at all, when the app does the same thing before
 * sending: the app is not the only client, and this column is read by every
 * other account. A name carrying a right-to-left override can reorder the line
 * it is drawn in — including the `@username` beside it, which is the one thing
 * on that row that is supposed to be unforgeable.
 */

/**
 * Invisible characters, minus the ones that make emoji and some scripts work.
 *
 * Kept on purpose: U+200C (ZWNJ) and U+200D (ZWJ), which join an emoji family
 * into one glyph and separate letters in Persian, Hindi and others, and the
 * variation selectors that decide whether a character is drawn as text or as
 * an emoji. Stripping those would not be sanitising a name, it would be
 * misspelling it.
 *
 * Removed: C0 and C1 controls, the soft hyphen, the bidi marks, overrides and
 * isolates, the invisible-operator block, the zero-width space and the byte
 * order mark.
 */
const INVISIBLE =
  // eslint-disable-next-line no-control-regex
  /[\u0000-\u001F\u007F-\u009F­؜​‎‏‪-‮⁠-⁤⁦-⁩﻿]/gu;

/** Every kind of space, including the ones that are not a space bar. */
const WHITESPACE = /[\s   -   　]+/gu;

/** Fifty of what a person would count, not of what UTF-16 counts. */
export const DISPLAY_NAME_LIMIT = 50;

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

/**
 * How long a name is to the person who typed it.
 *
 * `String.length` counts UTF-16 code units, which makes one emoji two or four
 * characters and one flag eight. A limit measured that way would refuse a name
 * that looks short and accept one that looks long.
 */
export function visibleLength(value: string): number {
  let count = 0;
  for (const _ of segmenter.segment(value)) count += 1;
  return count;
}

/**
 * The cleaned name, or null for "no name" — which is a legitimate answer.
 *
 * Null means the account falls back to its `@username` everywhere it is drawn.
 * That is why an empty string and a string of only spaces both come back as
 * null rather than as an error: somebody clearing the field is not somebody
 * making a mistake.
 */
export function cleanDisplayName(value: string): string | null {
  const collapsed = value.replace(INVISIBLE, '').replace(WHITESPACE, ' ').trim();
  // NFC so that a name typed with combining marks is stored the way the rest
  // of the world will send the same name, and so the length below is counted
  // on the composed form.
  const normalised = collapsed.normalize('NFC');
  return normalised.length === 0 ? null : normalised;
}

/** True when the cleaned name is longer than a name has any need to be. */
export function isTooLong(value: string): boolean {
  return visibleLength(value) > DISPLAY_NAME_LIMIT;
}
