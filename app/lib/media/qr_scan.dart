import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'image_decode.dart';

/// Reading a QR code out of a picture.
///
/// **There is no live camera scanner here, and that is a decision rather than a
/// gap.** Every live-scanning package for Flutter that works well on Android
/// goes through Google's ML Kit, which would put a Play Services dependency
/// into a build whose whole claim is that it has none — see `docs/privio-libre.md`.
/// What this does instead is take a photograph with the camera Privio already
/// opens for chat photos and decode it here, in Dart, on the device.
///
/// The trade is honest: a photo of a screen has to be reasonably square-on and
/// in focus, where a live scanner keeps trying thirty times a second. The gain
/// is that the decode is pure Dart, links nothing, and is testable end to end —
/// the round trip through a generated QR is in `qr_scan_test.dart`.
abstract final class QrScan {
  /// The text in the first QR code found, or null when there is none.
  ///
  /// Null rather than a throw for every failure the camera can produce — a
  /// blurred shot, a hand in the way, a picture of something that is not a QR
  /// code at all. None of those is exceptional and all of them mean the same
  /// thing to the person holding the phone: try again.
  static Future<String?> read(Uint8List picture) async {
    final decoded = await ImageDecode.any(picture);
    if (decoded == null) return null;
    return fromImage(decoded);
  }

  /// The same, for a picture that is already decoded.
  static String? fromImage(img.Image image) {
    // A 12-megapixel photo is both slower to scan and no more likely to decode
    // than a sensible one; the finder patterns survive the downscale.
    final sized = image.width > _maxEdge || image.height > _maxEdge
        ? img.copyResize(
            image,
            width: image.width >= image.height ? _maxEdge : null,
            height: image.height > image.width ? _maxEdge : null,
          )
        : image;

    final source = RGBLuminanceSource(
      sized.width,
      sized.height,
      sized
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List(),
    );

    // Hybrid rather than the global histogram: a photograph of a phone screen
    // has a bright patch where the room light is, and a single global
    // threshold turns that patch into solid white.
    try {
      return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
    } on Object {
      // Falls back to the simpler binarizer, which does better on a clean
      // screenshot than the adaptive one does.
      try {
        return QRCodeReader().decode(BinaryBitmap(GlobalHistogramBinarizer(source))).text;
      } on Object {
        return null;
      }
    }
  }

  static const int _maxEdge = 1024;
}
