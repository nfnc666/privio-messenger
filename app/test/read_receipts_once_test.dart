import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';

import 'deletion_test.dart' show buildServices, storeWith, text;
import 'group_receipts_test.dart' show groupOf;

/// A read receipt names what was read since the last one, and nothing else.
///
/// It used to name every message the other side had ever sent in the chat,
/// each time the chat was opened: more sealed bytes than the news was worth,
/// and the same news again for messages read weeks ago. Nothing about it was
/// wrong on the other side, whose ticks never walk backwards; it was simply
/// more leaving the device than had to.

List<String> receiptIds(List<MessagePayload> sent) => [
      for (final payload in sent)
        if (payload.isReceipt && payload.receiptKind == 'read') ...payload.receiptIds!,
    ];

void main() {
  group('the store', () {
    test('reading remembers what was read', () {
      final store = storeWith([text('t1'), text('t2')]);
      expect(store.unreadClientIds('account-bob'), ['t1', 't2']);

      store.markRead('account-bob');
      expect(store.unreadClientIds('account-bob'), isEmpty);

      store.append('account-bob', text('t3'));
      expect(store.unreadClientIds('account-bob'), ['t3']);
    });

    test('my own messages keep the state the other side reported', () {
      // Marking them read here would draw two blue ticks under a message
      // nobody has opened.
      final store = storeWith([text('c1', isMine: true), text('t1')]);
      store.markRead('account-bob');

      final messages = store.conversationWith('account-bob')!.messages;
      expect(messages.first.state, DeliveryState.sent);
      expect(messages.last.state, DeliveryState.read);
    });

    test('in a group it is remembered for every author', () {
      final store = groupOf(3)
        ..append('group-1', text('b1', author: 'account-bob'))
        ..append('group-1', text('k1', author: 'account-carol'));
      expect(store.unreadBySender('group-1'), {
        'account-bob': ['b1'],
        'account-carol': ['k1'],
      });

      store.markRead('group-1');
      expect(store.unreadBySender('group-1'), isEmpty);

      store.append('group-1', text('k2', author: 'account-carol'));
      expect(store.unreadBySender('group-1'), {
        'account-carol': ['k2'],
      });
    });

    test('what was read stays read after a restart', () async {
      final store = storeWith([text('t1')])..markRead('account-bob');
      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(store.conversations());

      final restored = InMemoryMessageStore()..restore((await archive.load()).conversations);
      expect(restored.unreadClientIds('account-bob'), isEmpty);
    });
  });

  group('the controller', () {
    test('opening a chat twice confirms each message once', () async {
      final store = storeWith([text('t1'), text('t2')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      controller.markRead('account-bob');
      await pumpEventQueue();
      expect(receiptIds(messaging.sent), ['t1', 't2']);

      controller.markRead('account-bob');
      await pumpEventQueue();
      expect(receiptIds(messaging.sent), ['t1', 't2'], reason: 'the same news went out again');

      store.append('account-bob', text('t3'));
      controller.markRead('account-bob');
      await pumpEventQueue();
      expect(receiptIds(messaging.sent), ['t1', 't2', 't3']);
    });

    test('what was read with receipts off is not confirmed once they are on', () async {
      // Turning receipts on says something about the future. Sending receipts
      // for what was read while they were off would say it about the past.
      final store = storeWith([text('t1')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      // The server is not there to store the setting; the switch flips first.
      await controller.setReadReceipts(false).catchError((_) {});
      controller.markRead('account-bob');
      await controller.setReadReceipts(true).catchError((_) {});

      store.append('account-bob', text('t2'));
      controller.markRead('account-bob');
      await pumpEventQueue();
      expect(receiptIds(messaging.sent), ['t2']);
    });
  });
}
