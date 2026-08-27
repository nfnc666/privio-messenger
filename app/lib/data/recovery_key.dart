import 'dart:math';

import 'package:flutter/foundation.dart';

/// The one secret Privio cannot help you with.
///
/// A backup is sealed under a key derived from this, and nothing on the server
/// can open it. That is the point, and it is also the whole risk: lose this and
/// the backup is bytes forever. So it is 256 bits of entropy from a secure
/// generator, written in an alphabet chosen so it can be copied off a screen
/// onto paper without ambiguity.
@immutable
class RecoveryKey {
  const RecoveryKey(this.bytes);

  /// Crockford's base32, minus the letters that get misread by hand: no I, L,
  /// O or U. What is left cannot be confused with 0, 1 or each other.
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const int keyLength = 32;
  static const int groupSize = 4;

  final Uint8List bytes;

  static RecoveryKey generate() {
    final random = Random.secure();
    return RecoveryKey(
      Uint8List.fromList(List<int>.generate(keyLength, (_) => random.nextInt(256))),
    );
  }

  /// Groups of four, which is how people read numbers off paper.
  String get formatted {
    final buffer = StringBuffer();
    final encoded = _encode(bytes);
    for (var i = 0; i < encoded.length; i += groupSize) {
      if (i > 0) buffer.write('-');
      buffer.write(encoded.substring(i, min(i + groupSize, encoded.length)));
    }
    return buffer.toString();
  }

  /// Reads a key back from something a person typed.
  ///
  /// Deliberately forgiving about spaces, dashes and case, and about the four
  /// letters the alphabet leaves out — someone who writes O for 0 has not made
  /// a mistake worth punishing. Returns null on anything that is not a key.
  static RecoveryKey? parse(String input) {
    final normalised = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('U', 'V');

    final bits = <int>[];
    for (final rune in normalised.runes) {
      final index = alphabet.indexOf(String.fromCharCode(rune));
      if (index < 0) return null;
      for (var bit = 4; bit >= 0; bit--) {
        bits.add((index >> bit) & 1);
      }
    }
    if (bits.length < keyLength * 8) return null;

    final out = Uint8List(keyLength);
    for (var i = 0; i < keyLength * 8; i++) {
      if (bits[i] == 1) out[i ~/ 8] |= 1 << (7 - i % 8);
    }
    return RecoveryKey(out);
  }

  static String _encode(Uint8List input) {
    final buffer = StringBuffer();
    var accumulator = 0;
    var bits = 0;
    for (final byte in input) {
      accumulator = (accumulator << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        buffer.write(alphabet[(accumulator >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) buffer.write(alphabet[(accumulator << (5 - bits)) & 31]);
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is RecoveryKey && listEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}
