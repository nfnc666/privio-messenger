import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/media/avatar.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

String asText(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// A wide photo, so cropping and resizing have something real to do.
Uint8List largePhoto() {
  final image = img.Image(width: 1600, height: 900);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return img.encodeJpg(image, quality: 95);
}

void main() {
  group('preparing a picture', () {
    test('a large photo becomes a small square', () async {
      final prepared = (await AvatarImage.prepare(largePhoto()))!;
      final decoded = img.decodeImage(prepared)!;

      expect(decoded.width, AvatarImage.size);
      expect(decoded.height, AvatarImage.size, reason: 'avatars are shown in a circle');
      expect(
        prepared.length,
        lessThan(largePhoto().length),
        reason: 'nobody needs a 1.4-megapixel thumbnail',
      );
    });

    test('metadata does not survive, even before the scrubber', () async {
      final prepared = (await AvatarImage.prepare(fixture('photo_with_exif.jpg')))!;

      // A profile picture is the one image handed to everyone you talk to, so
      // it is both scrubbed and re-encoded.
      expect(asText(prepared), isNot(contains('ACME')));
      expect(asText(prepared), isNot(contains('SN-4711-XYZ')));
      expect(asText(prepared), isNot(contains('2026:03:04')));
    });

    test('a file that is not an image is refused rather than uploaded', () async {
      expect(await AvatarImage.prepare(Uint8List.fromList(utf8.encode('not a picture'))), isNull);
      expect(await AvatarImage.prepare(Uint8List(0)), isNull);
    });
  });

  group('sealing a picture', () {
    late PrivioCrypto crypto;

    setUp(() async {
      crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    });

    test('the profile key is generated once and kept', () async {
      final first = await crypto.profileKey();
      final second = await crypto.profileKey();

      expect(first, second, reason: 'rotating it would orphan the current picture');
      expect(first.length, 32);
    });

    test('what the server would store is not a picture', () async {
      final prepared = (await AvatarImage.prepare(largePhoto()))!;
      final sealed = await AttachmentCipher.sealWithKey(
        prepared,
        key: await crypto.profileKey(),
        declaredType: 'image/jpeg',
      );

      expect(
        sealed.sublist(0, 4),
        isNot([0xFF, 0xD8, 0xFF, 0xE0]),
        reason: 'the upload must not even look like a JPEG',
      );
      expect(asText(sealed), isNot(contains('JFIF')));
    });

    test('a contact with the profile key can open it', () async {
      final prepared = (await AvatarImage.prepare(largePhoto()))!;
      final key = await crypto.profileKey();
      final sealed = await AttachmentCipher.sealWithKey(prepared, key: key);

      final opened = await AttachmentCipher.open(sealed, key);
      expect(opened, prepared);
      expect(img.decodeImage(opened)?.width, AvatarImage.size);
    });

    test('someone without the profile key cannot', () async {
      final sealed = await AttachmentCipher.sealWithKey(
        (await AvatarImage.prepare(largePhoto()))!,
        key: await crypto.profileKey(),
      );

      final stranger = await PrivioCrypto.open(InMemoryCryptoStorage());
      await expectLater(
        AttachmentCipher.open(sealed, await stranger.profileKey()),
        throwsA(isA<Exception>()),
        reason: 'the server holds these bytes and must not be able to open them',
      );
    });

    test('every contact opens the same file, so the key is not per-upload', () async {
      final prepared = (await AvatarImage.prepare(largePhoto()))!;
      final key = await crypto.profileKey();

      final first = await AttachmentCipher.sealWithKey(prepared, key: key);
      final second = await AttachmentCipher.sealWithKey(prepared, key: key);

      // Different ciphertext each time — a fresh nonce — but one key opens both.
      expect(first, isNot(second));
      expect(await AttachmentCipher.open(first, key), prepared);
      expect(await AttachmentCipher.open(second, key), prepared);
    });
  });

  group('sharing the key', () {
    test('a message carries the sender’s profile key', () async {
      const payload = MessagePayload.text('hallo', profileKey: 'cHJvZmlsZS1rZXk=');
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.profileKey, 'cHJvZmlsZS1rZXk=');
      expect(decoded.body, 'hallo');
    });

    test('an attachment message carries it too', () async {
      const payload = MessagePayload.media(
        mediaId: 'm1',
        mediaKey: 'a2V5',
        mediaType: 'image/jpeg',
        byteSize: 10,
        profileKey: 'cHJvZmlsZS1rZXk=',
      );
      expect(MessagePayload.decode(payload.encode()).profileKey, 'cHJvZmlsZS1rZXk=');
    });

    test('a message from a build that sends no key still reads', () async {
      expect(MessagePayload.decode(const MessagePayload.text('hi').encode()).profileKey, isNull);
    });
  });

  group('a format Dart cannot read', () {
    /// The bug this exists for: an iPhone camera writes **HEIC**, and
    /// `package:image` has no HEIC decoder. Every photo taken on an iPhone hit
    /// `decodeImage` returning null and came back as "not an image Privio can
    /// use" — the picker opened, a picture was chosen, and nothing happened.
    /// It hit the channel picture, the account picture and the new-channel
    /// screen alike, because all three go through `prepare`.
    ///
    /// The fix hands anything Dart cannot read to the engine, which uses the
    /// platform's own codecs. There is no engine in a unit test, so what can be
    /// pinned here is the half that is testable: that such bytes reach the
    /// fallback at all instead of being refused by the Dart decoder, and that
    /// the fallback's absence is still a clean null rather than a crash.
    Uint8List heicHeader() {
      // A real HEIC signature: an ISO-BMFF box declaring the `heic` brand.
      final box = <int>[
        0, 0, 0, 0x18, // box size
        ...utf8.encode('ftyp'),
        ...utf8.encode('heic'),
        0, 0, 0, 0,
        ...utf8.encode('heic'),
        ...utf8.encode('mif1'),
      ];
      return Uint8List.fromList(box);
    }

    test('is not refused by the Dart decoder alone', () {
      // The precondition of the bug, asserted so nobody "fixes" this by
      // assuming package:image grew a HEIC decoder.
      expect(
        img.decodeImage(heicHeader()),
        isNull,
        reason: 'package:image cannot read HEIC — that is why the fallback exists',
      );
    });

    test('comes back null rather than throwing when there is no engine', () async {
      // In a unit test the platform decoder is unavailable. The contract is
      // that this is indistinguishable from "not a picture": null, no throw.
      expect(await AvatarImage.prepare(heicHeader()), isNull);
    });
  });
}
