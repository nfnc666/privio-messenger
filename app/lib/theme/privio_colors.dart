import 'package:flutter/widgets.dart';

/// The Privio palette, taken from the mockup sheet in `design/mockups`.
///
/// Privio is dark-first: the background is true black because it is the brand
/// and because it costs nothing on the OLED panels most phones ship with.
abstract final class PrivioColors {
  // Accent
  static const Color accent = Color(0xFF22C55E);
  static const Color accentBright = Color(0xFF4ADE80);
  static const Color accentDim = Color(0xFF166534);
  static const Color accentSurface = Color(0xFF0F2A1A);

  /// Outgoing message bubbles. Sampled from the mockups at ~#043019 and lifted
  /// a shade so anti-aliased text stays crisp against it.
  static const Color bubbleOutgoing = Color(0xFF0B3B21);

  // Neutrals
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0B0B0B);
  static const Color surfaceRaised = Color(0xFF141414);
  static const Color surfaceHigh = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF232323);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA1A1A1);
  static const Color textTertiary = Color(0xFF6B6B6B);

  // Status
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  /// Operator keys in the iPhone-style disguise calculator only.
  static const Color calculatorOperator = Color(0xFFFF9F0A);
}

/// The spacing and radius scale. Everything in the UI is a multiple of these.
abstract final class PrivioSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal screen gutter.
  static const double gutter = 16;
}

abstract final class PrivioRadius {
  static const Radius card = Radius.circular(12);
  static const Radius bubble = Radius.circular(18);
  static const Radius button = Radius.circular(24);
  static const Radius pill = Radius.circular(999);
}

/// The colours a channel may choose for itself.
///
/// Names rather than values, and a fixed list rather than a picker: a channel
/// must not be able to ask for white-on-white, or for a colour that disappears
/// against one of the two backgrounds. Every pair here was checked against
/// both. The server holds the same list as a check constraint, so a channel
/// cannot arrive carrying a colour this app has never heard of.
abstract final class ChannelPalette {
  /// The accent a channel draws its links, buttons and reactions in.
  static const Map<String, Color> accents = {
    'green': PrivioColors.accent,
    'blue': Color(0xFF3B82F6),
    'purple': Color(0xFFA855F7),
    'orange': Color(0xFFF97316),
    'red': Color(0xFFEF4444),
    'teal': Color(0xFF14B8A6),
  };

  /// What its feed sits on. All three are dark: Privio is a dark app, and a
  /// channel choosing a light background would be choosing it for readers who
  /// did not.
  static const Map<String, Color> backgrounds = {
    'black': PrivioColors.background,
    'charcoal': Color(0xFF121212),
    'midnight': Color(0xFF0A1020),
  };

  /// The accent to draw with, falling back to Privio's own.
  static Color accentFor(String? name) => accents[name] ?? PrivioColors.accent;

  static Color backgroundFor(String? name) =>
      backgrounds[name] ?? PrivioColors.background;
}
