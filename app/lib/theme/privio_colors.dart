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
