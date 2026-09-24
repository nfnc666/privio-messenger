import 'package:flutter/material.dart';

import '../theme/accent.dart';

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

  /// The lock-up's symbol alone, and its word alone, on the same canvas as
  /// [wordmark].
  ///
  /// Two files rather than one because the screens that draw this tint the
  /// symbol with the account's accent and leave "Privio" white, and a single
  /// flattened image cannot be told apart that way — a colour filter over it
  /// would recolour the text too. Both are cut to the combined bounding box by
  /// `tools/generate_brand_assets.py`, so stacking them is the flat artwork
  /// again, at the same size and spacing.
  static const String wordmarkSymbol = 'assets/logo/privio_wordmark_symbol.png';
  static const String wordmarkWord = 'assets/logo/privio_wordmark_word.png';

  /// What the lock-up measures, width against height. Read off the artwork
  /// rather than guessed, so a re-cut asset does not silently distort.
  static const double wordmarkAspect = 1024 / 303;
}

/// Paints [child] in [colour], keeping every edge it already had.
///
/// `srcIn` against artwork that is one flat ink is an exact recolour: the alpha
/// channel — the shape, and the softness of its antialiasing — is what decides
/// coverage, and only the ink changes. It is what lets the mark follow the
/// account's accent without a second cut of the artwork per colour, and without
/// the shape moving by a pixel.
///
/// This is *not* the home-screen icon. That is a resource the launcher reads
/// and it stays Privio green whatever is chosen here; see `docs/app-icon.md`.
class _Tinted extends StatelessWidget {
  const _Tinted({required this.colour, required this.child});

  final Color colour;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: ColorFilter.mode(colour, BlendMode.srcIn),
        child: child,
      );
}

/// The Privio mark at a given size, optionally with the accent bloom behind it
/// that the splash and loading screens use.
///
/// Drawn in the account's accent, from the theme — so the splash, the lock
/// screen and every loading view are the colour somebody chose rather than the
/// colour the artwork was cut in.
class PrivioMark extends StatelessWidget {
  const PrivioMark({super.key, this.size = 96, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final accent = context.accents.accent;
    final logo = _Tinted(
      colour: accent,
      child: Image.asset(
        PrivioLogoAsset.mark,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );

    if (!glow) return logo;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.26),
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

    final height = width / PrivioLogoAsset.wordmarkAspect;
    final accent = context.accents.accent;

    Widget layer(String asset) => Image.asset(
          asset,
          height: height,
          width: width,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        );

    // The word stays white and the symbol takes the accent. Same canvas, same
    // box, so this is the flat lock-up with one of its two inks replaced —
    // nothing is measured here and nothing can drift.
    final logo = SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          layer(PrivioLogoAsset.wordmarkWord),
          _Tinted(colour: accent, child: layer(PrivioLogoAsset.wordmarkSymbol)),
        ],
      ),
    );

    if (!glow) return logo;

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: markSize * 0.55,
            spreadRadius: markSize * 0.01,
          ),
        ],
      ),
      child: logo,
    );
  }
}
