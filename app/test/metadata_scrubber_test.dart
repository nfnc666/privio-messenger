import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
  group('a Word document', () {
    final original = fixture('document.docx');
    const type =
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

    test('the fixture really does carry someone in it', () {
      // Guards the test itself: a fixture that never had a name in it would
      // let a scrubber that does nothing pass.
      final text = asText(original);
      // Deflated, so the words are not readable in the raw bytes — the parts
      // are what prove it.
      final parts = ZipDecoder().decodeBytes(original);
      final core = asText(
        Uint8List.fromList(parts.findFile('docProps/core.xml')!.readBytes()!),
      );
      expect(core, contains('Marlene Baumgartner'));
      expect(core, contains('2026-02-11T09:14:00Z'));
      final app = asText(
        Uint8List.fromList(parts.findFile('docProps/app.xml')!.readBytes()!),
      );
      expect(app, contains('Kanzlei Baumgartner GmbH'));
      expect(text, isNotEmpty);
    });

    test('the author, the company and the timestamps are gone', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      expect(result.report.recognised, isTrue);

      final parts = ZipDecoder().decodeBytes(result.bytes);
      final core = asText(
        Uint8List.fromList(parts.findFile('docProps/core.xml')!.readBytes()!),
      );
      final app = asText(
        Uint8List.fromList(parts.findFile('docProps/app.xml')!.readBytes()!),
      );

      expect(core, isNot(contains('Marlene')));
      expect(core, isNot(contains('2026-02-11')));
      expect(core, isNot(contains('<cp:revision>')));
      expect(app, isNot(contains('Kanzlei')));
      expect(app, isNot(contains('Dr. Vogt')));
      expect(app, isNot(contains('TotalTime')));
    });

    test('the document itself is untouched', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      final before = ZipDecoder().decodeBytes(original);
      final after = ZipDecoder().decodeBytes(result.bytes);

      expect(
        after.findFile('word/document.xml')!.readBytes(),
        before.findFile('word/document.xml')!.readBytes(),
        reason: 'a scrubber that edits the text is not a scrubber',
      );
      expect(
        after.findFile('[Content_Types].xml')!.readBytes(),
        before.findFile('[Content_Types].xml')!.readBytes(),
      );
    });

    test('every part that was there is still there', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      final before = ZipDecoder().decodeBytes(original).files.map((f) => f.name);
      final after = ZipDecoder().decodeBytes(result.bytes).files.map((f) => f.name);
      expect(
        after.toList(),
        before.toList(),
        reason: 'a removed part leaves a relationship pointing at nothing, and '
            'a word processor is entitled to call that corrupt',
      );
    });

    test('the minute it was last worked on is gone from every entry', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      final stamps = ZipDecoder()
          .decodeBytes(result.bytes)
          .files
          .map((f) => f.lastModDateTime.year)
          .toSet();
      expect(stamps, {1980}, reason: 'one fixed instant, the same for everyone');
    });

    test('it says what it took out', () {
      final report = MetadataScrubber.scrub(original, declaredType: type).report;
      expect(report.removed, contains(startsWith('Author')));
      expect(report.removed, contains(startsWith('Company')));
      expect(report.changedAnything, isTrue);
    });

    test('scrubbing an already-clean document reports only the timestamps', () {
      final once = MetadataScrubber.scrub(original, declaredType: type);
      final twice = MetadataScrubber.scrub(once.bytes, declaredType: type);
      expect(twice.report.removed, ['File timestamps inside the document']);
    });
  });

  group('an OpenDocument file', () {
    final original = fixture('document.odt');
    const type = 'application/vnd.oasis.opendocument.text';

    test('the author and the editing history are gone', () {
      final before = asText(
        Uint8List.fromList(
          ZipDecoder().decodeBytes(original).findFile('meta.xml')!.readBytes()!,
        ),
      );
      expect(before, contains('Marlene Baumgartner'));
      expect(before, contains('PT8H34M'));

      final result = MetadataScrubber.scrub(original, declaredType: type);
      expect(result.report.recognised, isTrue);
      final after = asText(
        Uint8List.fromList(
          ZipDecoder().decodeBytes(result.bytes).findFile('meta.xml')!.readBytes()!,
        ),
      );
      expect(after, isNot(contains('Marlene')));
      expect(after, isNot(contains('PT8H34M')));
      expect(after, isNot(contains('LibreOffice')));
    });

    test('the mimetype entry stays first and stays stored', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      final files = ZipDecoder().decodeBytes(result.bytes).files;
      expect(files.first.name, 'mimetype');
      // Deflating it produces something that opens as a ZIP and not as a
      // document, which is a corruption a test would otherwise never see.
      expect(files.first.compression, CompressionType.none);
      expect(
        asText(Uint8List.fromList(files.first.readBytes()!)),
        'application/vnd.oasis.opendocument.text',
      );
    });

    test('the text is untouched', () {
      final result = MetadataScrubber.scrub(original, declaredType: type);
      expect(
        ZipDecoder().decodeBytes(result.bytes).findFile('content.xml')!.readBytes(),
        ZipDecoder().decodeBytes(original).findFile('content.xml')!.readBytes(),
      );
    });
  });

  group('a ZIP that is not a document', () {
    test('is left exactly as it came', () {
      final original = fixture('plain.zip');
      final result = MetadataScrubber.scrub(original, declaredType: 'application/zip');
      expect(
        result.report.recognised,
        isFalse,
        reason: 'rewriting an archive of unknown files is not its business',
      );
      expect(result.bytes, original);
    });

    test('so is something that only starts like one', () {
      final broken = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5]);
      final result = MetadataScrubber.scrub(broken, declaredType: 'application/zip');
      expect(result.report.recognised, isFalse);
      expect(result.bytes, broken);
    });
  });

  group('WebP', () {
    final original = fixture('photo_with_exif.webp');

    test('the fixture really does carry what we claim to remove', () {
      final text = latin1.decode(original, allowInvalid: true);
      expect(text, contains('EXIF'));
      expect(text, contains('SECRET-XMP-MARKER'));
      expect(MetadataScrubber.sniff(original), 'image/webp');
    });

    test('EXIF, XMP and the colour profile are gone', () {
      final result = MetadataScrubber.scrub(original);
      final text = latin1.decode(result.bytes, allowInvalid: true);

      expect(result.report.recognised, isTrue);
      expect(text, isNot(contains('SECRET-XMP-MARKER')));
      expect(text, isNot(contains('Privio Camera')));
      expect(text, isNot(contains('SERIAL-12345')));
      expect(result.report.removed, contains('EXIF (camera, GPS, timestamps)'));
      expect(result.report.removed, contains('XMP metadata'));
      expect(result.report.removed, contains('ICC colour profile'));
      expect(result.bytes.length, lessThan(original.length));
    });

    test('it is still a WebP, and still decodes to the same picture', () {
      final result = MetadataScrubber.scrub(original);

      expect(latin1.decode(result.bytes.sublist(0, 4)), 'RIFF');
      expect(latin1.decode(result.bytes.sublist(8, 12)), 'WEBP');

      // The RIFF length field has to match what is actually there, or every
      // decoder reads past the end.
      final declared = result.bytes[4] |
          (result.bytes[5] << 8) |
          (result.bytes[6] << 16) |
          (result.bytes[7] << 24);
      expect(declared, result.bytes.length - 8);

      final decoded = img.decodeWebP(result.bytes);
      expect(decoded, isNotNull, reason: 'a scrubber that breaks the picture is not a scrubber');
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
    });

    test('the VP8X flags stop announcing chunks that are no longer there', () {
      final result = MetadataScrubber.scrub(original);
      var offset = 12;
      int? flags;
      while (offset + 8 <= result.bytes.length) {
        final fourCc = latin1.decode(result.bytes.sublist(offset, offset + 4));
        final size = result.bytes[offset + 4] |
            (result.bytes[offset + 5] << 8) |
            (result.bytes[offset + 6] << 16) |
            (result.bytes[offset + 7] << 24);
        if (fourCc == 'VP8X') flags = result.bytes[offset + 8];
        offset += 8 + size + (size.isOdd ? 1 : 0);
      }

      expect(flags, isNotNull, reason: 'the fixture has an extended header');
      // A decoder told there is an ICC profile and handed a file without one is
      // a decoder looking at a malformed image.
      expect(flags! & 0x20, 0, reason: 'ICC');
      expect(flags & 0x08, 0, reason: 'EXIF');
      expect(flags & 0x04, 0, reason: 'XMP');
    });
  });

  group('GIF', () {
    final original = fixture('animation_with_metadata.gif');

    test('the fixture really does carry what we claim to remove', () {
      final text = latin1.decode(original, allowInvalid: true);
      expect(text, contains('SECRET-GIF-COMMENT'));
      expect(text, contains('SECRET-XMP-MARKER'));
      expect(text, contains('NETSCAPE2.0'));
      expect(MetadataScrubber.sniff(original), 'image/gif');
    });

    test('the comment and the XMP block are gone', () {
      final result = MetadataScrubber.scrub(original);
      final text = latin1.decode(result.bytes, allowInvalid: true);

      expect(result.report.recognised, isTrue);
      expect(text, isNot(contains('SECRET-GIF-COMMENT')));
      expect(text, isNot(contains('SECRET-XMP-MARKER')));
      expect(result.report.removed, contains('Embedded comment'));
      expect(result.report.removed, contains('Application metadata (XMP DataXMP)'));
    });

    test('the loop block survives, because dropping it changes the picture', () {
      final result = MetadataScrubber.scrub(original);
      final text = latin1.decode(result.bytes, allowInvalid: true);

      // An animation that looped forever and now plays once has been altered,
      // not cleaned.
      expect(text, contains('NETSCAPE2.0'));
    });

    test('it still decodes, and still has every frame', () {
      final before = img.decodeGif(original)!;
      final result = MetadataScrubber.scrub(original);
      final after = img.decodeGif(result.bytes);

      expect(after, isNotNull);
      expect(after!.frames.length, before.frames.length);
      expect(after.width, 32);
      expect(after.height, 24);
    });
  });

  group('a file that cannot be walked', () {
    test('is reported as not cleaned, not as having nothing to remove', () {
      // Half a walk leaves the metadata in the half that was never read. The
      // UI shows a warning for `recognised: false` and a tick for a clean
      // pass, so getting this backwards tells someone their file is safe.
      final gif = fixture('animation_with_metadata.gif');
      final truncated = Uint8List.fromList(gif.sublist(0, gif.length - 40));

      final result = MetadataScrubber.scrub(truncated);
      expect(result.report.recognised, isFalse);
      expect(result.report.removed, isEmpty);
      expect(result.bytes, truncated, reason: 'and nothing is silently rewritten');
    });

    test('the same for a WebP whose chunk table runs off the end', () {
      final webp = fixture('photo_with_exif.webp');
      final truncated = Uint8List.fromList(webp.sublist(0, 40));

      final result = MetadataScrubber.scrub(truncated);
      expect(result.report.recognised, isFalse);
      expect(result.bytes, truncated);
    });
  });

  group('what is still not cleaned', () {
    test('a PDF is passed through and says so', () {
      final pdf = Uint8List.fromList([
        ...'%PDF-1.7\n'.codeUnits,
        ...'/Author (someone) /Producer (a tool)'.codeUnits,
      ]);
      final result = MetadataScrubber.scrub(pdf);

      // Stripping a PDF safely needs a real parser. Passing it through with a
      // warning is worse than cleaning it and better than pretending.
      expect(result.report.recognised, isFalse);
      expect(result.report.mediaType, 'application/pdf');
      expect(result.bytes, pdf);
    });
  });

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
