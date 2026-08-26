import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/media/metadata_scrubber.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

String asText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// Builds a box: 4-byte size, 4-byte type, payload.
Uint8List box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    (size >> 24) & 0xFF, (size >> 16) & 0xFF, (size >> 8) & 0xFF, size & 0xFF,
    ...type.codeUnits,
    ...payload,
  ]);
}

int boxSize(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];

void main() {
  group('JPEG', () {
    test('strips GPS, camera model and serial number from a real photo', () {
      final original = fixture('photo_with_exif.jpg');
      // The fixture is a phone-shaped JPEG: it really does carry all of this.
      expect(asText(original), contains('ACME Ultra 12 Pro'));
      expect(asText(original), contains('SN-4711-XYZ'));

      final result = MetadataScrubber.scrub(original);

      expect(asText(result.bytes), isNot(contains('ACME')));
      expect(asText(result.bytes), isNot(contains('SN-4711-XYZ')));
      expect(asText(result.bytes), isNot(contains('2026:03:04')));
      expect(result.report.recognised, isTrue);
      expect(result.report.removed, contains('EXIF / XMP (camera, GPS, timestamps)'));
      expect(result.report.scrubbedBytes, lessThan(result.report.originalBytes));
    });

    test('leaves the image itself intact and decodable', () {
      final result = MetadataScrubber.scrub(fixture('photo_with_exif.jpg'));

      expect(result.bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'still starts with SOI');
      expect(
        result.bytes.sublist(result.bytes.length - 2),
        [0xFF, 0xD9],
        reason: 'still ends with EOI',
      );
      // The pixels are passed through, never re-encoded, so nothing degrades.
      final scan = result.bytes.indexOf(0xDA);
      expect(scan, greaterThan(0), reason: 'the scan data survived');
    });

    test('scrubbing twice changes nothing the second time', () {
      final once = MetadataScrubber.scrub(fixture('photo_with_exif.jpg'));
      final twice = MetadataScrubber.scrub(once.bytes);

      expect(twice.bytes, once.bytes);
      expect(twice.report.removed, isEmpty);
    });
  });

  group('PNG', () {
    test('strips text chunks that carry a name and a location', () {
      final original = fixture('image_with_text.png');
      expect(asText(original), contains('Jane Doe'));
      expect(asText(original), contains('52.52 N'));

      final result = MetadataScrubber.scrub(original);

      expect(asText(result.bytes), isNot(contains('Jane Doe')));
      expect(asText(result.bytes), isNot(contains('52.52')));
      expect(asText(result.bytes), isNot(contains('xmpmeta')));
      expect(result.report.removed, isNotEmpty);
    });

    test('keeps the signature and the pixel chunks', () {
      final result = MetadataScrubber.scrub(fixture('image_with_text.png'));

      expect(
        result.bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
      expect(asText(result.bytes), contains('IHDR'));
      expect(asText(result.bytes), contains('IDAT'));
      expect(asText(result.bytes), contains('IEND'));
    });
  });

  group('MP4', () {
    /// A minimal file shaped like a phone recording: a udta box holding GPS and
    /// device tags, and an mvhd with real timestamps.
    Uint8List videoWithMetadata() {
      final mvhd = box('mvhd', [
        0, 0, 0, 0, // version + flags
        0xD4, 0xB2, 0x1F, 0x00, // creation time
        0xD4, 0xB2, 0x1F, 0x40, // modification time
        0, 0, 0x03, 0xE8, // timescale
        0, 0, 0x27, 0x10, // duration
      ]);
      final udta = box('udta', [
        ...box('©xyz', utf8.encode('+52.5200+013.4050/')),
        ...box('©mak', utf8.encode('ACME Phones')),
        ...box('©mod', utf8.encode('ACME Ultra 12 Pro')),
      ]);
      final moov = box('moov', [...mvhd, ...udta]);
      final ftyp = box('ftyp', utf8.encode('isom') + [0, 0, 0, 1] + utf8.encode('isom'));
      final mdat = box('mdat', List<int>.filled(64, 0x42));
      return Uint8List.fromList([...ftyp, ...moov, ...mdat]);
    }

    test('is recognised from its magic bytes, not its name', () {
      expect(MetadataScrubber.sniff(videoWithMetadata()), 'video/mp4');
    });

    test('strips the location and device tags', () {
      final original = videoWithMetadata();
      expect(asText(original), contains('+52.5200+013.4050'));
      expect(asText(original), contains('ACME Ultra 12 Pro'));

      final result = MetadataScrubber.scrub(original);

      expect(asText(result.bytes), isNot(contains('52.5200')));
      expect(asText(result.bytes), isNot(contains('ACME')));
      expect(
        result.report.removed,
        contains('User data (GPS location, device make and model)'),
      );
    });

    test('blanks the recording timestamps', () {
      final result = MetadataScrubber.scrub(videoWithMetadata());
      final mvhdAt = asText(result.bytes).indexOf('mvhd') - 4;

      // creation and modification times, right after version and flags.
      final times = result.bytes.sublist(mvhdAt + 12, mvhdAt + 20);
      expect(times, everyElement(0));
      expect(result.report.removed, contains('Recording timestamps'));
    });

    test('rewrites the container size so the file stays valid', () {
      final result = MetadataScrubber.scrub(videoWithMetadata());
      final moovAt = asText(result.bytes).indexOf('moov') - 4;
      final declared = boxSize(result.bytes, moovAt);

      // A wrong size here makes the file unplayable, so it is not enough to
      // just drop the box.
      expect(declared, lessThan(boxSize(videoWithMetadata(), 24)));
      expect(moovAt + declared, lessThanOrEqualTo(result.bytes.length));
    });

    test('leaves the media payload untouched', () {
      final result = MetadataScrubber.scrub(videoWithMetadata());
      final mdatAt = asText(result.bytes).indexOf('mdat') - 4;
      expect(result.bytes.sublist(mdatAt + 8, mdatAt + 8 + 64), everyElement(0x42));
    });
  });

  group('unknown formats', () {
    test('are passed through and reported as not cleaned', () {
      final bytes = Uint8List.fromList(utf8.encode('some proprietary format'));
      final result = MetadataScrubber.scrub(bytes);

      expect(result.bytes, bytes, reason: 'never silently corrupt a file we do not understand');
      expect(result.report.recognised, isFalse);
      expect(result.report.removed, isEmpty);
    });

    test('a truncated file does not throw', () {
      final broken = fixture('photo_with_exif.jpg').sublist(0, 30);
      expect(() => MetadataScrubber.scrub(broken), returnsNormally);
    });

    test('an empty file does not throw', () {
      expect(() => MetadataScrubber.scrub(Uint8List(0)), returnsNormally);
    });
  });
}
