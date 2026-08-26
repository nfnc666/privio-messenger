import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/media/attachment.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

String asText(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

void main() {
  group('sealing a file', () {
    test('strips the metadata before anything else happens', () async {
      final photo = fixture('photo_with_exif.jpg');
      expect(asText(photo), contains('ACME Ultra 12 Pro'));

      final sealed = await AttachmentCipher.seal(photo);
      final opened = await AttachmentCipher.open(sealed.bytes, sealed.key);

      // What the recipient gets has no camera, no GPS, no serial number —
      // encryption alone would have delivered all of it intact.
      expect(asText(opened), isNot(contains('ACME')));
      expect(asText(opened), isNot(contains('SN-4711-XYZ')));
      expect(sealed.report.removed, isNotEmpty);
    });

    test('what is uploaded reveals nothing about the file', () async {
      final photo = fixture('photo_with_exif.jpg');
      final sealed = await AttachmentCipher.seal(photo);

      expect(asText(sealed.bytes), isNot(contains('ACME')));
      expect(asText(sealed.bytes), isNot(contains('JFIF')));
      expect(
        sealed.bytes.sublist(0, 4),
        isNot([0xFF, 0xD8, 0xFF, 0xE0]),
        reason: 'the upload must not even look like a JPEG',
      );
    });

    test('the file size is padded, so length is not a fingerprint', () async {
      // Two clearly different files must not be distinguishable by upload size.
      final small = await AttachmentCipher.seal(Uint8List.fromList(List.filled(40, 1)));
      final larger = await AttachmentCipher.seal(Uint8List.fromList(List.filled(200, 2)));

      expect(small.bytes.length, larger.bytes.length);
    });

    test('every file gets its own key', () async {
      final first = await AttachmentCipher.seal(fixture('image_with_text.png'));
      final second = await AttachmentCipher.seal(fixture('image_with_text.png'));

      expect(first.key, isNot(second.key));
      expect(first.bytes, isNot(second.bytes), reason: 'same file, different ciphertext');
      expect(first.key.length, 32);
    });

    test('the key from one file does not open another', () async {
      final first = await AttachmentCipher.seal(fixture('image_with_text.png'));
      final second = await AttachmentCipher.seal(fixture('photo_with_exif.jpg'));

      await expectLater(
        AttachmentCipher.open(second.bytes, first.key),
        throwsA(isA<Exception>()),
      );
    });

    test('a byte changed in transit makes the file fail, not look genuine', () async {
      final sealed = await AttachmentCipher.seal(fixture('image_with_text.png'));
      final tampered = Uint8List.fromList(sealed.bytes);
      tampered[tampered.length ~/ 2] ^= 0xFF;

      await expectLater(
        AttachmentCipher.open(tampered, sealed.key),
        throwsA(isA<Exception>()),
      );
    });

    test('a file we cannot clean is still sent, and reported honestly', () async {
      final unknown = Uint8List.fromList(utf8.encode('proprietary payload'));
      final sealed = await AttachmentCipher.seal(unknown);

      expect(sealed.report.recognised, isFalse);
      expect(await AttachmentCipher.open(sealed.bytes, sealed.key), unknown);
    });

    test('truncated ciphertext is rejected rather than half-read', () async {
      final sealed = await AttachmentCipher.seal(fixture('image_with_text.png'));
      await expectLater(
        AttachmentCipher.open(sealed.bytes.sublist(0, 10), sealed.key),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('message payload', () {
    test('an attachment pointer survives a round trip', () {
      const payload = MessagePayload.media(
        mediaId: 'media-1',
        mediaKey: 'a2V5',
        mediaType: 'image/jpeg',
        byteSize: 1234,
        fileName: 'urlaub.jpg',
        body: 'Schau mal',
      );

      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isMedia, isTrue);
      expect(decoded.mediaId, 'media-1');
      expect(decoded.mediaKey, 'a2V5');
      expect(decoded.fileName, 'urlaub.jpg');
      expect(decoded.body, 'Schau mal');
    });

    test('the file name travels inside the encrypted payload, never beside it', () {
      const payload = MessagePayload.media(
        mediaId: 'media-1',
        mediaKey: 'a2V5',
        mediaType: 'application/pdf',
        byteSize: 10,
        fileName: 'reisepass_scan.pdf',
      );

      // The upload itself carries only bytes; this is the only place the name
      // exists, and it is sealed with the message.
      expect(payload.encode(), contains('reisepass_scan.pdf'));
      expect(MessagePayload.decode(payload.encode()).fileName, 'reisepass_scan.pdf');
    });

    test('plain text round trips', () {
      final decoded = MessagePayload.decode(const MessagePayload.text('hallo').encode());
      expect(decoded.isMedia, isFalse);
      expect(decoded.body, 'hallo');
    });

    test('a message that is not our format is read as plain text', () {
      // A build predating this format, or anything unexpected.
      expect(MessagePayload.decode('just a sentence').body, 'just a sentence');
      expect(MessagePayload.decode('{"unrelated":true}').body, '{"unrelated":true}');
    });
  });
}
