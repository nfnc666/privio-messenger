import 'package:flutter/widgets.dart';

/// How Privio moves. See `docs/design-system.md`, "Motion".
///
/// Motion here says one of three things — this just arrived, this changed,
/// you are somewhere else now — and is over before anybody waits for it.
/// Nothing loops except what is live (somebody typing, a recording), and
/// nothing is decoration.
///
/// The first version of these values was too quiet to be seen: a tenth of a
/// second and ten pixels read on a phone as no animation at all. These are
/// long and far enough to notice, and still short enough not to wait for.
///
/// **The device decides first.** Somebody who turned on "Reduce motion" (iOS)
/// or "Remove animations" (Android) gets nothing that moves — no rising, no
/// sliding, no growing — and a short fade in its place, which is what Apple's
/// guidance asks for. [reduced] tells a widget which of the two to do.
abstract final class PrivioMotion {
  /// A control changing state: a tick, a button swapping, a count. Also how
  /// long the fade is that stands in for movement when motion is reduced.
  static const Duration quick = Duration(milliseconds: 220);

  /// Something arriving: a message, a row, an empty state, a tab.
  static const Duration standard = Duration(milliseconds: 340);

  /// The few entrances worth a moment: the welcome screen.
  static const Duration gentle = Duration(milliseconds: 600);

  /// How far apart the rows of a list arrive when it first appears.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Things coming in decelerate; they arrive rather than stop.
  static const Curve enter = Curves.easeOutCubic;

  /// Things that pop overshoot a little and settle.
  static const Curve pop = Curves.easeOutBack;

  /// How far, in logical pixels, something rises as it arrives.
  static const double rise = 24;

  /// How far a message travels in from its own side of the chat.
  static const double travel = 28;

  /// True when the device asks for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The transition for an [AnimatedSwitcher] on a small control: the new
  /// state grows in from smaller while the old one fades — or, with motion
  /// reduced, only the fade.
  static AnimatedSwitcherTransitionBuilder swap(BuildContext context) =>
      reduced(context) ? _fade : _popIn;

  static Widget _fade(Widget child, Animation<double> animation) =>
      FadeTransition(opacity: animation, child: child);

  static Widget _popIn(Widget child, Animation<double> animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.4, end: 1).animate(
            CurvedAnimation(parent: animation, curve: pop),
          ),
          child: child,
        ),
      );
}
