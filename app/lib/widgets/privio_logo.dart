import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// Asset paths for the brand marks.
///
/// These are the supplied artwork, keyed off their black background so the same
/// file works on any surface. Masters live in `design/logo/`. Nothing in the app
/// redraws the logo — it is used as given.
abstract final class PrivioLogoAsset {
  /// The speech bubble with the padlock, no wordmark.
  static const String mark = 'assets/logo/privio_mark.png';

  /// The mark stacked above the "Privio" wordmark.
  static const String wordmark = 'assets/logo/privio_wordmark.png';
}

/// The Privio mark at a given size, optionally with the accent bloom behind it
/// that the splash and loading screens use.
class PrivioMark extends StatelessWidget {
  const PrivioMark({super.key, this.size = 96, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      PrivioLogoAsset.mark,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );

    if (!glow) return logo;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: PrivioColors.accent.withValues(alpha: 0.26),
            blurRadius: size * 0.5,
            spreadRadius: size * 0.02,
          ),
        ],
      ),
      child: logo,
    );
  }
}

/// The full lock-up: mark above the wordmark, as on the splash screen.
class PrivioWordmark extends StatelessWidget {
  const PrivioWordmark({super.key, this.markSize = 96, this.glow = true});

  /// Sized by the mark so callers keep using the same measurement; the artwork
  /// carries the wordmark's own proportions.
  final double markSize;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      PrivioLogoAsset.wordmark,
      width: markSize * 1.32,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );

    if (!glow) return logo;

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: PrivioColors.accent.withValues(alpha: 0.22),
            blurRadius: markSize * 0.55,
            spreadRadius: markSize * 0.01,
          ),
        ],
      ),
      child: logo,
    );
  }
}
