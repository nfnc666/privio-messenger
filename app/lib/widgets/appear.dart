import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Fades its child in while it rises a few pixels, once, when [play] is true.
///
/// Built the same way whether or not it plays, so a widget that stops being
/// new is not torn down and rebuilt underneath — a photo bubble that lost its
/// state at the end of its own entrance would fetch its picture twice. When it
/// does not play, it starts finished and costs nothing: a fade at full opacity
/// paints its child directly.
///
/// [delay] staggers a group of these, as on the welcome screen. Nothing moves
/// when the device asks for less motion.
class Appear extends StatefulWidget {
  const Appear({
    required this.child,
    super.key,
    this.play = true,
    this.delay = Duration.zero,
    this.duration = PrivioMotion.standard,
  });

  final Widget child;
  final bool play;
  final Duration delay;
  final Duration duration;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
    value: widget.play ? 0 : 1,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: PrivioMotion.enter,
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.play) return;
    _started = true;
    if (PrivioMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        builder: (context, child) => FadeTransition(
          opacity: _progress,
          child: Transform.translate(
            offset: Offset(0, (1 - _progress.value) * PrivioMotion.rise),
            child: child,
          ),
        ),
        child: widget.child,
      );
}
