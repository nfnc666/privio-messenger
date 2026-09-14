import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_colors.dart';

/// The palette, held to the two properties that decide whether an accent may
/// be offered at all: it has to be readable on the black the app sits on, and
/// whatever is drawn on top of it has to be readable too. Both are measured
/// rather than eyeballed, so a ninth colour cannot be added without the check
/// running against it.
void main() {
  group('every offered accent can actually be read', () {
    // WCAG AA for large text and for UI components. The accent is used for
    // labels, icons, ticks and strokes rather than body copy, which is the
    // 3:1 case; the check on labels *on* the accent below is stricter.
    const floor = 3.0;

    test('against the black the app sits on', () {
      for (final accent in AppAccent.values) {
        final ratio = PrivioAccents.contrastRatio(accent.seed, PrivioColors.background);
        expect(
          ratio,
          greaterThanOrEqualTo(floor),
          reason: '${accent.code} is ${ratio.toStringAsFixed(2)}:1 on black',
        );
      }
    });

    test('a label on the accent is readable, whichever way that falls', () {
      for (final accent in AppAccent.values) {
        final colours = PrivioAccents.of(accent);
        final ratio = PrivioAccents.contrastRatio(colours.accent, colours.onAccent);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${accent.code} label is ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('all eight take dark labels, because that is what measures better', () {
      // Worth pinning as an outcome rather than leaving to the rule above.
      // Several of these read as "white text" colours by convention — white on
      // #A855F7 is 3.96:1 and fails AA for normal text, while black is 5.31:1.
      // Measured beats conventional, and a uniform dark label across all eight
      // is also the more coherent result: it is what the app already did on
      // green. A future accent dark enough to want white would get it from
      // [PrivioAccents.readableOn] without this list being the thing that
      // decided.
      for (final accent in AppAccent.values) {
        expect(
          PrivioAccents.of(accent).onAccent,
          PrivioColors.background,
          reason: accent.code,
        );
      }
    });

    test('a message bubble is dark enough for white text on it', () {
      for (final accent in AppAccent.values) {
        final ratio = PrivioAccents.contrastRatio(
          PrivioAccents.of(accent).bubbleOutgoing,
          PrivioColors.textPrimary,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${accent.code} bubble is ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('choosing green gives back the app that shipped', () {
    // The property that makes the default a no-op rather than a redesign: the
    // derivation was fitted to Privio's own palette, so green must land back
    // on the constants the whole app was drawn with.
    final green = PrivioAccents.of(AppAccent.green);

    void expectClose(Color derived, Color original, String name) {
      // Within a couple of steps per channel. The derivation is a formula and
      // the originals were picked by hand, so exact equality would be a
      // coincidence rather than a property.
      for (final (a, b, channel) in [
        (derived.r, original.r, 'red'),
        (derived.g, original.g, 'green'),
        (derived.b, original.b, 'blue'),
      ]) {
        expect(
          (a - b).abs(),
          lessThan(0.04),
          reason: '$name $channel: $derived vs $original',
        );
      }
    }

    test('the accent itself is the same colour', () {
      expect(green.accent, PrivioColors.accent);
    });

    test('the brighter, dimmer and tinted shades land where they were', () {
      expectClose(green.bright, PrivioColors.accentBright, 'bright');
      expectClose(green.dim, PrivioColors.accentDim, 'dim');
      expectClose(green.surface, PrivioColors.accentSurface, 'surface');
      expectClose(green.bubbleOutgoing, PrivioColors.bubbleOutgoing, 'bubble');
    });
  });

  group('the stored name, not the position in the enum', () {
    test('a code round-trips', () {
      for (final accent in AppAccent.values) {
        expect(AppAccent.forCode(accent.code), accent);
      }
    });

    test('a name this build has never heard of is not a crash', () {
      expect(AppAccent.forCode('chartreuse'), isNull);
      expect(AppAccent.forCode(null), isNull);
    });

    test('green is what an account has before it chooses', () {
      expect(AppAccent.fallback, AppAccent.green);
    });
  });

  group('a theme with no accent on it still draws', () {
    testWidgets('falls back to the brand colour rather than throwing', (tester) async {
      late PrivioAccents seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.accents;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.accent, PrivioColors.accent);
    });
  });
}
