import 'package:flutter/widgets.dart';

/// How Privio moves. See `docs/design-system.md`, "Motion".
///
/// Short and quiet on purpose. Motion here says one of three things — this
/// just arrived, this changed, you are somewhere else now — and is over before
/// anybody waits for it. Nothing loops except what is live (somebody typing, a
/// recording), and nothing is decoration.
///
/// **The device decides first.** Somebody who turned on "Reduce motion" (iOS)
/// or "Remove animations" (Android) gets every change at once, with no
/// movement at all: [of] returns zero for them, and [reduced] tells a widget to
/// skip the movement entirely rather than play it fast.
abstract final class PrivioMotion {
  /// A control changing state: a tick, a button swapping, a count.
  static const Duration quick = Duration(milliseconds: 160);

  /// Something arriving: a message, an empty state, a tab.
  static const Duration standard = Duration(milliseconds: 240);

  /// The few entrances worth a moment: the welcome screen.
  static const Duration gentle = Duration(milliseconds: 420);

  /// Things coming in decelerate; they arrive rather than stop.
  static const Curve enter = Curves.easeOutCubic;

  /// How far, in logical pixels, something rises as it arrives.
  static const double rise = 10;

  /// True when the device asks for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or none at all when the device asks for less motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// The transition every [AnimatedSwitcher] for a small control uses: the new
  /// state grows in from a little smaller while the old one fades.
  static Widget popIn(Widget child, Animation<double> animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      );
}
