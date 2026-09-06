import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/widgets/message_bubble.dart';

import 'widget_test.dart' show quietServices, wrap;
import 'support/fake_voice.dart';

/// A recording that could not be sent, sitting in the queue.
///
/// Built through the controller rather than by hand, because what is on trial
/// is whether the chat offers the queue's own actions — and the queue is what
/// puts the message there.
Future<AppState> chatWithAFailedRecording() async {
  final services = await quietServices();
  services.store.upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  // The API answers everything with empty collections, so the send fails and
  // the recording stays queued — which is the case under test.
  final recorder = FakeVoiceRecorder(duration: const Duration(seconds: 5));
  await recorder.start();
  await state.conversations.sendVoice('account-bob', await recorder.stop());
  return state;
}


/// Long-presses the bubble itself rather than the row it sits in.
///
/// `MessageBubble` is an `Align` filling the width, so its own rectangle starts
/// at the far edge of the screen — pressing its top-left lands on empty space
/// beside an outgoing message and opens nothing. This presses just inside the
/// visible bubble, above the voice controls, which is also a check that those
/// controls do not swallow the gesture.
Future<void> longPressTheBubble(WidgetTester tester) async {
  final box = tester.getRect(find.byType(MessageBubble).first);
  await tester.longPressAt(Offset(box.right - 30, box.top + 12));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('a recording that did not go out can be tried again', (tester) async {
    // The controller has had `retry` since the offline queue was written and
    // nothing called it: a failed voice message showed a red mark and left the
    // person looking at it with nothing to do.
    final state = await chatWithAFailedRecording();
    addTearDown(state.conversations.stop);
    expect(state.conversations.queuedCount, 1, reason: 'it is in the queue');

    await tester.pumpWidget(wrap(const ChatScreen(accountId: 'account-bob', title: 'bob'), state));
    await tester.pump(const Duration(seconds: 1));

    await longPressTheBubble(tester);

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('deleting it takes the queue entry with it', (tester) async {
    // A bubble removed on its own leaves the message to arrive later out of a
    // queue the person thought they had emptied.
    final state = await chatWithAFailedRecording();
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(wrap(const ChatScreen(accountId: 'account-bob', title: 'bob'), state));
    await tester.pump(const Duration(seconds: 1));

    await longPressTheBubble(tester);
    await tester.tap(find.text('Delete'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(state.conversations.queuedCount, 0);
    expect(
      state.services.store.conversationWith('account-bob')!.messages,
      isEmpty,
      reason: 'and the bubble goes with it',
    );
  });
}
