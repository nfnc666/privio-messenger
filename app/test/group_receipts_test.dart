import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/messaging_service.dart';

import 'deletion_test.dart' show buildServices;

/// A group of [members] people — this account and the others — with bob and
/// carol known by name, so a receipt has somewhere to be sent.
InMemoryMessageStore groupOf(int members) => InMemoryMessageStore()
  ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'))
  ..upsertUser(const KnownUser(accountId: 'account-carol', username: 'carol'))
  ..upsertGroup(GroupInfo(groupId: 'group-1', role: 'member', memberCount: members));

Message mine(String clientId) => Message(
      id: clientId,
      clientId: clientId,
      body: 'hallo alle',
      sentAt: DateTime.now(),
      isMine: true,
    );

IncomingMessage receiptFrom(
  String accountId, {
  required List<String> ids,
  required String kind,
  String? groupId = 'group-1',
}) =>
    IncomingMessage(
      envelopeId: 1,
      senderAccountId: accountId,
      payload: MessagePayload.receipt(
        receiptIds: ids,
        receiptKind: kind,
        receiptGroupId: groupId,
      ),
      receivedAt: DateTime.now(),
    );

Message only(InMemoryMessageStore store) =>
    store.conversationWith('group-1')!.messages.single;

void main() {
  group('receipts in a group', () {
    test('one member reading is not everybody reading', () async {
      // Two ticks that light up because one of seven people opened the app say
      // something that is not true.
      final store = groupOf(4)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'));

      await controller.drain();

      expect(only(store).readCount, 1);
      expect(only(store).state, DeliveryState.sent, reason: 'the ticks have not moved');
    });

    test('the ticks move when everyone has', () async {
      final store = groupOf(3)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'))
        ..add(receiptFrom('account-carol', ids: ['c1'], kind: 'read'));

      await controller.drain();

      expect(only(store).readCount, 2);
      expect(only(store).state, DeliveryState.read);
    });

    test('a mixture of delivered and read is delivered, not read', () async {
      final store = groupOf(3)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'))
        ..add(receiptFrom('account-carol', ids: ['c1'], kind: 'delivered'));

      await controller.drain();

      expect(only(store).state, DeliveryState.delivered);
    });

    test('the same person twice is still one person', () async {
      final store = groupOf(3)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'))
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'));

      await controller.drain();

      expect(only(store).readCount, 1);
      expect(only(store).state, DeliveryState.sent);
    });

    test('a read receipt is never walked back by a later delivered one', () async {
      // Out of order happens: a read receipt from a phone, a delivered one from
      // the same person's laptop.
      final store = groupOf(2)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'))
        ..add(receiptFrom('account-bob', ids: ['c1'], kind: 'delivered'));

      await controller.drain();

      expect(only(store).state, DeliveryState.read);
    });

    test('without a member count nothing claims everyone has seen it', () async {
      // Zero means "not known yet", and a group of nobody is not a group.
      final store = groupOf(0)..append('group-1', mine('c1'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(receiptFrom('account-bob', ids: ['c1'], kind: 'read'));

      await controller.drain();

      expect(only(store).readCount, 1, reason: 'the count is still recorded');
      expect(only(store).state, DeliveryState.sent);
    });
  });

  group('sending them', () {
    test('a group message is acknowledged to its author, naming the group', () async {
      // Never to the group: who read what is between the reader and whoever
      // wrote it, and telling everybody costs a sealed copy per member device.
      final store = groupOf(3);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 2,
          senderAccountId: 'account-bob',
          groupId: 'group-1',
          payload: const MessagePayload.text('hallo', clientId: 'theirs-1'),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      final receipt = messaging.sent.singleWhere((p) => p.isReceipt);
      expect(receipt.receiptGroupId, 'group-1');
      expect(receipt.receiptIds, ['theirs-1']);
      expect(receipt.receiptKind, 'delivered');
    });

    test('opening a group tells each author about their own messages', () async {
      final store = groupOf(3)
        ..append(
          'group-1',
          Message(
            id: 'e1',
            clientId: 'from-bob',
            body: 'a',
            sentAt: DateTime.now(),
            isMine: false,
            senderAccountId: 'account-bob',
          ),
        )
        ..append(
          'group-1',
          Message(
            id: 'e2',
            clientId: 'from-carol',
            body: 'b',
            sentAt: DateTime.now(),
            isMine: false,
            senderAccountId: 'account-carol',
          ),
        );
      final (services, messaging) = await buildServices(store);

      ConversationController(services).markRead('group-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reads = messaging.sent.where((p) => p.receiptKind == 'read').toList();
      expect(reads, hasLength(2), reason: 'one each, not one to the group');
      expect(
        reads.expand((p) => p.receiptIds!).toSet(),
        {'from-bob', 'from-carol'},
      );
      expect(reads.every((p) => p.receiptGroupId == 'group-1'), isTrue);
    });
  });

  group('a pinned chat', () {
    test('stays pinned when the conversation is upserted again', () async {
      // An upsert happens on every contact refresh, every group listing and
      // every message from someone new. A pin a refresh quietly undid was a pin
      // that did not work.
      final store = groupOf(3)..setPinned('group-1', pinned: true);
      store.upsertGroup(const GroupInfo(groupId: 'group-1', role: 'member'));
      expect(store.conversationWith('group-1')!.pinned, isTrue);

      store
        ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'))
        ..setPinned('account-bob', pinned: true)
        ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
      expect(store.conversationWith('account-bob')!.pinned, isTrue);
    });
  });
}
