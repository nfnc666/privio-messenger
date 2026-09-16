
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/media/photo.dart';
import 'package:privio/media/photo_source.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/photo_preview_sheet.dart';

Widget _host(Widget child) => MaterialApp(
      theme: PrivioTheme.dark(),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
      home: Scaffold(body: child),
    );

Uint8List _jpeg({int shade = 120}) {
  final image = img.Image(width: 200, height: 150);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<List<PreparedPhoto>> _photos(int count) =>
    PhotoImage.prepareAll([for (var i = 0; i < count; i++) _jpeg(shade: 20 + i * 60)]);

/// Opens the preview from a button, so the result of the route is what the
/// test reads — which is the thing that decides whether anything is sent.
Future<PhotoPreviewResult?> _openPreview(
  WidgetTester tester,
  List<PreparedPhoto> photos, {
  bool allowRetake = false,
}) async {
  PhotoPreviewResult? result;
  var closed = false;
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await PhotoPreviewSheet.open(
              context,
              photos: photos,
              allowRetake: allowRetake,
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(closed, isFalse, reason: 'the preview is up');
  return result;
}

void main() {
  group('what an exception from the picker means', () {
    test('a refused camera is a refusal, and says which one', () {
      final pick = photoPickFailure(
        PlatformException(code: 'camera_access_denied'),
        camera: true,
      );
      expect(pick, isA<PhotoRefused>().having((p) => p.camera, 'camera', isTrue));
    });

    test('a refused library is a refusal about the library', () {
      final pick = photoPickFailure(
        PlatformException(code: 'photo_access_denied'),
        camera: false,
      );
      expect(pick, isA<PhotoRefused>().having((p) => p.camera, 'camera', isFalse));
    });

    test('a restricted device is a refusal too — there is nothing to ask for', () {
      expect(
        photoPickFailure(PlatformException(code: 'camera_access_restricted'), camera: true),
        isA<PhotoRefused>(),
      );
    });

    test('no camera on the device is not an error to apologise for', () {
      expect(
        photoPickFailure(PlatformException(code: 'no_available_camera'), camera: true),
        isA<PhotoUnavailable>(),
      );
    });

    test('a build with no plugin behind the channel says so rather than crashing', () {
      expect(
        photoPickFailure(MissingPluginException('no picker'), camera: false),
        isA<PhotoUnavailable>(),
      );
    });

    test('anything else keeps its message for the sentence on screen', () {
      final pick = photoPickFailure(
        PlatformException(code: 'multiple_request', message: 'already asking'),
        camera: true,
      );
      expect(pick, isA<PhotoFailed>().having((p) => p.detail, 'detail', 'already asking'));
    });
  });

  group('a build with no camera', () {
    test('answers unavailable for both, rather than pretending', () async {
      const source = NoPhotoSource();
      expect(await source.capture(), isA<PhotoUnavailable>());
      expect(await source.pickImages(), isA<PhotoUnavailable>());
    });
  });

  group('the preview is the last point at which a photo can be stopped', () {
    testWidgets('closing it sends nothing', (tester) async {
      PhotoPreviewResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PhotoPreviewSheet.open(context, photos: await _photos(1));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'a cancel is not a send');
    });

    testWidgets('sending hands back the pictures and the caption', (tester) async {
      PhotoPreviewResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PhotoPreviewSheet.open(context, photos: await _photos(2));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  from the roof  ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final send = result as PhotoPreviewSend;
      expect(send.photos, hasLength(2));
      expect(send.caption, 'from the roof', reason: 'trimmed, not padded');
    });

    testWidgets('removing one picture leaves the rest in order', (tester) async {
      PhotoPreviewResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PhotoPreviewSheet.open(context, photos: await _photos(3));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The big delete button removes the one being shown, which is the first.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final send = result as PhotoPreviewSend;
      expect(send.photos.map((p) => p.fileName), ['photo-2.jpg', 'photo-3.jpg']);
    });

    testWidgets('removing the last picture is a cancel, not an empty send',
        (tester) async {
      PhotoPreviewResult? result;
      var closed = false;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PhotoPreviewSheet.open(context, photos: await _photos(1));
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('a capture offers Retake', (tester) async {
      await _openPreview(tester, await _photos(1), allowRetake: true);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('a library selection does not — there is nothing to retake',
        (tester) async {
      await _openPreview(tester, await _photos(1));
      expect(find.text('Retake'), findsNothing);
    });

    testWidgets('Retake is its own answer, not a send', (tester) async {
      PhotoPreviewResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PhotoPreviewSheet.open(
                  context,
                  photos: await _photos(1),
                  allowRetake: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();

      expect(result, isA<PhotoPreviewRetake>());
    });
  });
}
