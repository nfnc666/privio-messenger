import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/nav_shell.dart';
import 'package:privio/screens/welcome_screen.dart';
import 'package:privio/theme/motion.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/appear.dart';
import 'package:privio/widgets/typing_label.dart';

import 'call_overlay_test.dart' show signedInApp;
import 'widget_test.dart' show quietServices, wrap;

/// How the app moves, and what it does instead when asked not to.
///
/// Messages that arrive while a chat is open come in from their own side, the
/// chat list fills a row at a time, a tab rises in, the chosen tab's icon
/// pops, the welcome screen comes in piece by piece, and somebody typing shows
/// three dots. The first version was there and could not be seen — a tenth
/// of a second and ten pixels — so these tests also hold it to being visible.
///
/// "Reduce motion" on the device keeps the fades and drops everything that
/// moves, which is Apple's guidance; these tests set it the way the device
/// reports it.
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

Finder _appearOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Appear)).first;

/// How far in [text]'s entrance is: 0 not yet visible, 1 fully there.
double _shown(WidgetTester tester, String text) {
  final fade = find.descendant(of: _appearOf(text), matching: find.byType(FadeTransition)).first;
  return tester.widget<FadeTransition>(fade).opacity.value;
}

/// Where [text] is on its way in from, relative to where it lands — zero
/// when it does not move at all.
Offset _offset(WidgetTester tester, String text) {
  final moves = find.descendant(of: _appearOf(text), matching: find.byType(Transform));
  if (moves.evaluate().isEmpty) return Offset.zero;
  final matrix = tester.widget<Transform>(moves.first).transform;
  return Offset(matrix.getTranslation().x, matrix.getTranslation().y);
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
  test('long and far enough to be seen', () {
    // The first values — 160 and 240 ms, 10 px — were invisible on a phone.
    expect(PrivioMotion.standard, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
    expect(PrivioMotion.rise, greaterThanOrEqualTo(20));
    expect(PrivioMotion.travel, greaterThanOrEqualTo(20));
  });

  testWidgets('a message you send comes in from the right, and settles', (tester) async {
    final state = await _chatWithBob();
    addTearDown(state.conversations.stop);
    await _sendWhileOpen(tester, state);

    expect(_shown(tester, 'gerade eben'), lessThan(1), reason: 'the new one is still on its way');
    expect(_offset(tester, 'gerade eben').dx, greaterThan(10), reason: 'from the side it sits on');

    await tester.pump(const Duration(milliseconds: 100));
    final halfway = _offset(tester, 'gerade eben');
    expect(halfway.dx, greaterThan(0), reason: 'still visibly moving a tenth of a second in');

    await tester.pump(const Duration(milliseconds: 400));
    expect(_shown(tester, 'gerade eben'), 1);
    expect(_offset(tester, 'gerade eben'), Offset.zero);
  });

  testWidgets('with "Reduce motion" on, it fades in and does not move', (tester) async {
    _reduceMotion(tester);
    final state = await _chatWithBob();
    addTearDown(state.conversations.stop);
    await _sendWhileOpen(tester, state);

    expect(_shown(tester, 'gerade eben'), lessThan(1), reason: 'a fade is not motion');
    expect(_offset(tester, 'gerade eben'), Offset.zero, reason: 'but nothing slides');
    await tester.pump(PrivioMotion.quick);
    expect(_shown(tester, 'gerade eben'), 1, reason: 'and the fade is short');
  });

  group('the chat list', () {
    Future<AppState> withChats(int count) async {
      final services = await quietServices();
      for (var i = 0; i < count; i++) {
        services.store
          ..upsertUser(KnownUser(accountId: 'account-$i', username: 'person$i'))
          ..append(
            'account-$i',
            Message(id: 'm$i', body: 'hallo $i', sentAt: DateTime(2026, 1, 1, 12, 59 - i), isMine: false),
          );
      }
      final state = AppState(services: services, store: InMemorySecureStore());
      await state.initialise();
      return state;
    }

    testWidgets('fills a row at a time, from the top', (tester) async {
      final state = await withChats(5);
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(milliseconds: 120));

      expect(_shown(tester, 'person0'), greaterThan(_shown(tester, 'person4')),
          reason: 'the top row is further in than the fifth');
      expect(_shown(tester, 'person4'), lessThan(1));

      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        expect(_shown(tester, 'person$i'), 1);
      }

      // Coming back to it, or it redrawing, plays nothing again.
      state.conversations.notifyListeners();
      await tester.pump();
      expect(_shown(tester, 'person2'), 1);
    });
  });

  group('rows a list has not held before', () {
    Widget list(Entrances entrances, List<String> ids) => MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              entrances.see(ids);
              // A builder, as the screens use: a row is made when it is shown.
              return ListView.builder(
                itemCount: ids.length,
                itemBuilder: (context, index) => entrances.wrap(
                  id: ids[index],
                  child: SizedBox(height: 40, child: Text(ids[index])),
                ),
              );
            },),
          ),
        );

    testWidgets('arrive; the ones already there do not again', (tester) async {
      final entrances = Entrances();
      await tester.pumpWidget(list(entrances, ['a', 'b']));
      expect(_shown(tester, 'a'), lessThan(1));
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpWidget(list(entrances, ['new', 'a', 'b']));
      expect(_shown(tester, 'new'), lessThan(1), reason: 'a chat that just started slides in');
      expect(_shown(tester, 'a'), 1, reason: 'and the others stay put');
      expect(_shown(tester, 'b'), 1);
    });

    testWidgets('a row not on screen when it arrived does not play when scrolled to',
        (tester) async {
      final entrances = Entrances();
      final ids = [for (var i = 0; i < 60; i++) 'row$i'];
      await tester.pumpWidget(list(entrances, ids));
      await tester.pump(const Duration(seconds: 1));

      await tester.drag(find.byType(ListView), const Offset(0, -1800));
      await tester.pump();
      final below = find.textContaining('row4');
      expect(below, findsWidgets);
      expect(_shown(tester, tester.widget<Text>(below.last).data!), 1);
    });
  });

  testWidgets('a tab rises in, and its icon pops as it is chosen', (tester) async {
    final (state, _) = await signedInApp();
    addTearDown(state.conversations.stop);
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavShell), findsOneWidget);

    final bar = find.byType(BottomNavigationBar);
    await tester.tap(find.descendant(of: bar, matching: find.text('Contacts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tabs = find.descendant(of: find.byType(NavShell), matching: find.byType(IndexedStack)).first;
    final tab = find.ancestor(of: tabs, matching: find.byType(FadeTransition)).first;
    expect(tester.widget<FadeTransition>(tab).opacity.value, lessThan(1), reason: 'the tab is fading up');
    final icon = find.descendant(of: bar, matching: find.byType(TweenAnimationBuilder<double>));
    expect(icon, findsOneWidget, reason: 'only the chosen icon pops');
    final scale = tester.widget<Transform>(find.descendant(of: icon, matching: find.byType(Transform)).first);
    expect(scale.transform.entry(0, 0), lessThan(1), reason: 'smaller than it ends');

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<FadeTransition>(tab).opacity.value, 1);
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

  testWidgets('the welcome screen fades in without moving when asked not to', (tester) async {
    _reduceMotion(tester);
    await tester.pumpWidget(welcome());
    expect(_offset(tester, 'Privacy by design'), Offset.zero);
    await tester.pump(PrivioMotion.quick);
    expect(_shown(tester, 'Privio'), 1, reason: 'no stagger: that is motion in time');
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
