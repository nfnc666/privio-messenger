import 'dart:typed_data';

import 'package:archive/archive.dart';

/// What a file said about itself before Privio stripped it.
class ScrubReport {
  const ScrubReport({
    required this.mediaType,
    required this.originalBytes,
    required this.scrubbedBytes,
    required this.removed,
    required this.recognised,
  });

  final String mediaType;
  final int originalBytes;
  final int scrubbedBytes;

  /// Human-readable names of what was dropped, for the "what was removed" sheet.
  final List<String> removed;

  /// False when the format is not one Privio knows how to strip. The file is
  /// still sent — encrypted — but the user is told it could not be cleaned.
  final bool recognised;

  bool get changedAnything => removed.isNotEmpty;
}

class ScrubResult {
  const ScrubResult(this.bytes, this.report);

  final Uint8List bytes;
  final ScrubReport report;
}

/// Removes identifying metadata from a file before it is encrypted and sent.
///
/// A photo straight from a phone carries GPS coordinates, the device make and
/// model, serial numbers and a capture timestamp. End-to-end encryption does not
/// help with any of that: the recipient decrypts the file and gets all of it.
/// So Privio strips it on the way out, always, with no setting to forget.
///
/// This is parsing, not cryptography — container structure only. The pixel data
/// is passed through untouched, so nothing is re-encoded and nothing degrades.
abstract final class MetadataScrubber {
  static ScrubResult scrub(Uint8List bytes, {String? declaredType}) {
    final type = sniff(bytes) ?? declaredType ?? 'application/octet-stream';
    return switch (type) {
      'image/jpeg' => _scrubJpeg(bytes),
      'image/png' => _scrubPng(bytes),
      'image/webp' => _scrubWebp(bytes),
      'image/gif' => _scrubGif(bytes),
      'video/mp4' || 'video/quicktime' => _scrubMp4(bytes, type),
      // Everything else may still be a document: Office and OpenDocument files
      // are ZIP containers, and nothing about the outside of one says which.
      _ => _looksLikeZip(bytes) ? _scrubZipDocument(bytes, type) : _unrecognised(bytes, type),
    };
  }

  /// Identifies a file by its magic bytes rather than its name, because the name
  /// is attacker-controlled and often just wrong.
  static String? sniff(Uint8List bytes) {
    bool startsWith(List<int> magic, {int at = 0}) {
      if (bytes.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
    if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], at: 8)) {
      return 'image/webp';
    }
    if (startsWith(const [0x66, 0x74, 0x79, 0x70], at: 4)) {
      // 'ftyp' at offset 4: an ISO base media file. The brand says which.
      final brand = String.fromCharCodes(bytes.sublist(8, 12.clamp(0, bytes.length)));
      return brand.startsWith('qt') ? 'video/quicktime' : 'video/mp4';
    }
    if (startsWith(const [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
    return null;
  }

  // --- WebP -----------------------------------------------------------------

  /// RIFF chunks that carry provenance rather than picture.
  ///
  /// `ICCP` is a colour profile and goes for the same reason JPEG's APP2 does:
  /// it is chosen by the device that wrote the file, which makes it a
  /// fingerprint of that device. The picture decodes without it.
  static const Map<String, String> _webpMetadataChunks = {
    'EXIF': 'EXIF (camera, GPS, timestamps)',
    'XMP ': 'XMP metadata',
    'ICCP': 'ICC colour profile',
  };

  /// Bits in the VP8X flags byte that announce those chunks.
  ///
  /// Clearing them matters: a decoder told there is an ICC profile and handed
  /// a file without one is a decoder looking at a malformed image. Removing
  /// the chunk and leaving the flag is how a scrubber breaks a picture.
  static const int _vp8xIccFlag = 0x20;
  static const int _vp8xExifFlag = 0x08;
  static const int _vp8xXmpFlag = 0x04;

  static ScrubResult _scrubWebp(Uint8List bytes) {
    final removed = <String>[];
    final kept = BytesBuilder();
    var offset = 12; // past 'RIFF' + size + 'WEBP'
    var dropped = 0;
    int? vp8xAt;

    while (offset + 8 <= bytes.length) {
      final fourCc = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bytes[offset + 4] |
          (bytes[offset + 5] << 8) |
          (bytes[offset + 6] << 16) |
          (bytes[offset + 7] << 24);
      // Chunks are padded to an even length; the pad byte is not counted.
      final end = offset + 8 + size + (size.isOdd ? 1 : 0);
      // A chunk running past the end means the rest was never read, so any
      // metadata in it survives. Reporting "nothing to remove" for a file that
      // could not be walked is the one answer worse than not cleaning it.
      if (size < 0 || end > bytes.length) return _unrecognised(bytes, 'image/webp');

      final label = _webpMetadataChunks[fourCc];
      if (label != null) {
        if (!removed.contains(label)) removed.add(label);
        dropped |= switch (fourCc) {
          'ICCP' => _vp8xIccFlag,
          'EXIF' => _vp8xExifFlag,
          _ => _vp8xXmpFlag,
        };
      } else {
        final chunk = Uint8List.fromList(bytes.sublist(offset, end));
        // VP8X announces what the file contains. It is written before the
        // chunks it describes, so the flags are cleared after the walk.
        if (fourCc == 'VP8X') vp8xAt = kept.length;
        kept.add(chunk);
      }
      offset = end;
    }
    final body = kept.toBytes();
    if (vp8xAt != null && dropped != 0) {
      // The flags byte is the first of the VP8X payload.
      body[vp8xAt + 8] &= ~dropped & 0xFF;
    }

    final out = BytesBuilder()
      ..add(bytes.sublist(0, 4))
      ..add(_le32(body.length + 4))
      ..add(bytes.sublist(8, 12))
      ..add(body);
    final scrubbed = out.toBytes();

    return ScrubResult(
      scrubbed,
      ScrubReport(
        mediaType: 'image/webp',
        originalBytes: bytes.length,
        scrubbedBytes: scrubbed.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  static Uint8List _le32(int value) => Uint8List.fromList([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);

  // --- GIF ------------------------------------------------------------------

  /// Application extensions that are machinery, not provenance.
  ///
  /// NETSCAPE2.0 carries the loop count. Dropping it turns an animation that
  /// loops forever into one that plays once, which is a visible change to the
  /// picture rather than a removal of information about it.
  static const List<String> _gifKeptApplications = ['NETSCAPE2.0', 'ANIMEXTS1.0'];

  static ScrubResult _scrubGif(Uint8List bytes) {
    final removed = <String>[];
    final out = BytesBuilder();

    // Header (6) + logical screen descriptor (7).
    if (bytes.length < 13) return _unrecognised(bytes, 'image/gif');
    out.add(bytes.sublist(0, 13));
    var offset = 13;

    // The global colour table, if the descriptor says there is one.
    final packed = bytes[10];
    if (packed & 0x80 != 0) {
      final size = 3 * (1 << ((packed & 0x07) + 1));
      if (offset + size > bytes.length) return _unrecognised(bytes, 'image/gif');
      out.add(bytes.sublist(offset, offset + size));
      offset += size;
    }

    while (offset < bytes.length) {
      final block = bytes[offset];

      if (block == 0x3B) {
        // Trailer. Anything after it is not part of the file.
        out.add(Uint8List.fromList(const [0x3B]));
        offset = bytes.length;
        break;
      }

      if (block == 0x21) {
        if (offset + 2 > bytes.length) return _unrecognised(bytes, 'image/gif');
        final label = bytes[offset + 1];
        final start = offset;
        var cursor = offset + 2;

        // An application extension names itself in an 11-byte block first.
        String? application;
        if (label == 0xFF && cursor < bytes.length && bytes[cursor] == 11) {
          if (cursor + 12 > bytes.length) return _unrecognised(bytes, 'image/gif');
          application = String.fromCharCodes(bytes.sublist(cursor + 1, cursor + 12));
        }

        cursor = _skipSubBlocks(bytes, cursor);
        if (cursor < 0) return _unrecognised(bytes, 'image/gif');

        final drop = switch (label) {
          0xFE => 'Embedded comment',
          0x01 => 'Plain-text extension',
          0xFF when application != null && !_gifKeptApplications.contains(application) =>
            'Application metadata ($application)',
          _ => null,
        };
        if (drop != null) {
          if (!removed.contains(drop)) removed.add(drop);
        } else {
          out.add(bytes.sublist(start, cursor));
        }
        offset = cursor;
        continue;
      }

      if (block == 0x2C) {
        // Image descriptor: 10 bytes, an optional local colour table, then the
        // LZW-coded data as sub-blocks. All picture; all kept.
        if (offset + 10 > bytes.length) return _unrecognised(bytes, 'image/gif');
        var cursor = offset + 10;
        final local = bytes[offset + 9];
        if (local & 0x80 != 0) cursor += 3 * (1 << ((local & 0x07) + 1));
        if (cursor + 1 > bytes.length) return _unrecognised(bytes, 'image/gif');
        cursor += 1; // LZW minimum code size
        cursor = _skipSubBlocks(bytes, cursor);
        if (cursor < 0) return _unrecognised(bytes, 'image/gif');
        out.add(bytes.sublist(offset, cursor));
        offset = cursor;
        continue;
      }

      // Not a block we understand. Everything after this point is unread, so
      // whatever metadata is in it is still there — say so rather than handing
      // back a file that was only half looked at.
      return _unrecognised(bytes, 'image/gif');
    }

    final scrubbed = out.toBytes();
    return ScrubResult(
      scrubbed,
      ScrubReport(
        mediaType: 'image/gif',
        originalBytes: bytes.length,
        scrubbedBytes: scrubbed.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  /// Walks a GIF sub-block chain and returns the offset just past its
  /// terminator, or -1 if the file runs out first.
  static int _skipSubBlocks(Uint8List bytes, int from) {
    var offset = from;
    while (offset < bytes.length) {
      final size = bytes[offset];
      if (size == 0) return offset + 1;
      offset += 1 + size;
    }
    return -1;
  }

  static ScrubResult _unrecognised(Uint8List bytes, String type) => ScrubResult(
        bytes,
        ScrubReport(
          mediaType: type,
          originalBytes: bytes.length,
          scrubbedBytes: bytes.length,
          removed: const [],
          recognised: false,
        ),
      );

  // --- Documents ------------------------------------------------------------

  /// The local file header every ZIP starts with.
  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  /// The parts of an Office Open XML file that describe the person rather than
  /// the document, and what goes in their place.
  ///
  /// Replaced rather than removed. Deleting a part leaves the relationship that
  /// points at it and the content-type override that declares it dangling, and
  /// a word processor handed those is entitled to call the file corrupt. An
  /// empty part of the right type is valid everywhere the full one was.
  static const Map<String, String> _ooxmlProperties = {
    'docProps/core.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<cp:coreProperties '
            'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" '
            'xmlns:dcterms="http://purl.org/dc/terms/" '
            'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>',
    'docProps/app.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Properties '
            'xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
            'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"/>',
    'docProps/custom.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Properties '
            'xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
            'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"/>',
  };

  /// The same for OpenDocument, which keeps all of it in one part.
  static const Map<String, String> _odfProperties = {
    'meta.xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-meta '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'office:version="1.2"><office:meta/></office:document-meta>',
  };

  static const Map<String, String> _partNames = {
    'docProps/core.xml': 'Author, last saved by, revision number, timestamps',
    'docProps/app.xml': 'Company, application, total editing time',
    'docProps/custom.xml': 'Custom document properties',
    'meta.xml': 'Author, editing cycles, editing time, timestamps',
  };

  /// Empties the metadata parts of a document that is a ZIP underneath.
  ///
  /// Word, Excel, PowerPoint and their OpenDocument equivalents all carry the
  /// name of whoever wrote the file, the name of whoever last saved it, how
  /// long it was open, and often the company it was written at. None of that
  /// is visible in the document, and all of it travels with it. Encryption
  /// does not help: the recipient decrypts the file and gets the lot.
  ///
  /// Anything that is a ZIP but not one of these formats is left alone and
  /// reported as unrecognised. Rewriting an archive of unknown files is not
  /// this function's business.
  static ScrubResult _scrubZipDocument(Uint8List bytes, String declaredType) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return _unrecognised(bytes, declaredType);
    }

    final names = {for (final file in archive.files) file.name};
    final Map<String, String> replacements;
    if (names.contains('[Content_Types].xml')) {
      replacements = _ooxmlProperties;
    } else if (names.contains('mimetype') && names.contains('meta.xml')) {
      replacements = _odfProperties;
    } else {
      return _unrecognised(bytes, declaredType);
    }

    final removed = <String>[];
    final rebuilt = Archive();
    for (final file in archive.files) {
      final replacement = replacements[file.name];
      final ArchiveFile entry;
      if (replacement != null && !file.isDirectory) {
        // Only worth reporting when there was something in it. An empty
        // core.xml replaced by an empty core.xml removed nothing.
        if (_carriesAnything(file)) removed.add(_partNames[file.name] ?? file.name);
        entry = ArchiveFile.string(file.name, replacement);
      } else {
        entry = ArchiveFile.bytes(file.name, file.readBytes() ?? const <int>[]);
      }
      // An OpenDocument reader looks for `mimetype` first and stored, not
      // deflated. Re-compressing it produces a file that opens as a ZIP and
      // not as a document.
      if (file.name == 'mimetype') entry.compression = CompressionType.none;
      // Every entry carries the minute it was written, which is a record of
      // when somebody was working on it. Flattened to one fixed instant, the
      // same for every file Privio sends.
      entry.lastModTime = _zipEpoch;
      rebuilt.addFile(entry);
    }

    final Uint8List encoded;
    try {
      encoded = ZipEncoder().encodeBytes(rebuilt);
    } on Object {
      return _unrecognised(bytes, declaredType);
    }
    removed.add('File timestamps inside the document');

    return ScrubResult(
      encoded,
      ScrubReport(
        mediaType: declaredType,
        originalBytes: bytes.length,
        scrubbedBytes: encoded.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  /// 1980-01-01 00:00 UTC, in seconds. The encoder wants Unix seconds and a
  /// ZIP entry stores a DOS date, whose earliest expressible instant this is —
  /// so it reads as "unset" rather than as a date somebody worked on this.
  static const int _zipEpoch = 315532800;

  /// The elements that name a person, a company, a machine or a moment.
  ///
  /// Listed rather than inferred: the empty part put in place of a full one is
  /// still a `<cp:coreProperties>` element with its namespaces, so "does it
  /// contain a tag" would call every scrubbed file dirty and report a removal
  /// on a file where nothing was removed.
  static final RegExp _identifyingElement = RegExp(
    r'<(dc:creator|dc:title|dc:subject|dc:description|dc:date|dc:language'
    r'|cp:lastModifiedBy|cp:revision|cp:keywords|cp:category|cp:contentStatus'
    r'|cp:lastPrinted|dcterms:created|dcterms:modified'
    r'|Company|Manager|Application|AppVersion|TotalTime|LastModifiedBy'
    r'|meta:|property)',
  );

  /// Whether a metadata part holds anything worth taking out.
  static bool _carriesAnything(ArchiveFile file) {
    final content = file.readBytes();
    if (content == null) return false;
    return _identifyingElement.hasMatch(String.fromCharCodes(content));
  }

  // --- JPEG -----------------------------------------------------------------

  /// JPEG markers carrying metadata rather than image data.
  ///
  /// APP0 (JFIF) and APP14 (Adobe colour transform) stay: dropping them changes
  /// how the image decodes. Everything else in the APP range is provenance.
  static const Map<int, String> _jpegMetadataMarkers = {
    0xE1: 'EXIF / XMP (camera, GPS, timestamps)',
    0xE2: 'ICC colour profile',
    0xE3: 'Kodak metadata',
    0xE4: 'FlashPix metadata',
    0xE5: 'Ricoh metadata',
    0xE6: 'Epson metadata',
    0xE7: 'Vendor metadata',
    0xE8: 'SPIFF metadata',
    0xE9: 'Vendor metadata',
    0xEA: 'Vendor metadata',
    0xEB: 'Vendor metadata',
    0xEC: 'Picture info',
    0xED: 'IPTC / Photoshop metadata',
    0xEF: 'Vendor metadata',
    0xFE: 'Embedded comment',
  };

  static ScrubResult _scrubJpeg(Uint8List bytes) {
    final out = BytesBuilder();
    final removed = <String>[];
    var offset = 0;

    // SOI
    out.add(bytes.sublist(0, 2));
    offset = 2;

    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xFF) break; // Not a marker: malformed, bail out.
      final marker = bytes[offset + 1];

      // Start of scan: everything after it is entropy-coded image data.
      if (marker == 0xDA) {
        out.add(bytes.sublist(offset));
        offset = bytes.length;
        break;
      }
      // Standalone markers carry no payload.
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD9) || marker == 0x01) {
        out.add(bytes.sublist(offset, offset + 2));
        offset += 2;
        continue;
      }

      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      final end = offset + 2 + length;
      if (length < 2 || end > bytes.length) break; // Truncated: keep what is left.

      final label = _jpegMetadataMarkers[marker];
      if (label != null) {
        if (!removed.contains(label)) removed.add(label);
      } else {
        out.add(bytes.sublist(offset, end));
      }
      offset = end;
    }
    if (offset < bytes.length) out.add(bytes.sublist(offset));

    final scrubbed = out.toBytes();
    return ScrubResult(
      scrubbed,
      ScrubReport(
        mediaType: 'image/jpeg',
        originalBytes: bytes.length,
        scrubbedBytes: scrubbed.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  // --- PNG ------------------------------------------------------------------

  /// PNG chunks that are kept. Everything else goes, which is the safe default
  /// for a format anyone can append arbitrary chunks to.
  static const Set<String> _pngKeep = {
    'IHDR', 'PLTE', 'IDAT', 'IEND', // structure and pixels
    'tRNS', 'gAMA', 'cHRM', 'sRGB', 'sBIT', // needed to render correctly
    'acTL', 'fcTL', 'fdAT', // APNG animation frames
  };

  static const Map<String, String> _pngLabels = {
    'tEXt': 'Text comment',
    'zTXt': 'Compressed text comment',
    'iTXt': 'International text comment (often XMP)',
    'eXIf': 'EXIF (camera, GPS, timestamps)',
    'tIME': 'Last-modified timestamp',
    'iCCP': 'ICC colour profile',
    'pHYs': 'Physical pixel dimensions',
    'bKGD': 'Background colour hint',
    'hIST': 'Palette histogram',
    'sPLT': 'Suggested palette',
  };

  static ScrubResult _scrubPng(Uint8List bytes) {
    final out = BytesBuilder()..add(bytes.sublist(0, 8));
    final removed = <String>[];
    var offset = 8;

    while (offset + 8 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final end = offset + 12 + length; // length + type + data + crc
      if (end > bytes.length) break;

      if (_pngKeep.contains(type)) {
        out.add(bytes.sublist(offset, end));
      } else {
        final label = _pngLabels[type] ?? 'Ancillary chunk $type';
        if (!removed.contains(label)) removed.add(label);
      }

      offset = end;
      if (type == 'IEND') break;
    }

    final scrubbed = out.toBytes();
    return ScrubResult(
      scrubbed,
      ScrubReport(
        mediaType: 'image/png',
        originalBytes: bytes.length,
        scrubbedBytes: scrubbed.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  // --- MP4 / QuickTime ------------------------------------------------------

  /// Boxes that exist to describe rather than to play: location, device, tags.
  static const Map<String, String> _mp4Drop = {
    'udta': 'User data (GPS location, device make and model)',
    'meta': 'Metadata tags',
    'uuid': 'Vendor extension box (often XMP)',
    'free': 'Free space',
    'skip': 'Skipped space',
  };

  /// Containers worth walking into, because metadata hides inside them.
  static const Set<String> _mp4Containers = {'moov', 'trak', 'mdia', 'edts', 'minf'};

  static ScrubResult _scrubMp4(Uint8List bytes, String mediaType) {
    final removed = <String>[];
    final scrubbed = _scrubMp4Boxes(bytes, 0, bytes.length, removed);
    return ScrubResult(
      scrubbed,
      ScrubReport(
        mediaType: mediaType,
        originalBytes: bytes.length,
        scrubbedBytes: scrubbed.length,
        removed: removed,
        recognised: true,
      ),
    );
  }

  static Uint8List _scrubMp4Boxes(
    Uint8List bytes,
    int start,
    int end,
    List<String> removed,
  ) {
    final out = BytesBuilder();
    var offset = start;

    while (offset + 8 <= end) {
      var size = _readUint32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      var headerSize = 8;

      if (size == 1) {
        // 64-bit size. Rare, and nothing we rewrite lives inside one, so it is
        // copied through whole.
        if (offset + 16 > end) break;
        size = _readUint64(bytes, offset + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset; // Extends to the end of the file.
      }
      if (size < headerSize || offset + size > end) break;

      final boxEnd = offset + size;
      final label = _mp4Drop[type];

      if (label != null) {
        if (!removed.contains(label)) removed.add(label);
      } else if (_mp4Containers.contains(type) && headerSize == 8) {
        // Rebuild the container from its scrubbed children, with a fresh size.
        final children = _scrubMp4Boxes(bytes, offset + 8, boxEnd, removed);
        out
          ..add(_uint32(children.length + 8))
          ..add(bytes.sublist(offset + 4, offset + 8))
          ..add(children);
      } else if (type == 'mvhd' || type == 'tkhd' || type == 'mdhd') {
        out.add(_zeroTimestamps(bytes.sublist(offset, boxEnd), removed));
      } else {
        out.add(bytes.sublist(offset, boxEnd));
      }
      offset = boxEnd;
    }
    if (offset < end) out.add(bytes.sublist(offset, end));
    return out.toBytes();
  }

  /// Blanks the creation and modification times in a header box.
  ///
  /// They record when the recording was made to the second, which is a strong
  /// correlator on its own.
  static Uint8List _zeroTimestamps(Uint8List box, List<String> removed) {
    final out = Uint8List.fromList(box);
    if (out.length < 12) return out;
    final version = out[8]; // after size(4) + type(4)
    const fieldStart = 12; // after version(1) + flags(3)
    final fieldSize = version == 1 ? 8 : 4;
    if (out.length < fieldStart + fieldSize * 2) return out;

    for (var i = fieldStart; i < fieldStart + fieldSize * 2; i++) {
      out[i] = 0;
    }
    const label = 'Recording timestamps';
    if (!removed.contains(label)) removed.add(label);
    return out;
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];

  static int _readUint64(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    return value;
  }

  static Uint8List _uint32(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;
}
