import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/auth_screen.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/contacts_screen.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/privio_back_button.dart';

import 'widget_test.dart' show quietServices, wrap;

/// Everything that can be tapped has a name a screen reader can say.
///
/// Flutter's own guideline, run over the screens people use most. Found by
/// walking the app through its accessibility tree in a browser: the channel's
/// send button, the thread's, the microphone, the password eye and the
/// add-contact button were each announced as nothing but "button".
Future<AppState> _state() async {
  final services = await quietServices();
  services.store.upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  return state;
}

void main() {
  final screens = <String, Widget>{
    'chat': const ChatScreen(accountId: 'account-bob', title: 'bob'),
    'chat list': const ChatsScreen(),
    'contacts': const ContactsScreen(),
    'sign-up': const AuthScreen(mode: AuthMode.signUp),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    testWidgets('every tap target on the $name screen has a label', (tester) async {
      final handle = tester.ensureSemantics();
      final state = await _state();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(screen, state));
      await tester.pump(const Duration(seconds: 1));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  testWidgets('the back arrow says "back" in the reader\'s language', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        locale: const Locale('de'),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: const Scaffold(body: PrivioBackButton()),
      ),
    );
    expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    handle.dispose();
  });
}
