import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/media/photo.dart';

/// Preparing a photo for sending.
///
/// The two that matter most are orientation and stripping, and they are
/// entangled: a camera JPEG is often stored sideways with an EXIF tag saying
/// which way up it goes, and removing the metadata without first rotating the
/// pixels turns every portrait photo on its side. So the order is tested, not
/// just the outcome.
void main() {
  /// A JPEG with the given dimensions, and optionally an orientation tag.
  Uint8List jpeg(int width, int height, {int? orientation}) {
    final image = img.Image(width: width, height: height);
    // A gradient rather than flat colour, so a resize has something to lose and
    // the encoder cannot collapse it to nothing.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    if (orientation != null) image.exif.imageIfd.orientation = orientation;
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  test('a photo comes back as a JPEG', () async {
    final photo = await PhotoImage.prepare(jpeg(800, 600));

    expect(photo, isNotNull);
    // The JPEG SOI marker.
    expect(photo!.bytes.take(2), [0xFF, 0xD8]);
    expect(photo.width, 800);
    expect(photo.height, 600);
  });

  test('a large photo is shrunk to the longest edge', () async {
    final photo = await PhotoImage.prepare(jpeg(4032, 3024));

    expect(photo!.width, PhotoImage.maxEdge);
    // The aspect ratio survives: 4032×3024 is 4:3, so 2048 wide is 1536 tall.
    expect(photo.height, 1536);
  });

  test('a tall photo is shrunk on its own longest edge', () async {
    final photo = await PhotoImage.prepare(jpeg(3024, 4032));

    expect(photo!.height, PhotoImage.maxEdge);
    expect(photo.width, 1536);
  });

  test('a small photo is left at its own size rather than blown up', () async {
    final photo = await PhotoImage.prepare(jpeg(320, 240));

    expect(photo!.width, 320);
    expect(photo.height, 240);
  });

  test('it lands inside the size limit', () async {
    final photo = await PhotoImage.prepare(jpeg(4032, 3024));
    expect(photo!.bytes.length, lessThanOrEqualTo(PhotoImage.maxBytes));
  });

  test('a sideways photo is rotated before its tag is thrown away', () async {
    // Orientation 6 means "rotate 90° clockwise to display" — what a phone
    // writes when you hold it upright. The pixels are 800 wide and 600 tall;
    // shown correctly the photo is 600 wide and 800 tall.
    final photo = await PhotoImage.prepare(jpeg(800, 600, orientation: 6));

    expect(
      photo!.width,
      600,
      reason: 'the pixels must be turned, not just the tag removed',
    );
    expect(photo.height, 800);
  });

  test('an upright photo is not turned', () async {
    final photo = await PhotoImage.prepare(jpeg(800, 600, orientation: 1));
    expect(photo!.width, 800);
    expect(photo.height, 600);
  });

  test('nothing from the device travels in the name', () async {
    // Not the camera roll's filename and not a path: one can carry a date and a
    // counter, the other can carry a person's name.
    final photo = await PhotoImage.prepare(jpeg(800, 600), index: 3);
    expect(photo!.fileName, 'photo-3.jpg');
  });

  test('something that is not a picture yields nothing rather than throwing',
      () async {
    final photo = await PhotoImage.prepare(
      Uint8List.fromList('not a photo, whatever the extension says'.codeUnits),
    );
    expect(photo, isNull);
  });

  group('several at once', () {
    test('keep the order they were chosen in', () async {
      // Each one a different size, so the order is visible in the result.
      final prepared = await PhotoImage.prepareAll([
        jpeg(400, 300),
        jpeg(800, 600),
        jpeg(1200, 900),
      ]);

      expect(prepared.map((each) => each.width), [400, 800, 1200]);
      expect(prepared.map((each) => each.fileName), [
        'photo-1.jpg',
        'photo-2.jpg',
        'photo-3.jpg',
      ]);
    });

    test('one unreadable file does not take the rest down', () async {
      final prepared = await PhotoImage.prepareAll([
        jpeg(400, 300),
        Uint8List.fromList('rubbish'.codeUnits),
        jpeg(800, 600),
      ]);

      expect(prepared, hasLength(2));
      expect(prepared.map((each) => each.width), [400, 800]);
      // And the names stay in step with what survived, rather than leaving a
      // gap where the broken one was.
      expect(prepared.map((each) => each.fileName), ['photo-1.jpg', 'photo-2.jpg']);
    });

    test('an empty selection is an empty result, not an error', () async {
      expect(await PhotoImage.prepareAll([]), isEmpty);
    });
  });

  test('a location in the picture does not travel with it', () async {
    // The one piece of metadata that can actually hurt somebody: a photograph
    // taken at home carries the house. `MetadataScrubber` is asked to remove
    // it and the encoder is asked not to write it back; this checks the file
    // that comes out, rather than trusting either.
    final image = img.Image(width: 120, height: 90);
    img.fill(image, color: img.ColorRgb8(90, 140, 190));
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(47, 1);
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(8, 1);
    image.exif.imageIfd['Make'] = 'A phone';
    final withLocation = Uint8List.fromList(img.encodeJpg(image));

    // The fixture has to actually carry it, or the test proves nothing.
    expect(img.decodeJpg(withLocation)!.exif.gpsIfd.isEmpty, isFalse);

    final sent = await PhotoImage.prepare(withLocation);

    final out = img.decodeJpg(sent!.bytes)!;
    expect(out.exif.gpsIfd.isEmpty, isTrue, reason: 'no location leaves the device');
    expect(out.exif.imageIfd['Make'], isNull, reason: 'nor the camera it was taken on');
  });
}
