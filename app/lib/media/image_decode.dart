import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Decodes picked bytes into an image, whatever wrote them.
///
/// **Two decoders, and the second one is the reason this is async.**
/// `package:image` is pure Dart and reads JPEG, PNG, WebP, GIF and a handful
/// more — but it has no HEIC decoder, and HEIC is what an iPhone camera writes
/// by default. So every photo taken on an iPhone arrived, failed to decode and
/// came back as "not an image Privio can use": the picker opened, a picture was
/// chosen, and nothing happened.
///
/// The fallback hands the bytes to the engine, which uses the platform's own
/// codecs — ImageIO on iOS, Skia's HEIF path on Android — so anything the
/// operating system can open, this can open. It is second rather than first
/// because it costs a trip through the engine and the common case does not
/// need it.
///
/// Lives here rather than beside one caller because both the avatar path and
/// the sticker path need exactly this, and a second copy is a second place for
/// the HEIC lesson to be forgotten.
abstract final class ImageDecode {
  /// The image, or null when nothing on this device can read the bytes.
  static Future<img.Image?> any(Uint8List bytes) async =>
      inDart(bytes) ?? await onPlatform(bytes);

  static img.Image? inDart(Uint8List bytes) {
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
  /// end in the same place.
  static Future<img.Image?> onPlatform(Uint8List bytes) async {
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
}
