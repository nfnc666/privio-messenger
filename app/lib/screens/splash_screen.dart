import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
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
            builder: (context, _) => CustomPaint(painter: _CodeRainPainter(_controller.value)),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
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

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Secure Messenger',
          style: theme.textTheme.bodyMedium?.copyWith(color: PrivioColors.accent),
        ),
        const SizedBox(height: PrivioSpacing.xs),
        Text(
          'Encrypted. Private. Yours.',
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
          'Initializing secure environment',
          style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.accent),
        ),
        const SizedBox(height: PrivioSpacing.md),
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(PrivioRadius.pill),
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
  _CodeRainPainter(this.phase);

  final double phase;
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
        paint.color = PrivioColors.accent.withValues(alpha: 0.16 * (1 - i / 14));
        canvas.drawLine(Offset(x, y), Offset(x, y + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CodeRainPainter oldDelegate) => oldDelegate.phase != phase;
}
