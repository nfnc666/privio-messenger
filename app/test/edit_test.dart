import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/message_bubble.dart';

import 'deletion_test.dart' show buildServices, storeWith, text;

IncomingMessage editOf(
  String clientId,
  String body, {
  String from = 'account-bob',
}) =>
    IncomingMessage(
      envelopeId: 2,
      senderAccountId: from,
      payload: MessagePayload.edit(editTo: clientId, body: body),
      receivedAt: DateTime(2026, 1, 1, 12, 6),
    );

void main() {
  group('the edit payload', () {
    test('survives encoding and is never a message', () {
      const payload = MessagePayload.edit(editTo: 'c1', body: 'korrigiert');
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.isEdit, isTrue);
      expect(decoded.isControl, isTrue, reason: 'it must never appear as a bubble');
      expect(decoded.isDeletion, isFalse);
      expect(decoded.editTo, 'c1');
      expect(decoded.body, 'korrigiert');
    });

    test('carries the target and the new text, and nothing else', () {
      final json = jsonDecode(const MessagePayload.edit(editTo: 'c1', body: 'neu').encode())
          as Map<String, dynamic>;
      expect(json['t'], 'edit');
      expect(json.keys.toSet(), {'v', 't', 'b', 'et'});
    });
  });

  group('the store', () {
    test('replaces the text in place and marks it edited', () {
      final store = storeWith([text('c1'), text('c2', body: 'alt'), text('c3')]);
      final at = DateTime(2026, 1, 1, 13);

      expect(
        store.editMessage(conversationId: 'account-bob', clientId: 'c2', body: 'neu', editedAt: at),
        isTrue,
      );

      final messages = store.conversationWith('account-bob')!.messages;
      expect(messages.map((m) => m.clientId), ['c1', 'c2', 'c3']);
      expect(messages[1].body, 'neu');
      expect(messages[1].editedAt, at);
      expect(messages[1].sentAt, DateTime(2026, 1, 1, 12), reason: 'when it was written does not move');
    });

    test('an edit that changes nothing is not a change', () {
      final store = storeWith([text('c1', body: 'gleich')]);
      expect(
        store.editMessage(
          conversationId: 'account-bob',
          clientId: 'c1',
          body: 'gleich',
          editedAt: DateTime(2026),
        ),
        isFalse,
      );
      expect(store.conversationWith('account-bob')!.messages.single.isEdited, isFalse);
    });

    test('a tombstone cannot be brought back by editing it', () {
      final store = storeWith([text('c1')]);
      store.deleteMessage(conversationId: 'account-bob', clientId: 'c1', tombstone: true);
      expect(
        store.editMessage(
          conversationId: 'account-bob',
          clientId: 'c1',
          body: 'wieder da',
          editedAt: DateTime(2026),
        ),
        isFalse,
      );
      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.deleted);
      expect(message.body, isEmpty);
    });

    test('an edit for a message this device does not have is dropped', () {
      final store = storeWith([text('c1')]);
      expect(
        store.editMessage(
          conversationId: 'account-bob',
          clientId: 'missing',
          body: 'x',
          editedAt: DateTime(2026),
        ),
        isFalse,
      );
    });
  });

  group('correcting a message', () {
    test('changes it here and sends the correction', () async {
      final store = storeWith([text('c1', isMine: true, body: 'Treffen um 8')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.editMessage(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
        '  Treffen um 9  ',
      );

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.body, 'Treffen um 9', reason: 'trimmed like any message');
      expect(message.isEdited, isTrue);
      expect(messaging.sent, hasLength(1));
      expect(messaging.sent.single.isEdit, isTrue);
      expect(messaging.sent.single.editTo, 'c1');
      expect(messaging.sent.single.body, 'Treffen um 9');
    });

    test('is refused for a message somebody else wrote', () async {
      final store = storeWith([text('c1', body: 'von Bob')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.editMessage(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
        'umgeschrieben',
      );

      expect(store.conversationWith('account-bob')!.messages.single.body, 'von Bob');
      expect(messaging.sent, isEmpty);
    });

    test('an empty correction is not a way to blank a message', () async {
      final store = storeWith([text('c1', isMine: true, body: 'bleibt')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.editMessage(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
        '   ',
      );

      expect(store.conversationWith('account-bob')!.messages.single.body, 'bleibt');
      expect(messaging.sent, isEmpty);
    });

    test('a send that fails keeps the new text here, and says the other side has the old',
        () async {
      final store = storeWith([text('c1', isMine: true, body: 'alt')]);
      final (services, messaging) = await buildServices(store);
      messaging.failSends = true;
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.editMessage(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
        'neu',
      );

      expect(store.conversationWith('account-bob')!.messages.single.body, 'neu');
      expect(controller.failure?.kind, FailureKind.editedHereOnly);
    });
  });

  group('a correction that arrives', () {
    test('changes the message on this device too', () async {
      final store = storeWith([text('c1', body: 'Treffen um 8')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(editOf('c1', 'Treffen um 9'));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.body, 'Treffen um 9');
      expect(message.isEdited, isTrue);
    });

    test('cannot rewrite a message this account wrote', () async {
      final store = storeWith([text('c1', isMine: true, body: 'was ich schrieb')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(editOf('c1', 'was Bob gern hätte'));
      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages.single.body, 'was ich schrieb');
    });

    test('cannot rewrite a message a third person wrote', () async {
      final store = storeWith([text('c1', author: 'account-carol', body: 'von Carol')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(editOf('c1', 'gefälscht'));
      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages.single.body, 'von Carol');
    });

    test('an empty correction is ignored rather than read as a deletion', () async {
      final store = storeWith([text('c1', body: 'bleibt')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(editOf('c1', ''));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.body, 'bleibt');
      expect(message.kind, MessageKind.text);
    });

    test('never becomes a bubble of its own', () async {
      final store = storeWith([text('c1')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(editOf('nothing-here', 'neu'));
      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages, hasLength(1));
    });
  });

  test('the edited mark survives the archive', () async {
    final store = storeWith([text('c1', isMine: true, body: 'alt')]);
    store.editMessage(
      conversationId: 'account-bob',
      clientId: 'c1',
      body: 'neu',
      editedAt: DateTime(2026, 1, 1, 13),
    );
    final archive = EncryptedMessageArchive(
      storage: InMemoryArchiveStorage(),
      keyStore: InMemorySecureStore(),
    );
    await archive.save(store.conversations());

    final restored = (await archive.load()).conversations.single.messages.single;
    expect(restored.body, 'neu');
    expect(restored.editedAt, DateTime(2026, 1, 1, 13));
  });

  testWidgets('an edited message says so beside its time, in the reader\'s language',
      (tester) async {
    Future<void> show(Message message, Locale locale) => tester.pumpWidget(
          MaterialApp(
            theme: PrivioTheme.dark(),
            locale: locale,
            localizationsDelegates: AppText.localizationsDelegates,
            supportedLocales: AppText.supportedLocales,
            home: Scaffold(body: MessageBubble(message: message)),
          ),
        );
    final original = text('c1', body: 'Treffen um 9');

    await show(original, const Locale('de'));
    expect(find.text('bearbeitet'), findsNothing);

    final edited = original.copyWith(body: 'Treffen um 10', editedAt: DateTime(2026, 1, 1, 13));
    await show(edited, const Locale('de'));
    expect(find.text('Treffen um 10'), findsOneWidget);
    expect(find.text('bearbeitet'), findsOneWidget);

    await show(edited, const Locale('fr'));
    expect(find.text('modifié'), findsOneWidget);
  });
}
