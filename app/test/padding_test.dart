import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/crypto/padding.dart';

void main() {
  test('a round trip returns exactly what went in', () {
    for (final text in ['', 'ok', 'Treffen um 19 Uhr', 'x' * 500, 'ü' * 3000]) {
      final bytes = utf8.encode(text);
      expect(utf8.decode(MessagePadding.unpad(MessagePadding.pad(bytes))), text);
    }
  });

  test('short messages are all the same size on the wire', () {
    final sizes = {
      for (final text in ['ja', 'nein', 'Bin unterwegs', 'Ich komme etwas später, warte nicht'])
        MessagePadding.pad(utf8.encode(text)).length,
    };

    expect(sizes, {MessagePadding.minimumBucket},
        reason: 'a yes and a sentence must not be distinguishable by length',);
  });

  test('sizes collapse into a handful of buckets', () {
    final observed = {
      for (var length = 0; length < 4000; length += 7)
        MessagePadding.pad(List<int>.filled(length, 0x41)).length,
    };

    expect(observed, {256, 512, 1024, 2048, 4096},
        reason: 'the server should see a few sizes, not a continuum',);
  });

  test('padding never costs more than double', () {
    for (var length = 1; length < 60000; length += 137) {
      final padded = MessagePadding.pad(List<int>.filled(length, 0x41)).length;
      expect(padded, greaterThan(length));
      expect(padded, lessThanOrEqualTo(length * 2 + MessagePadding.minimumBucket));
    }
  });

  test('large payloads step in fixed blocks rather than doubling', () {
    final big = MessagePadding.pad(List<int>.filled(20000, 0x41)).length;
    expect(big, MessagePadding.maximumBucket * 2);
  });

  test('content that looks like padding is still recovered', () {
    // A message whose last bytes are 0x80 and 0x00 must not confuse the reader.
    final tricky = [0x41, 0x80, 0x00, 0x00, 0x80];
    expect(MessagePadding.unpad(MessagePadding.pad(tricky)), tricky);
  });

  test('bytes that were never padded are rejected', () {
    expect(() => MessagePadding.unpad(const [0x41, 0x42, 0x43]), throwsFormatException);
    expect(() => MessagePadding.unpad(const []), throwsFormatException);
    expect(() => MessagePadding.unpad(const [0x00, 0x00]), throwsFormatException);
  });
}
