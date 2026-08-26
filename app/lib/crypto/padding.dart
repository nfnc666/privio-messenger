import 'dart:typed_data';

/// Hides how long a message is.
///
/// Ciphertext length tracks plaintext length, and the server sees every
/// ciphertext. Unpadded, that leaks a lot: a one-word "yes" is distinguishable
/// from a paragraph, a shared address from a link, and a repeated exchange of
/// fixed-size messages is a fingerprint on its own.
///
/// So every payload is padded up to a bucket before it is sealed. Bucket sizes
/// double, which keeps the overhead bounded (never more than 2x, on average far
/// less) while collapsing the range of observable sizes to a handful of values.
///
/// The scheme is ISO/IEC 7816-4: a single 0x80 byte marks the end of the real
/// content, then zeros to the bucket boundary. It is unambiguous — the padding
/// can never be mistaken for content, whatever the content is.
abstract final class MessagePadding {
  /// The smallest bucket. Chosen so ordinary short messages — the great
  /// majority — all land in it and are indistinguishable from each other.
  static const int minimumBucket = 256;

  /// Above this, doubling would waste more than it hides, so padding steps in
  /// fixed blocks instead.
  static const int maximumBucket = 16384;

  static int bucketFor(int length) {
    // +1 because the 0x80 marker must fit inside the bucket too.
    final needed = length + 1;
    if (needed > maximumBucket) {
      final blocks = (needed / maximumBucket).ceil();
      return blocks * maximumBucket;
    }
    var bucket = minimumBucket;
    while (bucket < needed) {
      bucket *= 2;
    }
    return bucket;
  }

  static Uint8List pad(List<int> plaintext) {
    final bucket = bucketFor(plaintext.length);
    final padded = Uint8List(bucket)..setRange(0, plaintext.length, plaintext);
    padded[plaintext.length] = 0x80;
    // The rest is already zero.
    return padded;
  }

  /// Recovers the content, or throws when the padding is not well formed —
  /// which means the bytes were not produced by [pad] and should not be trusted.
  static Uint8List unpad(List<int> padded) {
    for (var i = padded.length - 1; i >= 0; i--) {
      final byte = padded[i];
      if (byte == 0x00) continue;
      if (byte == 0x80) return Uint8List.fromList(padded.sublist(0, i));
      break;
    }
    throw const FormatException('Malformed padding');
  }
}
