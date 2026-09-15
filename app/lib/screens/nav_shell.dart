import 'package:flutter/material.dart';

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

class _NavShellState extends State<NavShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = NavShell.destinations;
    final text = AppText.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (final destination in destinations) destination.builder(context)],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (index) {
            setState(() => _index = index);
            // Told rather than inferred, so a screen the stack is keeping
            // alive can refresh what it read on the way in.
            PrivioScope.of(context).selectedTab = index;
          },
          items: [
            for (final destination in destinations)
              BottomNavigationBarItem(
                icon: Icon(destination.icon),
                activeIcon: Icon(destination.activeIcon),
                label: destination.label(text),
              ),
          ],
        ),
      ),
    );
  }
}
