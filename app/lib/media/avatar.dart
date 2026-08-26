import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'metadata_scrubber.dart';

/// Prepares a picked image for use as a profile picture.
///
/// Avatars are shown at 88 logical pixels at most, so uploading a 12-megapixel
/// photo wastes bandwidth on both sides and stores far more of the original
/// scene than anyone needs. Re-encoding also guarantees no metadata survives,
/// on top of the scrubber — belt and braces, because a profile picture is the
/// one image a user hands to everyone they talk to.
abstract final class AvatarImage {
  /// Enough for a retina display at the largest size the app shows.
  static const int size = 512;

  /// Quality high enough that a face still looks like itself.
  static const int jpegQuality = 82;

  /// Returns a square JPEG, or null when the bytes are not a decodable image.
  static Uint8List? prepare(Uint8List picked) {
    // Scrub first: if decoding fails we still return null rather than passing
    // the original through, so an undecodable file never becomes an avatar.
    final scrubbed = MetadataScrubber.scrub(picked).bytes;
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(scrubbed);
    } on Object {
      // The decoder throws rather than returning null on some malformed input —
      // an empty file, for one. Either way it is not a picture.
      return null;
    }
    if (decoded == null) return null;

    final square = _centreCrop(decoded);
    final resized = img.copyResize(
      square,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    return img.encodeJpg(resized, quality: jpegQuality);
  }

  /// Crops to the middle square, which is what a circular avatar shows anyway.
  static img.Image _centreCrop(img.Image source) {
    final side = source.width < source.height ? source.width : source.height;
    return img.copyCrop(
      source,
      x: (source.width - side) ~/ 2,
      y: (source.height - side) ~/ 2,
      width: side,
      height: side,
    );
  }
}
