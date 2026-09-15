/**
 * What an uploaded image actually is, read out of its own bytes.
 *
 * The client says what it is sending. That is a claim, not a fact, and a server
 * that files it under the claim has checked nothing: a `.png` content type on a
 * multi-megabyte blob of anything at all would sail through. So the type comes
 * from the magic bytes and the dimensions from the header, and the declared
 * content type is not consulted at any point.
 *
 * Written by hand rather than with an image library, and that is a deliberate
 * trade. Reading two headers is about sixty lines; the alternative is `sharp`,
 * which is a native binary and a build step, in a server that currently has
 * neither. What is given up is decoding — this does not prove the pixel data is
 * intact, only that the file announces itself as a PNG or a WebP of a stated
 * size. That is the right bar for a sticker: the bytes are served back to a
 * client that will decode them or not, and a corrupt image is one broken
 * sticker rather than a way in.
 */

/** What the bytes turned out to be. */
export interface ImageHeader {
  format: 'png' | 'webp';
  width: number;
  height: number;
  /** Whether the format can carry transparency at all. */
  supportsAlpha: boolean;
}

/** Why an upload was refused, as a case the route turns into a message. */
export type ImageRefusal =
  | 'not_an_image'
  | 'unsupported_format'
  | 'too_large'
  | 'dimensions_too_large'
  | 'dimensions_too_small';

export interface ImageCheck {
  header?: ImageHeader;
  refusal?: ImageRefusal;
}

/** The limits a sticker or custom emoji has to fit inside. */
export const STICKER_LIMITS = {
  /** 512 KiB. Comfortably more than a well-made 512×512 sticker needs. */
  maxBytes: 512 * 1024,
  /** Telegram's sticker edge, and a sensible ceiling for a chat bubble. */
  maxEdge: 512,
  /** Below this it is not a sticker, it is a favicon somebody mis-picked. */
  minEdge: 32,
} as const;

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * Reads a PNG's IHDR.
 *
 * The signature is eight bytes, then a chunk header of length + type, then the
 * IHDR payload: width and height as big-endian 32-bit integers. The spec
 * requires IHDR to be the first chunk, so the offsets are fixed.
 */
function readPng(bytes: Buffer): ImageHeader | null {
  if (bytes.length < 24) return null;
  if (!bytes.subarray(0, 8).equals(PNG_MAGIC)) return null;
  if (bytes.subarray(12, 16).toString('ascii') !== 'IHDR') return null;
  return {
    format: 'png',
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    supportsAlpha: true,
  };
}

/**
 * Reads a WebP header, in all three of its shapes.
 *
 * A RIFF container whose fourcc is `WEBP`, then one of:
 *
 *   - `VP8 ` — lossy. Dimensions sit after a three-byte start code in the
 *     frame header, as 14-bit values.
 *   - `VP8L` — lossless. Width and height are 14-bit each, packed into the
 *     four bytes after the signature byte.
 *   - `VP8X` — extended, which is what an animated or alpha-carrying file
 *     uses. Dimensions are stored minus one, as 24-bit little-endian.
 *
 * All three are accepted for reading. Whether an *animated* one is allowed is
 * not this function's decision — see `isAnimated`, which the route uses to keep
 * the first release to static images.
 */
function readWebp(bytes: Buffer): ImageHeader | null {
  if (bytes.length < 30) return null;
  if (bytes.subarray(0, 4).toString('ascii') !== 'RIFF') return null;
  if (bytes.subarray(8, 12).toString('ascii') !== 'WEBP') return null;

  const chunk = bytes.subarray(12, 16).toString('ascii');

  if (chunk === 'VP8 ') {
    // 12 RIFF + 8 chunk header = 20, then 3 bytes of start code.
    if (bytes.length < 30) return null;
    if (bytes[23] !== 0x9d || bytes[24] !== 0x01 || bytes[25] !== 0x2a) return null;
    return {
      format: 'webp',
      width: bytes.readUInt16LE(26) & 0x3fff,
      height: bytes.readUInt16LE(28) & 0x3fff,
      // Lossy WebP without an ALPH chunk carries no transparency. Saying so
      // lets the route warn rather than silently flatten somebody's cut-out.
      supportsAlpha: false,
    };
  }

  if (chunk === 'VP8L') {
    if (bytes.length < 25) return null;
    if (bytes[20] !== 0x2f) return null;
    const packed = bytes.readUInt32LE(21);
    return {
      format: 'webp',
      width: (packed & 0x3fff) + 1,
      height: ((packed >> 14) & 0x3fff) + 1,
      supportsAlpha: true,
    };
  }

  if (chunk === 'VP8X') {
    if (bytes.length < 30) return null;
    const width = 1 + (bytes[24]! | (bytes[25]! << 8) | (bytes[26]! << 16));
    const height = 1 + (bytes[27]! | (bytes[28]! << 8) | (bytes[29]! << 16));
    // Bit 4 of the flags byte is the alpha flag.
    const supportsAlpha = (bytes[20]! & 0x10) !== 0;
    return { format: 'webp', width, height, supportsAlpha };
  }

  return null;
}

/**
 * Whether a WebP announces itself as animated.
 *
 * Bit 1 of the VP8X flags. The first release of packs is static images only, so
 * the route refuses these rather than storing something clients will render as
 * a still first frame and the owner will believe is moving.
 */
export function isAnimated(bytes: Buffer): boolean {
  if (bytes.length < 21) return false;
  if (bytes.subarray(0, 4).toString('ascii') !== 'RIFF') return false;
  if (bytes.subarray(8, 12).toString('ascii') !== 'WEBP') return false;
  if (bytes.subarray(12, 16).toString('ascii') !== 'VP8X') return false;
  return (bytes[20]! & 0x02) !== 0;
}

/** Reads the header of a PNG or a WebP, or says it is neither. */
export function readImageHeader(bytes: Buffer): ImageHeader | null {
  return readPng(bytes) ?? readWebp(bytes);
}

/**
 * Whether these bytes may be stored as a sticker.
 *
 * Every limit is checked here, on the server, whatever the client did before
 * uploading — the client's own crop and resize are a convenience for the person
 * using it, not a control.
 */
export function checkSticker(bytes: Buffer): ImageCheck {
  if (bytes.length > STICKER_LIMITS.maxBytes) return { refusal: 'too_large' };

  const header = readImageHeader(bytes);
  if (header === null) return { refusal: 'not_an_image' };
  if (isAnimated(bytes)) return { refusal: 'unsupported_format' };

  const edge = Math.max(header.width, header.height);
  if (edge > STICKER_LIMITS.maxEdge) return { refusal: 'dimensions_too_large' };
  if (Math.min(header.width, header.height) < STICKER_LIMITS.minEdge) {
    return { refusal: 'dimensions_too_small' };
  }

  return { header };
}
