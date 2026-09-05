import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The font declaration is load-bearing for a privacy claim, and it does not
/// look it — which is exactly why it needs a test.
void main() {
  test('the bundled typeface is declared under the name the engine looks for', () {
    // CanvasKit keeps a default font so that laying out text with an
    // unregistered family cannot crash it, and it downloads that font from
    // fonts.gstatic.com unless the app's manifest declares a family literally
    // called `Roboto` (SkiaFontCollection.loadAssetFonts). Declaring ours as
    // `Privio` alone left the bundled file unused beside a request to Google on
    // every page load. The second declaration looks like a duplicate to tidy
    // away; it is the thing that stops the request.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('- family: Roboto'),
      reason: 'without it every web page load announces itself to Google',
    );
    expect(pubspec, contains('- family: Privio'));
  });

  test('the web build asks for nothing off-origin', () {
    // Both of the engine's off-origin defaults are pinned to this build: the
    // renderer, and the place it looks for glyphs no bundled font can draw.
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('canvasKitBaseUrl: "canvaskit/"'));
    expect(bootstrap, contains('fontFallbackBaseUrl: "fallback-fonts/"'));
    expect(
      bootstrap,
      isNot(contains('https://fonts.gstatic')),
      reason: 'the point of both settings is that no such URL is ever built',
    );
  });
}
