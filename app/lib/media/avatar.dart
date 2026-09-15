import 'dart:typed_data';
import 'dart:ui' as ui;

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
  ///
  /// **Two decoders, and the second one is why this is async.** `package:image`
  /// is pure Dart and reads JPEG, PNG, WebP, GIF and a handful more — but it has
  /// no HEIC decoder, and HEIC is what an iPhone camera writes by default. So
  /// every photo taken on an iPhone arrived here, failed to decode, and came
  /// back as "not an image Privio can use": the picker opened, a picture was
  /// chosen, and nothing happened. That was the bug, and it hit the channel
  /// picture, the account picture and the new-channel screen alike.
  ///
  /// The fallback hands the bytes to the engine, which uses the platform's own
  /// codecs — ImageIO on iOS, Skia's HEIF path on Android — so anything the
  /// operating system can open, this can open. It is second rather than first
  /// because it costs a trip through the engine and the common case does not
  /// need it.
  static Future<Uint8List?> prepare(Uint8List picked) async {
    // Scrub first: if decoding fails we still return null rather than passing
    // the original through, so an undecodable file never becomes an avatar.
    final scrubbed = MetadataScrubber.scrub(picked).bytes;
    final decoded = _decodeInDart(scrubbed) ?? await _decodeOnPlatform(scrubbed);
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

  static img.Image? _decodeInDart(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } on Object {
      // The decoder throws rather than returning null on some malformed input —
      // an empty file, for one. Either way Dart cannot read it; the platform
      // still gets its turn.
      return null;
    }
  }

  /// Decodes through the Flutter engine, which means the platform's codecs.
  ///
  /// Returns null rather than throwing when there is no engine to ask — a unit
  /// test with no binding, for one — so "no platform here" and "not a picture"
  /// end in the same place as they always did.
  static Future<img.Image?> _decodeOnPlatform(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = (await codec.getNextFrame()).image;
      final raw = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) return null;
      return img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: raw.buffer,
        numChannels: 4,
      );
    } on Object {
      return null;
    } finally {
      frame?.dispose();
      codec?.dispose();
    }
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
