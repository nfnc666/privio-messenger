import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// The Privio mark: a white speech bubble around a white padlock.
///
/// Drawn rather than loaded from the PNG so it stays crisp at every size and
/// can sit on any background. `assets/logo/` holds the master artwork for the
/// splash, the About screen and the store listings.
class PrivioMark extends StatelessWidget {
  const PrivioMark({super.key, this.size = 96, this.glow = false});

  final double size;

  /// The accent bloom used behind the mark on the splash and loading screens.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: PrivioColors.accent.withValues(alpha: 0.28),
                    blurRadius: size * 0.55,
                    spreadRadius: size * 0.04,
                  ),
                ]
              : null,
        ),
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2;

    final white = Paint()..color = PrivioColors.textPrimary;
    final ring = Paint()
      ..color = PrivioColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // The tail first, so the ring stroke lands on top of its base and the two
    // read as one continuous shape.
    Offset onCircle(double degrees) {
      final radians = degrees * math.pi / 180;
      return centre + Offset(math.cos(radians) * radius, math.sin(radians) * radius);
    }

    final tip = centre +
        Offset(
          math.cos(147 * math.pi / 180) * radius * 1.46,
          math.sin(147 * math.pi / 180) * radius * 1.46,
        );
    final tail = Path()
      ..moveTo(onCircle(112).dx, onCircle(112).dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(onCircle(172).dx, onCircle(172).dy)
      ..close();
    canvas.drawPath(tail, white);

    canvas.drawCircle(centre, radius, ring);

    // Punch the bubble interior back out, leaving the tail solid outside it.
    canvas.drawCircle(
      centre,
      radius - stroke / 2,
      Paint()..color = PrivioColors.background,
    );

    // Padlock body.
    final bodyWidth = size.width * 0.40;
    final bodyHeight = size.height * 0.30;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centre.dx, centre.dy + size.height * 0.09),
        width: bodyWidth,
        height: bodyHeight,
      ),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(body, white);

    // Shackle.
    final shackleWidth = bodyWidth * 0.58;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centre.dx, centre.dy - size.height * 0.07),
        width: shackleWidth,
        height: shackleWidth,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = PrivioColors.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.9
        ..strokeCap = StrokeCap.round,
    );

    // Keyhole.
    canvas.drawCircle(
      Offset(centre.dx, centre.dy + size.height * 0.06),
      size.width * 0.045,
      Paint()..color = PrivioColors.background,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo plus wordmark, as shown on the splash screen.
class PrivioWordmark extends StatelessWidget {
  const PrivioWordmark({super.key, this.markSize = 96, this.glow = true});

  final double markSize;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrivioMark(size: markSize, glow: glow),
        const SizedBox(height: 20),
        Text(
          'Privio',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}
