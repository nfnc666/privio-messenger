import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/privio_colors.dart';
import 'account_screen.dart';
import 'calls_screen.dart';
import 'channels_screen.dart';
import 'chats_screen.dart';
import 'contacts_screen.dart';
import '../core/app_state.dart';
import '../l10n/app_localizations.dart';

/// One destination in the bottom bar.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.builder,
  });

  /// Read from the translations rather than stored, because a static list
  /// built once at start-up would keep whichever language was in force then.
  final String Function(AppText) label;
  final IconData icon;
  final IconData activeIcon;
  final WidgetBuilder builder;
}

/// The tabbed shell.
///
/// The five tabs from the brief. The destinations are data, so shipping a new
/// tab is one entry here rather than a rewrite. Screens keep their state across
/// tab switches via [IndexedStack].
class NavShell extends StatefulWidget {
  const NavShell({super.key});

  static final List<NavDestination> destinations = [
    NavDestination(
      label: (text) => text.navChats,
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      builder: (_) => const ChatsScreen(),
    ),
    NavDestination(
      label: (text) => text.navChannels,
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign_rounded,
      builder: (_) => const ChannelsScreen(),
    ),
    NavDestination(
      label: (text) => text.navCalls,
      icon: Icons.call_outlined,
      activeIcon: Icons.call_rounded,
      builder: (_) => const CallsScreen(),
    ),
    NavDestination(
      label: (text) => text.navContacts,
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      builder: (_) => const ContactsScreen(),
    ),
    NavDestination(
      label: (text) => text.navAccount,
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      builder: (_) => const AccountScreen(),
    ),
  ];

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> with SingleTickerProviderStateMixin {
  int _index = 0;

  /// A tab arrives by fading up from the black behind it as it rises into
  /// place. A cut between two lists that look alike reads as nothing having
  /// happened.
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: PrivioMotion.standard,
    value: 1,
  );
  late final CurvedAnimation _arriving = CurvedAnimation(
    parent: _arrive,
    curve: PrivioMotion.enter,
  );

  @override
  void dispose() {
    _arriving.dispose();
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = NavShell.destinations;
    final text = AppText.of(context);

    return Scaffold(
      body: FadeTransition(
        opacity: _arriving,
        child: AnimatedBuilder(
          animation: _arriving,
          builder: (context, child) => Transform.translate(
            // With motion reduced the fade stays and the rise goes.
            offset: Offset(
              0,
              PrivioMotion.reduced(context) ? 0 : (1 - _arriving.value) * PrivioMotion.rise,
            ),
            child: child,
          ),
          child: IndexedStack(
            index: _index,
            children: [for (final destination in destinations) destination.builder(context)],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (index) {
            if (index != _index) {
              _arrive.duration =
                  PrivioMotion.reduced(context) ? PrivioMotion.quick : PrivioMotion.standard;
              _arrive.forward(from: 0);
            }
            setState(() => _index = index);
            // Told rather than inferred, so a screen the stack is keeping
            // alive can refresh what it read on the way in.
            PrivioScope.of(context).selectedTab = index;
          },
          items: [
            for (final destination in destinations)
              BottomNavigationBarItem(
                icon: Icon(destination.icon),
                // Pops as it is chosen, so the eye goes to where it is now.
                activeIcon: _Chosen(child: Icon(destination.activeIcon)),
                label: destination.label(text),
              ),
          ],
        ),
      ),
    );
  }
}

/// An icon that grows into place as its tab is chosen — or simply is there,
/// when the device asks for less motion.
class _Chosen extends StatelessWidget {
  const _Chosen({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (PrivioMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: PrivioMotion.standard,
      curve: PrivioMotion.pop,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
