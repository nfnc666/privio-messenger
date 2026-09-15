import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/sticker_controller.dart';
import 'image_decode.dart';
import 'metadata_scrubber.dart';

/// A crop, in fractions of the source image.
///
/// Fractions rather than pixels so the widget that drew the frame does not
/// have to know how large the original is: it knows what part of the picture
/// the person put inside the square, which is the same thing at any scale.
class StickerCrop {
  const StickerCrop({
    required this.left,
    required this.top,
    required this.side,
  });

  /// The whole picture, centre-cropped to a square by [StickerImage.prepare].
  static const StickerCrop whole = StickerCrop(left: 0, top: 0, side: 1);

  final double left;
  final double top;

  /// The side of the square, as a fraction of the shorter edge.
  final double side;
}

/// Prepares a picked image for use as a sticker or a custom emoji.
///
/// Three things this does that the avatar path deliberately does not:
///
/// 1. **PNG, not JPEG.** A sticker without transparency is a rectangle with a
///    white box around it, which is not a sticker. JPEG has no alpha channel
///    at all, so the format is the decision — not a quality setting.
/// 2. **It can fail on size.** The server reads the header and refuses
///    anything over its limits, so this shrinks until it fits rather than
///    uploading something that will come back refused. What it will not do is
///    upscale: a 40-pixel picture stays 40 pixels and is simply small.
/// 3. **It takes a crop.** The person chose which part of the picture is the
///    sticker; centre-cropping over the top of that would throw their choice
///    away.
abstract final class StickerImage {
  /// The longest edge that leaves the server's check, and the shortest that
  /// passes it. Both from [StickerLimits], which mirrors the server's own.
  static int get maxEdge => StickerLimits.maxEdge;
  static int get minEdge => StickerLimits.minEdge;

  /// Returns PNG bytes, or null when nothing here can read the picture.
  ///
  /// [crop] is in fractions of the source; omit it for the middle square.
  static Future<Uint8List?> prepare(Uint8List picked, {StickerCrop? crop}) async {
    // Scrubbed first, like every other picture that leaves this device. A
    // sticker is more exposed than most: it is shared by link, to people the
    // author has never spoken to, so the camera model and the GPS tag in the
    // original have no business travelling with it.
    final scrubbed = MetadataScrubber.scrub(picked).bytes;
    final decoded = await ImageDecode.any(scrubbed);
    if (decoded == null) return null;

    final square = _square(decoded, crop);
    // Never upscaled: enlarging a small picture makes a blurry sticker out of
    // a sharp one and buys nothing, since the server's minimum is about
    // refusing a one-pixel file, not about demanding a large one.
    final side = square.width > maxEdge ? maxEdge : square.width;
    final sized = side == square.width
        ? square
        : img.copyResize(
            square,
            width: side,
            height: side,
            interpolation: img.Interpolation.average,
          );

    return _encodeWithinLimit(sized);
  }

  /// Whether prepared bytes would pass the server's own check.
  ///
  /// Used by the sheet to grey out the confirm button rather than letting
  /// somebody press it and be refused. The server checks again regardless —
  /// this is a courtesy, not the rule.
  static bool fits(Uint8List png, {int? edge}) =>
      png.length <= StickerLimits.maxBytes && (edge == null || edge >= minEdge);

  /// Encodes, and shrinks until it is under the byte limit.
  ///
  /// A 512×512 photograph with an alpha channel can be well over half a
  /// megabyte as PNG, and the loop is what stops that becoming an upload the
  /// server refuses. Each step is a real resize rather than a quality knob:
  /// PNG is lossless, so there is no quality to turn down — the only thing
  /// that makes it smaller is fewer pixels.
  static Uint8List? _encodeWithinLimit(img.Image image) {
    var current = image;
    for (var attempt = 0; attempt < 5; attempt++) {
      final encoded = img.encodePng(current);
      if (encoded.length <= StickerLimits.maxBytes) return encoded;
      final next = (current.width * 3) ~/ 4;
      if (next < minEdge) {
        // Smaller than the server will take. Hand back what we have and let
        // the refusal be the server's, said in this app's words — better than
        // silently producing something below the minimum.
        return encoded;
      }
      current = img.copyResize(
        current,
        width: next,
        height: next,
        interpolation: img.Interpolation.average,
      );
    }
    return img.encodePng(current);
  }

  /// The square the person chose, or the middle one.
  static img.Image _square(img.Image source, StickerCrop? crop) {
    final shortest = source.width < source.height ? source.width : source.height;
    if (crop == null) {
      return img.copyCrop(
        source,
        x: (source.width - shortest) ~/ 2,
        y: (source.height - shortest) ~/ 2,
        width: shortest,
        height: shortest,
      );
    }

    // Clamped rather than trusted. The fractions come from a gesture, and a
    // fling can leave them slightly outside the picture; `copyCrop` on an
    // out-of-bounds rectangle is not something to find out about in the field.
    final side = (crop.side.clamp(0.05, 1.0) * shortest).round().clamp(1, shortest);
    final maxLeft = source.width - side;
    final maxTop = source.height - side;
    final left = (crop.left * source.width).round().clamp(0, maxLeft < 0 ? 0 : maxLeft);
    final top = (crop.top * source.height).round().clamp(0, maxTop < 0 ? 0 : maxTop);
    return img.copyCrop(source, x: left, y: top, width: side, height: side);
  }
}
