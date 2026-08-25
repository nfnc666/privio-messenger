import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/theme/privio_colors.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/chat_list_row.dart';
import 'package:privio/widgets/message_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: PrivioTheme.dark(),
      home: PrivioScope(notifier: AppState(), child: child),
    );

void main() {
  testWidgets('the chat list shows names, previews and unread counts', (tester) async {
    await tester.pumpWidget(_wrap(const ChatsScreen()));
    await tester.pump();

    expect(find.text('Privio'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Hey! How are you?'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('the Unread filter hides read conversations', (tester) async {
    await tester.pumpWidget(_wrap(const ChatsScreen()));
    await tester.pump();

    expect(find.text('Charlie'), findsOneWidget);
    await tester.tap(find.text('Unread'));
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget, reason: 'Alice has unread messages');
    expect(find.text('Charlie'), findsNothing, reason: 'Charlie has none');
  });

  testWidgets('outgoing bubbles sit right and carry read ticks', (tester) async {
    final message = Message(
      id: '1',
      body: 'Sealed before it leaves the device',
      sentAt: DateTime(2026, 1, 1, 12),
      isMine: true,
      state: DeliveryState.read,
    );

    await tester.pumpWidget(_wrap(Scaffold(body: MessageBubble(message: message))));

    final align = tester.widget<Align>(find.ancestor(
      of: find.text('Sealed before it leaves the device'),
      matching: find.byType(Align),
    ).first,);
    expect(align.alignment, Alignment.centerRight);

    final tick = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(tick.color, PrivioColors.accentBright, reason: 'read receipts are accent green');
  });

  testWidgets('a group row uses the group avatar', (tester) async {
    const chat = ChatSummary(
      id: 'g',
      title: 'Project X',
      preview: 'Bob: Document.pdf',
      timestamp: '10:45',
      isGroup: true,
    );
    await tester.pumpWidget(_wrap(const Scaffold(body: ChatListRow(chat: chat))));
    expect(find.byIcon(Icons.group_rounded), findsOneWidget);
  });
}
