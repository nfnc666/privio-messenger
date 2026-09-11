import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// Asset paths for the brand marks.
///
/// Both are cut from the delivered artwork in `design/logo/` by
/// `tools/generate_brand_assets.py`; nothing in the app redraws the logo. They
/// carry a real alpha channel, so they sit on any surface without a plate
/// behind them.
abstract final class PrivioLogoAsset {
  /// The green mark on its own — the P whose counter is a speech bubble.
  static const String mark = 'assets/logo/privio_mark.png';

  /// The horizontal lock-up: the mark, then "Privio".
  ///
  /// The white-text cut, because every surface in this app is black. A light
  /// surface wants `design/logo/privio-wordmark-light.png` instead, which is
  /// where the README and the store listings take theirs from.
  static const String wordmark = 'assets/logo/privio_wordmark.png';

  /// What the lock-up measures, width against height. Read off the artwork
  /// rather than guessed, so a re-cut asset does not silently distort.
  static const double wordmarkAspect = 1024 / 303;
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

/// The full lock-up: the mark, then "Privio" beside it.
///
/// The artwork is horizontal, so [markSize] is the *height* and the width
/// follows from the aspect ratio. That is a real change in shape — the previous
/// lock-up stacked the mark above the word and was barely wider than it was
/// tall, so a height that used to measure 137 logical pixels across now
/// measures 351. Hence the clamp below: on a 320-point phone that would run off
/// both edges, and a logo that overflows is worse than a slightly smaller one.
class PrivioWordmark extends StatelessWidget {
  const PrivioWordmark({
    super.key,
    this.markSize = 64,
    this.glow = true,
    this.maxWidthFraction = 0.7,
  });

  /// The height of the lock-up.
  final double markSize;
  final bool glow;

  /// How much of the available width the lock-up may take before it is scaled
  /// down to fit. Only bites on narrow screens.
  final double maxWidthFraction;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width * maxWidthFraction;
    final wanted = markSize * PrivioLogoAsset.wordmarkAspect;
    final width = wanted > available ? available : wanted;

    final logo = Image.asset(
      PrivioLogoAsset.wordmark,
      height: width / PrivioLogoAsset.wordmarkAspect,
      width: width,
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
