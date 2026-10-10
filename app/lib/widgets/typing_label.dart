import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// "typing…", with the dots alive.
///
/// [text] is the translated sentence, ellipsis and all. The ellipsis is
/// replaced by three dots that rise and fall in turn — the one thing in the
/// app that moves on its own, and only for as long as somebody is actually
/// typing. With "Reduce motion" on, the sentence is shown exactly as written.
class TypingLabel extends StatefulWidget {
  const TypingLabel(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<TypingLabel> createState() => _TypingLabelState();
}

class _TypingLabelState extends State<TypingLabel> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// The sentence without its trailing ellipsis, in any of the ways the
  /// translations write one.
  String get _words => widget.text.replaceFirst(RegExp(r'\s*(…|\.\.\.)\s*$'), '');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PrivioMotion.reduced(context)) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    if (PrivioMotion.reduced(context)) return Text(widget.text, style: style);

    final size = (style.fontSize ?? 12) * 0.32;
    return Semantics(
      // Read as the sentence, not as a word and three shapes.
      label: widget.text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_words, style: style),
          SizedBox(width: size),
          for (var i = 0; i < 3; i++)
            AnimatedBuilder(
              animation: _beat,
              builder: (context, _) {
                // Each dot a third of a beat behind the one before it.
                final phase = (_beat.value - i / 3) % 1;
                final lift = math.max(0.0, math.sin(phase * 2 * math.pi));
                return Padding(
                  padding: EdgeInsets.only(right: size * 0.5, bottom: size * 0.6),
                  child: Transform.translate(
                    offset: Offset(0, -lift * size * 1.2),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: style.color?.withValues(alpha: 0.55 + 0.45 * lift),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
