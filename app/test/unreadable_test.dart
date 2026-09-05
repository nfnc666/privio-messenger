import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/messaging_service.dart';

import 'deletion_test.dart' show ScriptedMessaging, buildServices;

InMemoryMessageStore withBob() => InMemoryMessageStore()
  ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));

UndecryptableMessage broken({
  int envelopeId = 1,
  String? from = 'account-bob',
  int? deviceIndex = 1,
  String? groupId,
}) =>
    UndecryptableMessage(
      envelopeId,
      from,
      StateError('No valid sessions'),
      senderDeviceIndex: deviceIndex,
      groupId: groupId,
    );

List<Message> holes(InMemoryMessageStore store, String id) => store
    .conversationWith(id)!
    .messages
    .where((m) => m.kind == MessageKind.undelivered)
    .toList();

void main() {
  group('a message that could not be read', () {
    test('leaves a line in the conversation rather than a gap', () async {
      // The sender's screen says delivered. Dropping it silently leaves a hole
      // that reads as an answer nobody gave.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable.add(broken());

      await controller.drain();

      expect(holes(store, 'account-bob').single.body, contains('could not be read'));
      expect(holes(store, 'account-bob').single.body, contains('bob'));
    });

    test('a batch from one sender is one line, with the count', () async {
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable
        ..add(broken(envelopeId: 1))
        ..add(broken(envelopeId: 2))
        ..add(broken(envelopeId: 3));

      await controller.drain();

      final line = holes(store, 'account-bob').single;
      expect(line.body, startsWith('3 messages'));
    });

    test('lands in the group it came through, not in a private chat', () async {
      final store = withBob()..upsertGroup(const GroupInfo(groupId: 'group-1', role: 'member'));
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable.add(broken(groupId: 'group-1'));

      await controller.drain();

      expect(holes(store, 'group-1'), hasLength(1));
      expect(holes(store, 'account-bob'), isEmpty);
    });

    test('is not something to reply to, read or search', () async {
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable.add(broken());

      await controller.drain();

      expect(store.conversationWith('account-bob')!.unreadCount, 0);
      expect(controller.searchMessages('could not'), isEmpty);
    });
  });

  group('repairing the session', () {
    List<MessagePayload> resets(ScriptedMessaging m) =>
        m.sent.where((p) => p.isSessionReset).toList();

    test('asks the sender to start again', () async {
      // Without this the ratchet stays out of step and every later message from
      // that device fails the same way, for good.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable.add(broken());

      await controller.drain();

      expect(resets(messaging), hasLength(1));
    });

    test('once per device, however many envelopes failed', () async {
      // A reset consumes one of the other side's one-time prekeys. Twenty
      // failed envelopes must not become twenty handshakes.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable
        ..add(broken(envelopeId: 1))
        ..add(broken(envelopeId: 2))
        ..add(broken(envelopeId: 3));

      await controller.drain();
      messaging.undecryptable.add(broken(envelopeId: 4));
      await controller.drain();

      expect(resets(messaging), hasLength(1));
      expect(ConversationController.sessionResetInterval, const Duration(hours: 1));
    });

    test('does nothing for a failure with no identifiable device', () async {
      // An envelope the server could not label is not a session to repair, and
      // guessing at one would consume a stranger's prekeys.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.undecryptable.add(broken(deviceIndex: null));

      await controller.drain();

      expect(resets(messaging), isEmpty);
    });

    test('an arriving reset leaves nothing behind', () async {
      // Opening it was the repair. There is nothing to file and nothing to show.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 9,
          senderAccountId: 'account-bob',
          payload: const MessagePayload.sessionReset(),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages, isEmpty);
    });
  });
}
