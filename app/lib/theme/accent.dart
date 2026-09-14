import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'privio_colors.dart';

/// The accents Privio offers, by the name that is stored.
///
/// A fixed list rather than a colour picker, for the reason the channel palette
/// is one: every entry here has been checked for legible text on it and against
/// the black the app sits on. A picker would let somebody choose a colour that
/// makes their own app unreadable, and the setting that did it would be the
/// last one they could still find.
///
/// The stored name is what goes in the keystore, so the order of this enum may
/// change and the wire may not.
enum AppAccent {
  /// Privio's own. What a new account gets, and what "reset" returns to.
  green('green', Color(0xFF22C55E)),
  blue('blue', Color(0xFF3B82F6)),
  teal('teal', Color(0xFF14B8A6)),
  purple('purple', Color(0xFFA855F7)),
  pink('pink', Color(0xFFEC4899)),

  /// Deliberately a rose rather than [PrivioColors.danger]'s red. Destructive
  /// actions stay that red whatever the accent is, and two reds a shade apart
  /// would make "send" and "delete" look like the same button. See
  /// `docs/design-system.md`.
  red('red', Color(0xFFF43F5E)),
  orange('orange', Color(0xFFF97316)),
  yellow('yellow', Color(0xFFEAB308));

  const AppAccent(this.code, this.seed);

  /// What is written to the keystore.
  final String code;

  /// The one value everything else on the screen is derived from.
  final Color seed;

  /// The accent an account has before it has chosen, and after a reset.
  static const AppAccent fallback = AppAccent.green;

  static AppAccent? forCode(String? code) {
    if (code == null) return null;
    for (final accent in AppAccent.values) {
      if (accent.code == code) return accent;
    }
    return null;
  }
}

/// Every accent-derived colour the app draws with, as one value on the theme.
///
/// A `ThemeExtension` rather than a set of constants, because that is what
/// makes `Theme.of(context)` the single answer to "what colour is this" — a
/// screen reads the theme, the theme was built from the account's choice, and
/// nothing in between has to be told when the choice changes.
///
/// The fields are named for what they *do*, not for how they look. `dim` is
/// "an accent surface that is switched off", not "dark green", which is what
/// lets the same screens render in eight colours without one of them being the
/// one the names were written for.
@immutable
class PrivioAccents extends ThemeExtension<PrivioAccents> {
  const PrivioAccents({
    required this.choice,
    required this.accent,
    required this.bright,
    required this.dim,
    required this.surface,
    required this.bubbleOutgoing,
    required this.onAccent,
  });

  /// Derives the whole set from one seed.
  ///
  /// One place, so a pressed state and a disabled state cannot drift apart per
  /// colour, and so adding a ninth accent is adding one line rather than six.
  /// The numbers were fitted to Privio's own green: building this from
  /// [AppAccent.green] returns the palette the app already shipped, which is
  /// what makes the default a no-op rather than a redesign.
  factory PrivioAccents.of(AppAccent choice) {
    final hsl = HSLColor.fromColor(choice.seed);
    return PrivioAccents(
      choice: choice,
      accent: choice.seed,
      bright: hsl.withLightness((hsl.lightness + 0.13).clamp(0.0, 0.95)).toColor(),
      dim: hsl
          .withLightness(0.235)
          .withSaturation((hsl.saturation * 0.92).clamp(0.0, 1.0))
          .toColor(),
      surface: hsl
          .withLightness(0.11)
          .withSaturation((hsl.saturation * 0.69).clamp(0.0, 1.0))
          .toColor(),
      bubbleOutgoing: hsl.withLightness(0.14).toColor(),
      onAccent: readableOn(choice.seed),
    );
  }

  /// Privio green, for anything built before a theme exists to ask.
  static final PrivioAccents privio = PrivioAccents.of(AppAccent.green);

  /// Which accent this was built from, so a screen can mark the chosen row.
  final AppAccent choice;

  /// The accent itself: buttons, active tabs, ticks, switches, links.
  final Color accent;

  /// A shade up. Hover, focus rings, and the one-step-brighter states.
  final Color bright;

  /// An accent surface with nothing behind it: a disabled button.
  final Color dim;

  /// A tinted panel on black — a chip, a selected row, an avatar placeholder.
  final Color surface;

  /// The bubble this account's own messages are drawn in.
  final Color bubbleOutgoing;

  /// Text and icons *on top of* [accent].
  ///
  /// Black on yellow, white on purple. Chosen by measuring rather than by
  /// taste — see [readableOn] — because an accent whose label cannot be read
  /// is an accent that should not have been offered.
  final Color onAccent;

  /// Whichever of black or white can actually be read on [background].
  static Color readableOn(Color background) {
    const dark = PrivioColors.background;
    const light = PrivioColors.textPrimary;
    return contrastRatio(background, dark) >= contrastRatio(background, light) ? dark : light;
  }

  /// WCAG 2.1 relative-luminance contrast, 1:1 to 21:1.
  ///
  /// Here so the accents can be *checked* rather than eyeballed: the test suite
  /// holds every offered colour to a floor, against black and against its own
  /// label. A palette nobody measured is a palette that ships an unreadable
  /// entry the day somebody adds a ninth.
  static double contrastRatio(Color a, Color b) {
    final first = _luminance(a);
    final second = _luminance(b);
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _luminance(Color colour) {
    double channel(double raw) =>
        raw <= 0.03928 ? raw / 12.92 : math.pow((raw + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b);
  }

  @override
  PrivioAccents copyWith({
    AppAccent? choice,
    Color? accent,
    Color? bright,
    Color? dim,
    Color? surface,
    Color? bubbleOutgoing,
    Color? onAccent,
  }) =>
      PrivioAccents(
        choice: choice ?? this.choice,
        accent: accent ?? this.accent,
        bright: bright ?? this.bright,
        dim: dim ?? this.dim,
        surface: surface ?? this.surface,
        bubbleOutgoing: bubbleOutgoing ?? this.bubbleOutgoing,
        onAccent: onAccent ?? this.onAccent,
      );

  @override
  PrivioAccents lerp(ThemeExtension<PrivioAccents>? other, double t) {
    if (other is! PrivioAccents) return this;
    return PrivioAccents(
      choice: t < 0.5 ? choice : other.choice,
      accent: Color.lerp(accent, other.accent, t)!,
      bright: Color.lerp(bright, other.bright, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      bubbleOutgoing: Color.lerp(bubbleOutgoing, other.bubbleOutgoing, t)!,
      onAccent: t < 0.5 ? onAccent : other.onAccent,
    );
  }
}

/// `context.accents.accent` — the way a widget asks what colour to draw in.
///
/// Falls back to Privio green rather than throwing when no theme carries the
/// extension: a widget dropped into a bare `MaterialApp` in a test should
/// render in the brand colour, not crash.
extension PrivioAccentsOf on BuildContext {
  PrivioAccents get accents =>
      Theme.of(this).extension<PrivioAccents>() ?? PrivioAccents.privio;
}
