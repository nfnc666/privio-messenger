import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/screens/account_screen.dart';
import 'package:privio/screens/invite_screen.dart';
import 'package:privio/screens/privacy_screen.dart';
import 'package:privio/screens/settings_screen.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_colors.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/settings_row.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'widget_test.dart' show quietServices, wrap;

/// Where the options are, and that they can be found.
///
/// Settings was one list of twelve rows in the order they were built, reached
/// through a small gear in the corner of the Account tab, with Backup in both
/// places. It is grouped and named now, and opened from a row anybody can see.
Future<AppState> _state() async {
  final state = AppState(services: await quietServices(), store: InMemorySecureStore());
  await state.initialise();
  return state;
}

/// Tall enough for the whole screen, so the order on it can be read off.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

double _y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('settings are grouped, and every row is in its group', (tester) async {
    _tallScreen(tester);
    final state = await _state();
    await tester.pumpWidget(wrap(const SettingsScreen(), state));
    await tester.pumpAndSettle();

    final security = _y(tester, 'SECURITY & ACCOUNT');
    final chats = _y(tester, 'CHATS & MEDIA');
    final look = _y(tester, 'LOOK & LANGUAGE');
    expect(security, lessThan(chats));
    expect(chats, lessThan(look));

    void within(String row, double from, double to) {
      final at = _y(tester, row);
      expect(at, greaterThan(from), reason: '$row is under its caption');
      expect(at, lessThan(to), reason: '$row is above the next caption');
    }

    for (final row in ['Privacy & Security', 'Devices', 'Backup']) {
      within(row, security, chats);
    }
    for (final row in ['Notifications', 'Data and Storage', 'Stickers & Emoji']) {
      within(row, chats, look);
    }
    for (final row in ['Appearance', 'Language']) {
      within(row, look, double.infinity);
    }
    expect(_y(tester, 'About Privio'), greaterThan(_y(tester, 'Language')),
        reason: 'and the app itself last');

    // Each option once: a row in two groups is two places to wonder which.
    for (final row in ['Privacy & Security', 'Backup', 'Notifications', 'Language']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('the account tab shows the way into settings, above the profile', (tester) async {
    _tallScreen(tester);
    final state = await _state();
    await tester.pumpWidget(wrap(const AccountScreen(), state));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Settings'), findsNothing, reason: 'no gear hiding in the corner');
    expect(find.text('Settings'), findsOneWidget);
    expect(_y(tester, 'Settings'), lessThan(_y(tester, 'PROFILE')),
        reason: 'the options before the profile details nobody changes often');
    expect(_y(tester, 'PROFILE'), lessThan(_y(tester, 'Username')));
    expect(find.text('Backup'), findsNothing, reason: 'Backup is in Settings, once');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the address is on top of the account tab, with its link and its code',
      (tester) async {
    _tallScreen(tester);
    final state = await _state();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(wrap(const AccountScreen(), state));
    await tester.pumpAndSettle();

    // Under the picture and before everything else, as in the messengers
    // built around privacy. It was small print under the name, and the way
    // to the link and the code was the fifth row down.
    final address = find.textContaining(RegExp(r'^@'));
    expect(address, findsOneWidget, reason: 'the address once, on its card');
    final username = tester.widget<Text>(address).data!.substring(1);
    expect(_y(tester, 'YOUR ADDRESS'), lessThan(_y(tester, 'Settings')));
    expect(tester.getTopLeft(address).dy, lessThan(_y(tester, 'Settings')));
    expect(find.byIcon(Icons.qr_code_rounded), findsOneWidget,
        reason: 'the code is reached from the card, not from a row as well');

    // The link, not the bare name: the link is what opens Privio on the other
    // phone. And the same link the invite screen hands out.
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, [InviteScreen.linkFor(username)]);
    expect(find.text('Invite link copied'), findsOneWidget);

    await tester.tap(find.text('QR Code'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteScreen), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget, reason: 'it opens on the code it named');
  });

  testWidgets("a row's icon sits on a tile of the accent, and a disabled one is grey",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: const Scaffold(
          body: SettingsSection(
            children: [
              SettingsRow(icon: Icons.lock_outline, label: 'Open'),
              SettingsRow(icon: Icons.key_outlined, label: 'Shut', enabled: false),
            ],
          ),
        ),
      ),
    );
    final accents = tester.element(find.text('Open')).accents;

    Color tileOf(IconData icon) {
      final tile = find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)).first;
      return (tester.widget<Container>(tile).decoration! as BoxDecoration).color!;
    }

    expect(tileOf(Icons.lock_outline), accents.surface);
    expect(tester.widget<Icon>(find.byIcon(Icons.lock_outline)).color, accents.accent);
    expect(tileOf(Icons.key_outlined), PrivioColors.surfaceHigh);
    expect(tester.widget<Icon>(find.byIcon(Icons.key_outlined)).color, PrivioColors.textTertiary);
  });

  testWidgets('a row with a value has its chevron where the row without one has it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: Scaffold(
          body: SettingsSection(
            children: [
              SettingsRow(icon: Icons.lock_outline, label: 'Plain', onTap: () {}),
              SettingsRow(icon: Icons.schedule, label: 'Valued', value: 'All', onTap: () {}),
            ],
          ),
        ),
      ),
    );
    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    expect(chevrons, findsNWidgets(2));
    // A short value in a loose box used to leave the rest of its share empty
    // after the chevron, pulling it left of the one above.
    expect(tester.getTopRight(chevrons.at(1)).dx, tester.getTopRight(chevrons.at(0)).dx);
  });

  testWidgets('privacy: every setting has its icon, and sits with its kind', (tester) async {
    _tallScreen(tester);
    final state = await _state();
    await tester.pumpWidget(wrap(const PrivacyScreen(), state));
    await tester.pumpAndSettle();

    // Two of eighteen rows had an icon; a list half with and half without
    // reads as two lists.
    for (final row in tester.widgetList<SettingsRow>(find.byType(SettingsRow))) {
      expect(row.icon, isNotNull, reason: '${row.label} has no icon');
    }

    final who = _y(tester, 'WHO CAN SEE');
    final messaging = _y(tester, 'MESSAGING');
    final access = _y(tester, 'ACCESS');
    // Blocking decides who reaches you; a location is something a chat sends.
    // Both used to sit among the locks and codes.
    expect(_y(tester, 'Blocked Users'), inExclusiveRange(who, messaging));
    expect(_y(tester, 'Share location'), inExclusiveRange(messaging, access));
    expect(_y(tester, 'Screen Lock'), greaterThan(access));
  });
}

