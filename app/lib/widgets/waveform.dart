import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// The bars of a voice message.
///
/// Drawn from the amplitudes the *recorder* measured, not from decoding the
/// audio: the shape is available before a byte has been downloaded, and nothing
/// has to decode a file to draw it.
class Waveform extends StatelessWidget {
  const Waveform({
    required this.bars,
    super.key,
    this.progress = 0,
    this.playedColor = PrivioColors.accent,
    this.pendingColor = PrivioColors.textTertiary,
    this.barWidth = 3,
    this.gap = 2,
    this.height = 28,
  });

  /// 0..1 per bar.
  final List<double> bars;

  /// How far playback has got, 0..1. Bars behind it are drawn in [playedColor].
  final double progress;

  final Color playedColor;
  final Color pendingColor;
  final double barWidth;
  final double gap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(
          bars: bars,
          progress: progress.clamp(0.0, 1.0),
          playedColor: playedColor,
          pendingColor: pendingColor,
          barWidth: barWidth,
          gap: gap,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.pendingColor,
    required this.barWidth,
    required this.gap,
  });

  final List<double> bars;
  final double progress;
  final Color playedColor;
  final Color pendingColor;
  final double barWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;

    // Draw as many bars as fit, sampling the series rather than squeezing it:
    // a squeezed waveform stops looking like the sound it came from.
    final slot = barWidth + gap;
    final count = (size.width / slot).floor().clamp(1, bars.length);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < count; i++) {
      final value = bars[(i * bars.length / count).floor().clamp(0, bars.length - 1)];
      // A floor, so silence still reads as a waveform rather than a gap.
      final barHeight = (size.height * (0.12 + 0.88 * value)).clamp(2.0, size.height);
      final x = i * slot + barWidth / 2;
      final centre = size.height / 2;
      paint.color = (i / count) <= progress ? playedColor : pendingColor;
      canvas.drawLine(
        Offset(x, centre - barHeight / 2),
        Offset(x, centre + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.playedColor != playedColor ||
      old.pendingColor != pendingColor;
}

/// How a duration reads on a voice message: "0:07", "1:42".
String formatVoiceDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
