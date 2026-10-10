import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/welcome_screen.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/appear.dart';
import 'package:privio/widgets/typing_label.dart';

import 'widget_test.dart' show quietServices, wrap;

/// How the app moves, and that it stops when asked to.
///
/// Motion is new here: messages that arrive while a chat is open rise in, the
/// welcome screen comes in piece by piece, and somebody typing shows three
/// dots. "Reduce motion" on the device turns all of it off, and these tests
/// set it the way the device reports it.
Future<AppState> _chatWithBob() async {
  final services = await quietServices();
  services.store
    ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'))
    ..append(
      'account-bob',
      Message(id: 'old', body: 'schon da', sentAt: DateTime(2026), isMine: false),
    );
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  return state;
}

/// How far in [text]'s entrance is: 0 not yet visible, 1 fully there.
double _shown(WidgetTester tester, String text) {
  final appear = find.ancestor(of: find.text(text), matching: find.byType(Appear)).first;
  final fade = find.descendant(of: appear, matching: find.byType(FadeTransition)).first;
  return tester.widget<FadeTransition>(fade).opacity.value;
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _sendWhileOpen(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(wrap(const ChatScreen(accountId: 'account-bob', title: 'bob'), state));
  // On the very first frame: a chat opening is not its history arriving.
  expect(_shown(tester, 'schon da'), 1, reason: 'the history moved in when the chat opened');
  await tester.pump(const Duration(seconds: 1));
  // Sent from here and refused by the quiet server: what matters is that a
  // bubble arrives while the chat is on screen.
  await tester.runAsync(() => state.conversations.send('account-bob', 'gerade eben'));
  await tester.pump();
}

void main() {
  testWidgets('a message that arrives while the chat is open rises in', (tester) async {
    final state = await _chatWithBob();
    addTearDown(state.conversations.stop);
    await _sendWhileOpen(tester, state);

    expect(_shown(tester, 'gerade eben'), lessThan(1), reason: 'the new one is still on its way');

    await tester.pump(const Duration(milliseconds: 400));
    expect(_shown(tester, 'gerade eben'), 1);
  });

  testWidgets('with "Reduce motion" on, it is simply there', (tester) async {
    _reduceMotion(tester);
    final state = await _chatWithBob();
    addTearDown(state.conversations.stop);
    await _sendWhileOpen(tester, state);

    expect(_shown(tester, 'gerade eben'), 1);
  });

  Widget welcome() => MaterialApp(
        theme: PrivioTheme.dark(),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: WelcomeScreen(onGetStarted: () {}, onSignIn: () {}, onImportBackup: () {}),
      );

  testWidgets('the welcome screen arrives in order, and is all there within a second',
      (tester) async {
    await tester.pumpWidget(welcome());
    expect(_shown(tester, 'Privio'), 0);
    expect(_shown(tester, 'End-to-end encrypted'), 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester, 'Privio'), greaterThan(0));
    expect(
      _shown(tester, 'Privio'),
      greaterThan(_shown(tester, 'End-to-end encrypted')),
      reason: 'the name before the promises',
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(_shown(tester, 'End-to-end encrypted'), 1);
    expect(_shown(tester, 'Privacy by design'), 1);
  });

  testWidgets('the welcome screen does not move when asked not to', (tester) async {
    _reduceMotion(tester);
    await tester.pumpWidget(welcome());
    await tester.pump();
    expect(_shown(tester, 'Privio'), 1);
    expect(_shown(tester, 'Privacy by design'), 1);
  });

  Widget typing() => const MaterialApp(home: Scaffold(body: TypingLabel('tippt …')));

  testWidgets('typing shows live dots, and is still read as the sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(typing());
    expect(find.text('tippt'), findsOneWidget, reason: 'the ellipsis became the dots');
    expect(find.bySemanticsLabel('tippt …'), findsOneWidget);
    // Live: it is still moving a second later, which is why nothing that shows
    // it can wait for the screen to settle.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    handle.dispose();
  });

  testWidgets('typing is the plain sentence when motion is reduced', (tester) async {
    _reduceMotion(tester);
    await tester.pumpWidget(typing());
    expect(find.text('tippt …'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
