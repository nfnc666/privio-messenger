import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_decode.dart';
import 'metadata_scrubber.dart';

/// One photo, ready to be sent.
@immutable
class PreparedPhoto {
  const PreparedPhoto({
    required this.bytes,
    required this.fileName,
    required this.width,
    required this.height,
    required this.report,
  });

  /// JPEG, stripped, upright, and within the size limit.
  final Uint8List bytes;

  /// A name this app invented. **Never the path or the name off the device** —
  /// a camera roll filename can carry a date and a counter, and a path can
  /// carry a person's name. Neither has any business travelling with a photo,
  /// and neither is needed to render one.
  final String fileName;

  final int width;
  final int height;

  /// What the scrubber took out, for the notice the chat already shows.
  final ScrubReport report;
}

/// Turns a picked or captured photo into something to send.
///
/// Four things happen here and each of them is a requirement rather than a
/// nicety:
///
/// 1. **It decodes anything the phone can produce**, HEIC included, by going
///    through [ImageDecode.any] — Dart first, then the platform's own codecs.
///    An iPhone writes HEIC by default and a photo that will not decode is a
///    photo that cannot be sent.
/// 2. **It bakes the orientation in.** A JPEG from a camera is very often
///    stored sideways with an EXIF tag saying which way up it goes — and the
///    next step removes that tag. Rotating the pixels first is what stops
///    stripping the metadata from turning every portrait photo on its side.
/// 3. **It shrinks.** A modern phone camera produces 12 megapixels and several
///    megabytes; nobody reads a chat at that size and the upload limit is
///    real.
/// 4. **It strips.** Through the same [MetadataScrubber] every other
///    attachment goes through, so a photo does not take a GPS fix with it.
abstract final class PhotoImage {
  /// The longest edge a sent photo keeps. Generous enough to fill a phone
  /// screen at retina density and still crop into, small enough to send on a
  /// bad connection.
  static const int maxEdge = 2048;

  /// Re-encoded at this quality. High enough that faces and text survive, low
  /// enough that a photograph lands in a few hundred kilobytes.
  static const int quality = 82;

  /// What a sent photo may weigh. Below the server's own limit on purpose: the
  /// point is to arrive, not to find out at the end that it will not.
  static const int maxBytes = 8 * 1024 * 1024;

  /// Prepares one photo, or null when nothing on this device can read it.
  ///
  /// [index] only names the file — `photo-1.jpg` — so the recipient's chat has
  /// something to show rather than a blank, and so nothing from the sender's
  /// filesystem travels.
  static Future<PreparedPhoto?> prepare(Uint8List picked, {int index = 1}) async {
    // **The original is decoded, not the scrubbed copy, and the order is the
    // whole point.** Scrubbing removes the EXIF — orientation included — so a
    // photo decoded from the scrubbed bytes has already lost the tag that says
    // which way up it goes, and every picture taken in portrait arrives lying
    // on its side. The scrub still runs, and runs first, but only to describe
    // what was in the file: that description is what the chat's notice shows,
    // and it has to be about the photo the person picked rather than about the
    // re-encoding below.
    //
    // A test holds this: a JPEG tagged orientation 6 comes out 600×800 rather
    // than 800×600, and it failed when these two lines were the other way
    // round.
    final scrubbed = MetadataScrubber.scrub(picked);
    final decoded = await ImageDecode.any(picked);
    if (decoded == null) return null;

    // Turns the pixels the way the tag said they should be shown, and clears
    // the tag. Now the image is upright without needing anybody to be told.
    final upright = img.bakeOrientation(decoded);

    final longest = upright.width > upright.height ? upright.width : upright.height;
    final sized = longest <= maxEdge
        ? upright
        : img.copyResize(
            upright,
            width: upright.width >= upright.height ? maxEdge : null,
            height: upright.height > upright.width ? maxEdge : null,
            interpolation: img.Interpolation.average,
          );

    // Everything else the original carried goes here, before encoding: a GPS
    // fix lives in the same EXIF block `bakeOrientation` only partly clears,
    // and `encodeJpg` writes back whatever the image still holds. Clearing it
    // outright is the one line that stops a photograph taking a location with
    // it.
    sized.exif = img.ExifData();

    // Scrubbed again on the way out. The encoder should now be producing a
    // file with nothing in it, and this is what makes that a checked fact
    // rather than an assumption about somebody else's library.
    final encoded = MetadataScrubber.scrub(_encodeWithinLimit(sized)).bytes;

    return PreparedPhoto(
      bytes: encoded,
      fileName: 'photo-$index.jpg',
      width: sized.width,
      height: sized.height,
      // The report describes the file that was picked — what was taken out of
      // it — which is what the notice in the chat is about.
      report: scrubbed.report,
    );
  }

  /// Prepares several, keeping the order they were chosen in.
  ///
  /// Order matters and is easy to lose: `Future.wait` would finish in whatever
  /// order the work happened to complete, and a set of photos that arrives
  /// shuffled is a set of photos somebody has to explain. Sequential here, and
  /// the list is built in step.
  static Future<List<PreparedPhoto>> prepareAll(List<Uint8List> picked) async {
    final out = <PreparedPhoto>[];
    for (var i = 0; i < picked.length; i++) {
      final photo = await prepare(picked[i], index: out.length + 1);
      // One unreadable file does not take the rest of the selection down.
      if (photo != null) out.add(photo);
    }
    return out;
  }

  /// Encodes, dropping quality then size until it fits.
  ///
  /// A photograph at quality 82 is almost always well inside the limit; this is
  /// for the ones that are not — a screenshot of dense text, a panorama — and
  /// it tries the cheap lever first. Re-encoding at a lower quality keeps the
  /// dimensions, which matters more to a reader than the last few per cent of
  /// detail.
  static Uint8List _encodeWithinLimit(img.Image image) {
    for (final attempt in const [quality, 65, 50]) {
      final encoded = img.encodeJpg(image, quality: attempt);
      if (encoded.length <= maxBytes) return encoded;
    }

    var current = image;
    for (var step = 0; step < 4; step++) {
      current = img.copyResize(
        current,
        width: (current.width * 3) ~/ 4,
        interpolation: img.Interpolation.average,
      );
      final encoded = img.encodeJpg(current, quality: 65);
      if (encoded.length <= maxBytes) return encoded;
    }
    // Five megapixels of noise at quality 50 is already far under the limit, so
    // this is unreachable in practice. Returning the smallest attempt rather
    // than throwing means the send is refused by the server with a sentence
    // rather than by an exception with none.
    return img.encodeJpg(current, quality: 50);
  }
}
