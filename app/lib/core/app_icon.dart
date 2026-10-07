import 'package:flutter/foundation.dart';

import '../theme/accent.dart';

/// The colours the home-screen icon comes in.
///
/// The same eight the accent menu offers, by the same names, because the two
/// settings sit next to each other and a colour called one thing in one and
/// another thing in the other would be two features pretending to be unrelated.
/// The codes match [AppAccent.code], which is what lets "use my accent colour"
/// be a lookup rather than a table.
///
/// The stored name is what the platform and the keystore hold, so the order of
/// this enum may change and the wire may not.
enum AppIconColour {
  /// The delivered artwork, untouched.
  ///
  /// Not a recolour of anything: the brand mark is `#01F47B`, which is not the
  /// accent green, and "restore the original" has to return the original file
  /// rather than a close approximation of it.
  green('green'),
  blue('blue'),
  teal('teal'),
  purple('purple'),
  pink('pink'),
  red('red'),
  orange('orange'),
  yellow('yellow');

  const AppIconColour(this.code);

  final String code;

  /// What the app ships with, and what "restore the default" returns to.
  static const AppIconColour fallback = AppIconColour.green;

  static AppIconColour? forCode(String? code) {
    if (code == null) return null;
    for (final colour in AppIconColour.values) {
      if (colour.code == code) return colour;
    }
    return null;
  }

  /// The icon that matches an accent, for "use my accent colour".
  static AppIconColour forAccent(AppAccent accent) =>
      forCode(accent.code) ?? AppIconColour.fallback;

  /// The accent this icon colour is drawn in, for the preview swatch.
  AppAccent get accent => AppAccent.forCode(code) ?? AppAccent.fallback;
}

/// The artwork styles, which are **not** colours of the same picture.
///
/// The eight [AppIconColour] variants are one delivered mark with its hue
/// shifted, which works because that artwork is two tones. These four are their
/// own pictures — a camouflage plate, the same with a shield, neon glass, neon
/// glass over a mesh — and nothing about them can be derived from anything
/// else. So they ship as their own icon sets and are picked from their own
/// thumbnails rather than from a tinted preview.
///
/// The code is the wire name: it reaches the keystore, the Android alias and
/// the iOS alternate icon, so it may not change once a build has shipped.
enum AppIconStyle {
  camo('camo', 'assets/launcher_styles/camo.png'),
  camoShield('camo_shield', 'assets/launcher_styles/camo_shield.png'),
  neon('neon', 'assets/launcher_styles/neon.png'),
  neonMesh('neon_mesh', 'assets/launcher_styles/neon_mesh.png');

  const AppIconStyle(this.code, this.preview);

  final String code;

  /// The thumbnail the picker draws. The real artwork at 256px, not a tint:
  /// there is no single colour these could be tinted from.
  final String preview;

  static AppIconStyle? forCode(String? code) {
    if (code == null) return null;
    for (final style in AppIconStyle.values) {
      if (style.code == code) return style;
    }
    return null;
  }
}

/// What the launcher should be showing — one value, so it cannot be two things.
///
/// The disguise and the icon colour both want the same slot on the home screen,
/// and the precedence between them is a rule rather than a race: the disguise
/// wins while it is on, because somebody who turned it on is relying on what
/// the home screen shows. Keeping that rule here, in one value the platform is
/// simply handed, is what makes it testable without a launcher.
@immutable
class LauncherEntry {
  const LauncherEntry.icon(this.colour)
      : disguised = false,
        style = null;

  /// One of the artwork styles. The colour is the fallback and means nothing
  /// here: a style is a whole picture, not a hue applied to one.
  const LauncherEntry.styled(AppIconStyle this.style)
      : colour = AppIconColour.green,
        disguised = false;

  const LauncherEntry.calculator()
      : colour = AppIconColour.green,
        style = null,
        disguised = true;

  /// The colour, meaningless while [disguised] or while [style] is set.
  final AppIconColour colour;

  /// The artwork style, when one was chosen instead of a colour.
  final AppIconStyle? style;

  /// True for the calculator entry, whatever is stored underneath it.
  final bool disguised;

  /// The name the platform channel speaks. Stable; the enums are not.
  String get wireName {
    if (disguised) return 'calculator';
    return style?.code ?? colour.code;
  }

  static LauncherEntry? forWireName(String? name) {
    if (name == null) return null;
    if (name == 'calculator') return const LauncherEntry.calculator();
    final style = AppIconStyle.forCode(name);
    if (style != null) return LauncherEntry.styled(style);
    final colour = AppIconColour.forCode(name);
    return colour == null ? null : LauncherEntry.icon(colour);
  }

  @override
  bool operator ==(Object other) =>
      other is LauncherEntry &&
      other.colour == colour &&
      other.style == style &&
      other.disguised == disguised;

  @override
  int get hashCode => Object.hash(colour, style, disguised);

  @override
  String toString() => 'LauncherEntry($wireName)';
}
