import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Fades its child in while it moves into place, once, when [play] is true.
///
/// By default it rises from [PrivioMotion.rise] below; [from] moves it in from
/// elsewhere — a message from its own side of the chat — and [scale] grows it
/// in from a little smaller.
///
/// Built the same way whether or not it plays, so a widget that stops being
/// new is not torn down and rebuilt underneath — a photo bubble that lost its
/// state at the end of its own entrance would fetch its picture twice. When it
/// does not play, it starts finished and costs nothing: a fade at full opacity
/// paints its child directly.
///
/// [delay] staggers a group of these, as on the welcome screen. When the
/// device asks for less motion, nothing moves or grows: it fades in, quickly.
class Appear extends StatefulWidget {
  const Appear({
    required this.child,
    super.key,
    this.play = true,
    this.delay = Duration.zero,
    this.duration = PrivioMotion.standard,
    this.from = const Offset(0, PrivioMotion.rise),
    this.scale = 1,
  });

  final Widget child;
  final bool play;
  final Duration delay;
  final Duration duration;

  /// Where it starts, relative to where it ends, in logical pixels.
  final Offset from;

  /// How large it starts, relative to its size; 1 does not grow at all.
  final double scale;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.play ? 0 : 1,
  );
  late CurvedAnimation _progress;

  bool _started = false;
  bool _still = false;

  CurvedAnimation _curve(Duration delay, Duration duration) {
    final total = delay + duration;
    _controller.duration = total;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: PrivioMotion.enter),
    );
  }

  @override
  void initState() {
    super.initState();
    _progress = _curve(widget.delay, widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.play) return;
    _started = true;
    if (PrivioMotion.reduced(context)) {
      // A fade, without the wait: a stagger is movement in time.
      _still = true;
      _progress.dispose();
      _progress = _curve(Duration.zero, PrivioMotion.quick);
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return FadeTransition(opacity: _progress, child: widget.child);
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final left = 1 - _progress.value;
        return FadeTransition(
          opacity: _progress,
          child: Transform.translate(
            offset: widget.from * left,
            child: widget.scale == 1
                ? child
                : Transform.scale(scale: 1 - (1 - widget.scale) * left, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Which rows of a list have come in already.
///
/// Rows that the list did not hold before arrive together, a beat apart from
/// the top down: all of them the first time the list has anything in it, and
/// later only the new ones — a chat that just started. Scrolling a row out and
/// back, or the list rebuilding, plays nothing again, and a row further down
/// that was not on screen when it arrived does not play when it is scrolled to.
///
/// One per list, kept in the screen's state. [see] is told every id the list
/// holds on each build, and [wrap] wraps each row.
class Entrances {
  final Set<Object> _known = {};
  final Map<Object, int> _arriving = {};

  /// The most rows that wait for the ones above them; any further down arrive
  /// with the last of these, so a long list does not keep the eye waiting.
  static const int _wave = 8;

  /// Records the list's ids; any not seen before arrive, in this order.
  void see(Iterable<Object> ids) {
    var order = 0;
    for (final id in ids) {
      if (_known.add(id)) _arriving[id] = order++;
    }
    if (order > 0) {
      // Whatever was not on screen this frame has missed its entrance.
      WidgetsBinding.instance.addPostFrameCallback((_) => _arriving.clear());
    }
  }

  /// The row with [id], arriving if it is new.
  Widget wrap({required Object id, required Widget child}) {
    final order = _arriving.remove(id);
    return Appear(
      key: ValueKey(id),
      play: order != null,
      delay: PrivioMotion.stagger * math.min(order ?? 0, _wave),
      child: child,
    );
  }
}
