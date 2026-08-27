import 'package:flutter_test/flutter_test.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';

Message mine(String clientId, {DeliveryState state = DeliveryState.sent}) => Message(
      id: clientId,
      clientId: clientId,
      body: 'hallo',
      sentAt: DateTime(2026),
      isMine: true,
      state: state,
    );

Message theirs(String clientId) => Message(
      id: 'envelope-$clientId',
      clientId: clientId,
      body: 'hallo zurück',
      sentAt: DateTime(2026),
      isMine: false,
    );

InMemoryMessageStore storeWith(List<Message> messages) {
  final store = InMemoryMessageStore()
    ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
  for (final message in messages) {
    store.append('acc-bob', message);
  }
  return store;
}

void main() {
  group('the payload', () {
    test('a receipt survives encoding and is never a message', () {
      const payload = MessagePayload.receipt(
        receiptIds: ['a', 'b'],
        receiptKind: 'read',
      );
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.isReceipt, isTrue);
      expect(decoded.isControl, isTrue);
      expect(decoded.receiptIds, ['a', 'b']);
      expect(decoded.receiptKind, 'read');
      expect(decoded.body, isEmpty);
      expect(decoded.isMedia, isFalse);
    });

    test('a typing notice carries when, not how long', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final decoded = MessagePayload.decode(MessagePayload.typing(now).encode());

      expect(decoded.isTyping, isTrue);
      expect(decoded.isControl, isTrue);
      expect(decoded.typingAt, now);
    });

    test('an ordinary message is neither', () {
      final decoded = MessagePayload.decode(
        const MessagePayload.text('hallo', clientId: 'c1').encode(),
      );
      expect(decoded.isReceipt, isFalse);
      expect(decoded.isTyping, isFalse);
      expect(decoded.isControl, isFalse);
      expect(decoded.body, 'hallo');
    });

    test('a control payload does not pick up a profile key', () {
      const receipt = MessagePayload.receipt(receiptIds: ['a'], receiptKind: 'delivered');
      expect(receipt.withProfileKey('a2V5').profileKey, isNull);

      // An ordinary one does.
      expect(const MessagePayload.text('hi').withProfileKey('a2V5').profileKey, 'a2V5');
    });
  });

  group('delivery state', () {
    test('a new message claims only that it was sent', () {
      final message = Message(id: '1', body: 'x', sentAt: DateTime(2026), isMine: true);
      expect(
        message.state,
        DeliveryState.sent,
        reason: 'the old default said every message had been read',
      );
    });

    test('a receipt moves my messages forward', () {
      final store = storeWith([mine('c1'), mine('c2')]);

      expect(store.markStateByClientIds('acc-bob', {'c1'}, DeliveryState.delivered), 1);
      final messages = store.conversationWith('acc-bob')!.messages;
      expect(messages[0].state, DeliveryState.delivered);
      expect(messages[1].state, DeliveryState.sent, reason: 'only what was named');
    });

    test('never walks backwards, however the receipts arrive', () {
      final store = storeWith([mine('c1')]);

      store.markStateByClientIds('acc-bob', {'c1'}, DeliveryState.read);
      // A delivered receipt from a second device, arriving late.
      expect(store.markStateByClientIds('acc-bob', {'c1'}, DeliveryState.delivered), 0);
      expect(store.conversationWith('acc-bob')!.messages.single.state, DeliveryState.read);
    });

    test('a receipt cannot change the other side’s messages', () {
      final store = storeWith([theirs('t1')]);
      expect(store.markStateByClientIds('acc-bob', {'t1'}, DeliveryState.read), 0);
    });

    test('unread ids name their messages, not mine', () {
      final store = storeWith([mine('c1'), theirs('t1'), theirs('t2')]);
      expect(store.unreadClientIds('acc-bob'), ['t1', 't2']);
    });
  });

  group('typing', () {
    test('is true only while it lasts', () {
      final store = storeWith([]);
      final now = DateTime(2026, 6, 1, 12);

      store.setTyping('acc-bob', now.add(const Duration(seconds: 6)));
      expect(store.conversationWith('acc-bob')!.isTypingAt(now), isTrue);
      expect(
        store.conversationWith('acc-bob')!.isTypingAt(now.add(const Duration(seconds: 7))),
        isFalse,
      );
    });

    test('clears when it is told to', () {
      final store = storeWith([]);
      store.setTyping('acc-bob', DateTime.now().add(const Duration(seconds: 6)));
      store.setTyping('acc-bob', null);
      expect(store.conversationWith('acc-bob')!.isTypingAt(DateTime.now()), isFalse);
    });

    test('a conversation with nobody typing says so', () {
      final store = storeWith([mine('c1')]);
      expect(store.conversationWith('acc-bob')!.isTypingAt(DateTime.now()), isFalse);
    });
  });
}
