import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_icon.dart';
import '../core/app_state.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../l10n/app_localizations.dart';
import '../widgets/privio_logo.dart';

/// Screens 1 and 2: the splash, then the secure-initialisation progress.
///
/// The two are one widget because they are one moment for the user — the mark
/// stays put while the tagline gives way to the progress bar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final initialising = state.stage == AppStage.initialising;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _CodeRainPainter(_controller.value, context.accents.accent),
            ),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // The artwork this device chose, when it chose one. The same
                // picture the home screen is wearing, so the tap and the first
                // frame are one continuous thing — which is what the launch
                // screens themselves cannot do, because they are drawn before
                // any of this runs. See docs/app-icon.md.
                if (state.appIcon.style case final style?)
                  _StyledMark(style: style)
                else
                  const PrivioWordmark(markSize: 64),
                const SizedBox(height: PrivioSpacing.lg),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: initialising
                      ? _InitialisingIndicator(progress: state.initProgress)
                      : const _Tagline(),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chosen artwork over the word, in place of the tinted lock-up.
///
/// Not tinted, and that is the point: these four are whole pictures rather than
/// hues of the mark, so a colour filter over one would flatten a camouflage
/// plate or a glow into a single ink. The word below it stays white, as it is
/// in the lock-up, and the glow around it keeps the account's accent — the
/// artwork is the device's choice and the accent is the account's, and this is
/// the one place both are on screen at once.
class _StyledMark extends StatelessWidget {
  const _StyledMark({required this.style});

  final AppIconStyle style;

  @override
  Widget build(BuildContext context) {
    final accent = context.accents.accent;
    const size = 96.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.22),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: size * 0.4,
              ),
            ],
          ),
          child: ClipRRect(
            // The radius a home-screen icon is masked to, roughly, so this
            // reads as the icon rather than as a photograph of one.
            borderRadius: BorderRadius.circular(size * 0.22),
            child: Image.asset(
              style.preview,
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(height: PrivioSpacing.md),
        Image.asset(
          PrivioLogoAsset.wordmarkWord,
          height: 22,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          AppText.of(context).splashTagline,
          style: theme.textTheme.bodyMedium?.copyWith(color: context.accents.accent),
        ),
        const SizedBox(height: PrivioSpacing.xs),
        Text(
          AppText.of(context).splashPromise,
          style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
        ),
      ],
    );
  }
}

class _InitialisingIndicator extends StatelessWidget {
  const _InitialisingIndicator({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          AppText.of(context).splashInitialising,
          style: theme.textTheme.bodySmall?.copyWith(color: context.accents.accent),
        ),
        const SizedBox(height: PrivioSpacing.md),
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(PrivioRadius.pill),
            // The fill colour is the theme's — `progressIndicatorTheme` is
            // built from the same accent as everything else here, so this bar
            // needs no colour of its own and must not grow one: a second place
            // to set it is a second place for it to be wrong.
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: PrivioColors.surfaceHigh,
            ),
          ),
        ),
        const SizedBox(height: PrivioSpacing.sm),
        Text('${(progress * 100).round()}%', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// The faint green code rain behind the splash, as in the mockups. Purely
/// decorative: deterministic, cheap, and never touches real data.
class _CodeRainPainter extends CustomPainter {
  _CodeRainPainter(this.phase, this.accent);

  final double phase;

  /// Passed in rather than read from a constant: a painter has no context, and
  /// the rain behind an accent-coloured mark must be the same colour as it.
  final Color accent;

  static const int _columns = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final columnWidth = size.width / _columns;
    final paint = Paint()..strokeWidth = 1.4..strokeCap = StrokeCap.round;

    for (var column = 0; column < _columns; column++) {
      final speed = 0.4 + random.nextDouble();
      final offset = random.nextDouble();
      final headY = ((phase * speed + offset) % 1.2) * size.height;
      final x = columnWidth * (column + 0.5);

      for (var i = 0; i < 14; i++) {
        final y = headY - i * 16;
        if (y < 0 || y > size.height) continue;
        paint.color = accent.withValues(alpha: 0.16 * (1 - i / 14));
        canvas.drawLine(Offset(x, y), Offset(x, y + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CodeRainPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.accent != accent;
}
