import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/crypto/safety_number.dart';
import 'package:privio/media/qr_scan.dart';
import 'package:qr/qr.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;
import 'safety_number_test.dart' show introduce;

/// Draws a QR code the way a phone screen would, so the decoder has a real
/// picture to read rather than a bitmap it was handed.
///
/// White quiet zone included: a QR with no margin is one that readers refuse,
/// and leaving it out would have made this test pass on a picture no camera
/// could ever decode.
Uint8List drawQr(String data, {int scale = 6, int quiet = 4}) {
  final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L);
  final matrix = QrImage(code);
  final size = (matrix.moduleCount + quiet * 2) * scale;
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  for (var y = 0; y < matrix.moduleCount; y++) {
    for (var x = 0; x < matrix.moduleCount; x++) {
      if (!matrix.isDark(y, x)) continue;
      img.fillRect(
        image,
        x1: (x + quiet) * scale,
        y1: (y + quiet) * scale,
        x2: (x + quiet) * scale + scale - 1,
        y2: (y + quiet) * scale + scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('reading a QR code out of a picture', () {
    test('what was drawn comes back', () async {
      const payload = 'privio-safety-number-round-trip';
      expect(await QrScan.read(drawQr(payload)), payload);
    });

    test('a picture with no QR code in it is null, not an error', () async {
      final blank = img.Image(width: 300, height: 300);
      img.fill(blank, color: img.ColorRgb8(120, 130, 140));
      expect(await QrScan.read(Uint8List.fromList(img.encodePng(blank))), isNull);
    });

    test('something that is not an image at all is null', () async {
      expect(await QrScan.read(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });

    test('a photograph-sized picture still decodes', () async {
      // The real case: a 12-megapixel shot of a phone screen. The reader
      // downscales first, and this is what says the downscale does not lose
      // the finder patterns.
      final small = img.decodePng(drawQr('privio', scale: 8))!;
      final blownUp = img.copyResize(small, width: 2400, interpolation: img.Interpolation.cubic);
      expect(QrScan.fromImage(blownUp), 'privio');
    });
  });

  group('a scanned safety number', () {
    late FakeKeyServer server;
    late TestDevice alice;
    late TestDevice bob;
    late TestDevice mallory;

    setUp(() async {
      server = FakeKeyServer();
      alice = TestDevice('account-alice', 'device-alice-1', 1);
      bob = TestDevice('account-bob', 'device-bob-1', 1);
      mallory = TestDevice('account-mallory', 'device-mallory-1', 1);
      await alice.boot(server);
      await bob.boot(server);
      await mallory.boot(server);
      await introduce(server, alice, bob);
      await introduce(server, bob, alice);
      await introduce(server, alice, mallory);
      await introduce(server, mallory, alice);
    });

    Future<SafetyNumber> number(TestDevice me, TestDevice them) async {
      final numbers = await me.crypto.safetyNumbers(
        localAccountId: me.accountId,
        remoteAccountId: them.accountId,
      );
      return numbers.numbers.single;
    }

    test('there is a code to show at all', () async {
      expect((await number(alice, bob)).scannable, isNotNull);
    });

    test("Alice scanning Bob's code matches", () async {
      final onAlice = await number(alice, bob);
      final onBob = await number(bob, alice);

      expect(onAlice.matchesScan(onBob.scannable!), isTrue);
      expect(onBob.matchesScan(onAlice.scannable!), isTrue);
    });

    test('a code from a different conversation does not match', () async {
      // The attack this check exists for: a code replayed from somewhere else.
      // The comparison is two-sided, so it fails.
      final aliceAndBob = await number(alice, bob);
      final aliceAndMallory = await number(alice, mallory);

      expect(aliceAndBob.matchesScan(aliceAndMallory.scannable!), isFalse);
    });

    test('scanning your own code back does not match', () async {
      // Holding the phone up to a mirror must not verify anybody: my own code
      // has my halves the wrong way round for my own comparison.
      final onAlice = await number(alice, bob);
      expect(onAlice.matchesScan(onAlice.scannable!), isFalse);
    });

    test('a photograph of the code verifies, end to end', () async {
      // The whole path: the code one side shows, drawn as a picture, decoded
      // by the reader, compared by the other side.
      final onAlice = await number(alice, bob);
      final onBob = await number(bob, alice);

      final scanned = await QrScan.read(drawQr(onBob.scannable!));

      expect(scanned, isNotNull);
      expect(onAlice.matchesScan(scanned!), isTrue);
    });

    test('nonsense in the picture is a mismatch, never an error', () async {
      final onAlice = await number(alice, bob);
      expect(onAlice.matchesScan('not base64 at all !!!'), isFalse);
      expect(onAlice.matchesScan(''), isFalse);
      expect(onAlice.matchesScan('AAECAwQ='), isFalse);
    });

    test('a number with no fingerprint never claims a match', () async {
      final bare = SafetyNumber(deviceIndex: 1, digits: '0' * 60, identityKey: 'k');
      expect(bare.scannable, isNull);
      expect(bare.matchesScan('anything'), isFalse);
    });
  });
}
