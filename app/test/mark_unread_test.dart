import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/widgets/chat_list_row.dart';

import 'deletion_test.dart' show buildServices, storeWith, text;
import 'saved_test.dart' show signedInAs;
import 'widget_test.dart' show wrap;

/// "Mark as unread": a reminder somebody sets for themselves in the chat list.
///
/// What these pin is that it stays a reminder. It is never sent, it never
/// pretends there are messages that are not there, it survives the things a
/// pin once did not survive, and it goes away the moment the chat is opened.

/// A chat with Bob holding one message from him that has already been read
/// here, so the list shows nothing waiting.
InMemoryMessageStore readChatWithBob() => storeWith([text('c1')])..markRead('account-bob');

/// Bob with one message in the signed-in list, read or not.
void bobWrote(AppState state, {bool read = true}) {
  final store = state.services.store
    ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'))
    ..append(
      'acc-bob',
      Message(
        id: 'b1',
        clientId: 'b1',
        body: 'bis später',
        sentAt: DateTime(2026, 9, 22, 18),
        isMine: false,
        senderAccountId: 'acc-bob',
      ),
    );
  if (read) store.markRead('acc-bob');
}

/// The dot a marked row wears, found by what it tells a screen reader. The row
/// merges it into its own announcement, so it is looked up on the widget.
final markedDot = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Marked as unread',
);

ChatSummary rowOf(AppState state, String id) =>
    state.conversations.chats.singleWhere((chat) => chat.id == id);

void main() {
  group('the store', () {
    test('keeps the mark apart from the count, and sets it once', () {
      final store = readChatWithBob();

      expect(store.setMarkedUnread('account-bob', marked: true), isTrue);
      final conversation = store.conversationWith('account-bob')!;
      expect(conversation.markedUnread, isTrue);
      expect(conversation.unreadCount, 0, reason: 'a mark is not a message');

      expect(store.setMarkedUnread('account-bob', marked: true), isFalse);
      expect(store.setMarkedUnread('nobody', marked: true), isFalse);
    });

    test('reading the chat takes the mark away', () {
      final store = readChatWithBob()..setMarkedUnread('account-bob', marked: true);
      store.markRead('account-bob');
      expect(store.conversationWith('account-bob')!.markedUnread, isFalse);
    });

    test('a new message on top of it is counted, and reading clears both', () {
      final store = readChatWithBob()..setMarkedUnread('account-bob', marked: true);
      store.append('account-bob', text('c2'));

      final conversation = store.conversationWith('account-bob')!;
      expect(conversation.unreadCount, 1);
      expect(conversation.markedUnread, isTrue);

      store.markRead('account-bob');
      expect(store.conversationWith('account-bob')!.unreadCount, 0);
      expect(store.conversationWith('account-bob')!.markedUnread, isFalse);
    });

    test('a contact refresh does not drop it', () {
      // The pin once had exactly this bug: an upsert built a new conversation
      // and quietly left the local preference behind.
      final store = readChatWithBob()..setMarkedUnread('account-bob', marked: true);
      store.upsertUser(
        const KnownUser(accountId: 'account-bob', username: 'bob', displayName: 'Bob'),
        authoritative: true,
      );
      expect(store.conversationWith('account-bob')!.markedUnread, isTrue);
    });

    test('a group listing does not drop it either', () {
      final store = InMemoryMessageStore()
        ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung'));
      expect(store.setMarkedUnread('g1', marked: true), isTrue);

      store.upsertGroup(
        const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung am Sonntag'),
        authoritative: true,
      );
      expect(store.conversationWith('g1')!.markedUnread, isTrue);
    });

    test('it survives being written to the archive and read back', () async {
      final store = readChatWithBob()
        ..upsertUser(const KnownUser(accountId: 'account-carol', username: 'carol'))
        ..append('account-carol', text('c9', author: 'account-carol'))
        ..setMarkedUnread('account-bob', marked: true)
        ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung'))
        ..setMarkedUnread('g1', marked: true);

      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(store.conversations());

      final restored = InMemoryMessageStore()..restore((await archive.load()).conversations);
      expect(restored.conversationWith('account-bob')!.markedUnread, isTrue);
      expect(restored.conversationWith('g1')!.markedUnread, isTrue);
      expect(restored.conversationWith('account-carol')!.markedUnread, isFalse);
    });
  });

  group('the controller', () {
    test('marking unread and back sends nothing at all', () async {
      final store = readChatWithBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      controller.setMarkedUnread('account-bob', marked: true);
      expect(controller.chats.single.markedUnread, isTrue);
      expect(controller.chats.single.hasUnread, isTrue);
      expect(controller.chats.single.unreadCount, 0);

      controller.setMarkedUnread('account-bob', marked: false);
      expect(controller.chats.single.hasUnread, isFalse);
      await pumpEventQueue();

      expect(messaging.sent, isEmpty, reason: 'a mark told somebody something');
      expect(messaging.sentToGroup, isEmpty);

      // And this is what it is not: reading a chat with something new in it
      // does send, because read receipts are on. Without this the test above
      // would also pass if the mark went through the read path.
      store.append('account-bob', text('c2'));
      controller.markRead('account-bob');
      await pumpEventQueue();
      expect(messaging.sent.where((payload) => payload.isReceipt), isNotEmpty);
    });

    test('the mark is redrawn and saved', () async {
      final store = readChatWithBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      var redraws = 0;
      controller.addListener(() => redraws += 1);

      controller.setMarkedUnread('account-bob', marked: true);
      expect(redraws, 1);

      // Setting what is already set is not a change and draws nothing.
      controller.setMarkedUnread('account-bob', marked: true);
      expect(redraws, 1);

      // Not `flush`, which writes whatever is there: the question is whether
      // setting the mark asked for a write by itself.
      await Future<void>.delayed(const Duration(seconds: 1));
      final restored = InMemoryMessageStore()
        ..restore((await services.archive.load()).conversations);
      expect(restored.conversationWith('account-bob')!.markedUnread, isTrue);
    });
  });

  group('the row', () {
    Future<void> drawRow(WidgetTester tester, ChatSummary chat) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(Scaffold(body: ChatListRow(chat: chat)), state));
      await tester.pump(const Duration(seconds: 1));
    }

    ChatSummary summary({int unreadCount = 0, bool markedUnread = false}) => ChatSummary(
          id: 'acc-bob',
          title: 'bob',
          preview: const ChatPreview(ChatPreviewKind.body, text: 'bis später'),
          timestamp: ChatStamp.none,
          unreadCount: unreadCount,
          markedUnread: markedUnread,
        );

    testWidgets('a marked chat wears a dot, not a number', (tester) async {
      await drawRow(tester, summary(markedUnread: true));
      expect(markedDot, findsOneWidget);
      expect(find.text('1'), findsNothing, reason: 'a count claims messages that are not there');
    });

    testWidgets('a real count wins over the mark', (tester) async {
      await drawRow(tester, summary(unreadCount: 3, markedUnread: true));
      expect(find.text('3'), findsOneWidget);
      expect(markedDot, findsNothing);
    });

    testWidgets('a read chat wears neither', (tester) async {
      await drawRow(tester, summary());
      expect(markedDot, findsNothing);
    });
  });

  group('the chat list', () {
    Future<void> openList(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.longPress(find.text('bob'));
      await tester.pumpAndSettle();
    }

    testWidgets('a long press marks a read chat unread, and says nothing is sent',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      bobWrote(state);
      await openList(tester, state);

      await openSheet(tester);
      expect(find.text('Mark as unread'), findsOneWidget);
      expect(find.text('Mark as read'), findsNothing);
      await tester.tap(find.text('Mark as unread'));
      await tester.pumpAndSettle();

      expect(rowOf(state, 'acc-bob').markedUnread, isTrue);
      expect(rowOf(state, 'acc-bob').unreadCount, 0);
      expect(markedDot, findsOneWidget);
      // Lets the archive write that the mark started finish.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the Unread filter shows a marked chat', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      bobWrote(state);
      await openList(tester, state);

      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.text('bob'), findsNothing);

      state.conversations.setMarkedUnread('acc-bob', marked: true);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('a marked chat offers to take the mark away, and only that',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      bobWrote(state);
      state.conversations.setMarkedUnread('acc-bob', marked: true);
      await openList(tester, state);

      await openSheet(tester);
      expect(find.text('Mark as read'), findsOneWidget);
      // Nothing is waiting, so nothing goes out, receipts on or not.
      expect(find.text('Only on this device. Nothing is sent.'), findsWidgets);
      expect(find.text('Read receipts go out, as when you open the chat.'), findsNothing);
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      expect(rowOf(state, 'acc-bob').hasUnread, isFalse);
    });

    testWidgets('with messages waiting it reads them, and says receipts go out',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      bobWrote(state, read: false);
      await openList(tester, state);

      await openSheet(tester);
      expect(find.text('Mark as read'), findsOneWidget);
      expect(find.text('Read receipts go out, as when you open the chat.'), findsOneWidget);
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      expect(rowOf(state, 'acc-bob').unreadCount, 0);
    });

    testWidgets('with read receipts off the note does not promise any',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await state.conversations.setReadReceipts(false);
      bobWrote(state, read: false);
      await openList(tester, state);

      await openSheet(tester);
      expect(find.text('Mark as read'), findsOneWidget);
      expect(find.text('Read receipts go out, as when you open the chat.'), findsNothing);
    });
  });

  testWidgets('opening the chat takes the mark away, whichever way in',
      (tester) async {
    // Straight to the screen, as from a contact or a profile, without the
    // list's tap that marks a chat read.
    final state = await signedInAs('acc-alice');
    addTearDown(state.conversations.stop);
    bobWrote(state);
    state.conversations.setMarkedUnread('acc-bob', marked: true);

    await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
    await tester.pump(const Duration(seconds: 1));

    expect(rowOf(state, 'acc-bob').markedUnread, isFalse);
  });
}
