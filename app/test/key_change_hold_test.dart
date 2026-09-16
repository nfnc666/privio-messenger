import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';

import 'deletion_test.dart' show buildServices;

InMemoryMessageStore withBob() => InMemoryMessageStore()
  ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));

void main() {
  group('holding a chat after a safety number changed', () {
    test('off by default — a reinstall must not lock a chat unasked', () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';

      expect(controller.blockOnKeyChange, isFalse);
    });

    test('with it off, a key change warns but does not hold', () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';
      await services.crypto.raiseKeyChangeAlert('account-bob');
      await controller.loadKeyChangeAlerts();

      expect(controller.hasKeyChangeAlert('account-bob'), isTrue);
      expect(controller.isHeldByKeyChange('account-bob'), isFalse);
    });

    test('with it on, the chat is held', () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';
      await controller.setBlockOnKeyChange(true);
      await services.crypto.raiseKeyChangeAlert('account-bob');
      await controller.loadKeyChangeAlerts();

      expect(controller.isHeldByKeyChange('account-bob'), isTrue);
    });

    test('a chat with no key change is never held, however strict the setting',
        () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';
      await controller.setBlockOnKeyChange(true);

      expect(controller.isHeldByKeyChange('account-bob'), isFalse);
    });

    test('answering the change lifts the hold', () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';
      await controller.setBlockOnKeyChange(true);
      await services.crypto.raiseKeyChangeAlert('account-bob');
      await controller.loadKeyChangeAlerts();
      expect(controller.isHeldByKeyChange('account-bob'), isTrue);

      await controller.acknowledgeKeyChange('account-bob');

      expect(controller.isHeldByKeyChange('account-bob'), isFalse);
    });

    test('the setting survives a restart, and is the account’s own', () async {
      final (services, _) = await buildServices(withBob());
      final first = ConversationController(services)..accountId = 'account-alice';
      await first.setBlockOnKeyChange(true);

      final second = ConversationController(services)..accountId = 'account-alice';
      await second.loadKeyChangeBlocking('account-alice');
      expect(second.blockOnKeyChange, isTrue);

      // A different account on the same phone starts from the default.
      final other = ConversationController(services)..accountId = 'account-carol';
      await other.loadKeyChangeBlocking('account-carol');
      expect(other.blockOnKeyChange, isFalse);
    });

    test('a read that lands after a switch is dropped', () async {
      final (services, _) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';
      await controller.setBlockOnKeyChange(true);

      final reader = ConversationController(services)..accountId = 'account-alice';
      final pending = reader.loadKeyChangeBlocking('account-alice');
      reader.accountId = 'account-carol';
      await pending;

      expect(
        reader.blockOnKeyChange,
        isFalse,
        reason: "one account's strict setting must not govern the next one's chats",
      );
    });

    test('the server is never told', () async {
      // The setting is local and stays local: a server that knew which of its
      // users refuse unexplained key changes would know which of them not to
      // try it on.
      final (services, messaging) = await buildServices(withBob());
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.setBlockOnKeyChange(true);

      expect(messaging.sent, isEmpty);
    });
  });
}
