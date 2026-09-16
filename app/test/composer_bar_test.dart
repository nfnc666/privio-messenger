import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/screens/chat_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// The bar at the bottom of a chat.
///
/// It had grown to four icons *before* the text field, and on a phone that left
/// the field a column two words wide — the thing people are there to use was the
/// narrowest thing in the row. These tests are about the shape, because the
/// shape is what went wrong.
Future<AppState> chatWithBob() async {
  final services = await quietServices();
  services.store.upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  return state;
}

Future<void> openChat(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    wrap(const ChatScreen(accountId: 'account-bob', title: 'bob'), state),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// The rectangle of the field somebody types into.
Rect fieldRect(WidgetTester tester) =>
    tester.getRect(find.byType(TextField).hitTestable().first);

void main() {
  testWidgets('the text field is the widest thing in the bar', (tester) async {
    // The regression this file exists for. Anything that takes width from the
    // field has to earn it, and nothing has earned more than half.
    final state = await chatWithBob();
    addTearDown(state.conversations.stop);
    await openChat(tester, state);

    final screen = tester.getSize(find.byType(ChatScreen)).width;
    expect(
      fieldRect(tester).width,
      greaterThan(screen * 0.6),
      reason: 'the bar squeezed the field again',
    );
  });

  testWidgets('it stays one line with nothing typed in it', (tester) async {
    // Three lines of placeholder is what a squeezed field looks like before
    // anybody measures it.
    final state = await chatWithBob();
    addTearDown(state.conversations.stop);
    await openChat(tester, state);

    expect(fieldRect(tester).height, lessThan(80), reason: 'the field wrapped');
  });

  testWidgets('emoji and camera are still there, and inside the field',
      (tester) async {
    final state = await chatWithBob();
    addTearDown(state.conversations.stop);
    await openChat(tester, state);

    final field = fieldRect(tester);
    for (final icon in [Icons.emoji_emotions_outlined, Icons.photo_camera_outlined]) {
      final found = find.byIcon(icon);
      expect(found, findsOneWidget, reason: '$icon left the bar');
      final rect = tester.getRect(found);
      expect(
        rect.left,
        greaterThan(field.left),
        reason: '$icon sits beside the field rather than in it',
      );
    }
  });

  testWidgets('the attach button and the microphone flank it', (tester) async {
    final state = await chatWithBob();
    addTearDown(state.conversations.stop);
    await openChat(tester, state);

    final field = fieldRect(tester);
    expect(tester.getRect(find.byIcon(Icons.add_rounded)).right, lessThan(field.left));
    expect(find.byIcon(Icons.mic_rounded).evaluate().length, 1);
  });

  group('the disappearing-messages timer', () {
    testWidgets('is not in the bar while it is off', (tester) async {
      final state = await chatWithBob();
      addTearDown(state.conversations.stop);
      await openChat(tester, state);

      expect(find.byIcon(Icons.timer_rounded), findsNothing);
    });

    testWidgets('but is still reachable, from the attach menu', (tester) async {
      // Moving a control out of the bar must not move it out of reach. The row
      // carries its state too, so the menu answers "is it on?" as well as
      // offering to change it.
      final state = await chatWithBob();
      addTearDown(state.conversations.stop);
      await openChat(tester, state);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Disappearing Messages'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('shows in the field the moment it is on', (tester) async {
      // The one thing in this bar somebody can be hurt by not seeing: a chat
      // that deletes itself while they keep writing. It is drawn without being
      // asked for, next to the field they are about to type into.
      final state = await chatWithBob();
      addTearDown(state.conversations.stop);
      await state.conversations.setDisappearAfter('account-bob', const Duration(hours: 1));
      await openChat(tester, state);

      expect(find.byIcon(Icons.timer_rounded), findsOneWidget);
      final chip = tester.getRect(find.byIcon(Icons.timer_rounded));
      final field = fieldRect(tester);
      expect(chip.left, lessThan(field.left), reason: 'the chip leads the field');
      expect(
        fieldRect(tester).width,
        greaterThan(tester.getSize(find.byType(ChatScreen)).width * 0.45),
        reason: 'the chip took too much of the field',
      );
    });
  });
}
