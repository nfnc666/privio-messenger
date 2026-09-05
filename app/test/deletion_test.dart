import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

Message text(
  String clientId, {
  bool isMine = false,
  String body = 'hallo',
  String? author,
}) =>
    Message(
      id: 'envelope-$clientId',
      clientId: clientId,
      body: body,
      sentAt: DateTime(2026, 1, 1, 12),
      isMine: isMine,
      senderAccountId: isMine ? null : (author ?? 'account-bob'),
    );

InMemoryMessageStore storeWith(List<Message> messages) {
  final store = InMemoryMessageStore()
    ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
  for (final message in messages) {
    store.append('account-bob', message);
  }
  return store;
}

/// Sends nothing and receives whatever a test puts in front of it.
class ScriptedMessaging extends MessagingService {
  ScriptedMessaging({required super.api, required super.crypto});

  final List<MessagePayload> sent = [];
  final List<IncomingMessage> inbox = [];
  bool failSends = false;

  @override
  Future<int> sendPayload(String username, MessagePayload payload) async {
    if (failSends) throw ApiException(503, 'unavailable', 'no route to host');
    sent.add(payload);
    return 1;
  }

  @override
  Future<ReceiveResult> receive({int limit = 100}) async {
    final batch = [...inbox];
    inbox.clear();
    return ReceiveResult(batch, const [], false);
  }
}

/// [client] lets a test that needs the server to answer something supply it;
/// the default refuses everything, which is what most of these want.
Future<(PrivioServices, ScriptedMessaging)> buildServices(
  InMemoryMessageStore store, {
  http.Client? client,
}) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: client ??
        MockClient(
          (request) async => http.Response(
            jsonEncode({'error': 'not_found', 'message': request.url.path}),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = ScriptedMessaging(api: api, crypto: crypto);
  final secureStore = InMemorySecureStore();

  return (
    PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      recorder: FakeVoiceRecorder(),
      player: FakeVoicePlayer(),
      store: store,
      secureStore: secureStore,
      backup: BackupService(api: api, store: secureStore, messages: store),
      archive: EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      ),
    ),
    messaging,
  );
}

IncomingMessage deletionOf(String clientId, {String from = 'account-bob'}) =>
    IncomingMessage(
      envelopeId: 1,
      senderAccountId: from,
      payload: MessagePayload.deletion(clientId),
      receivedAt: DateTime(2026, 1, 1, 12, 5),
    );

void main() {
  group('the deletion payload', () {
    test('survives encoding and is never a message', () {
      const payload = MessagePayload.deletion('c1');
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.isDeletion, isTrue);
      expect(decoded.isControl, isTrue, reason: 'it must never appear as a bubble');
      expect(decoded.deleteTo, 'c1');
      expect(decoded.body, isEmpty);
    });

    test('carries nothing but the id of what to forget', () {
      final json = jsonDecode(const MessagePayload.deletion('c1').encode())
          as Map<String, dynamic>;
      expect(json['t'], 'delete');
      expect(json['dt'], 'c1');
      // The empty body is the shape every payload has; what matters is that
      // nothing else rides along — no quote, no media, no timer.
      expect(json.keys.toSet(), {'v', 't', 'b', 'dt'});
      expect(json['b'], isEmpty);
    });
  });

  group('the store', () {
    test('a tombstone keeps its place and carries nothing else', () {
      final store = storeWith([text('c1'), text('c2', isMine: true), text('c3')]);
      store.applyReaction(
        conversationId: 'account-bob',
        targetClientId: 'c2',
        accountId: 'account-alice',
        emoji: '👍',
      );

      expect(
        store.deleteMessage(conversationId: 'account-bob', clientId: 'c2', tombstone: true),
        isTrue,
      );

      final messages = store.conversationWith('account-bob')!.messages;
      expect(
        messages.map((m) => m.clientId),
        ['c1', 'c2', 'c3'],
        reason: 'the gap is where the message was, not at the end',
      );
      final gone = messages[1];
      expect(gone.kind, MessageKind.deleted);
      expect(gone.body, isEmpty);
      expect(gone.reactions, isEmpty);
      expect(gone.isMine, isTrue, reason: 'whose it was is the one thing left');
      expect(gone.sentAt, DateTime(2026, 1, 1, 12));
    });

    test('delete for me leaves nothing at all', () {
      final store = storeWith([text('c1'), text('c2')]);
      expect(
        store.deleteMessage(conversationId: 'account-bob', clientId: 'c2', tombstone: false),
        isTrue,
      );
      expect(store.conversationWith('account-bob')!.messages.map((m) => m.clientId), ['c1']);
    });

    test('deleting the same message twice changes nothing', () {
      final store = storeWith([text('c1')]);
      store.deleteMessage(conversationId: 'account-bob', clientId: 'c1', tombstone: true);
      expect(
        store.deleteMessage(conversationId: 'account-bob', clientId: 'c1', tombstone: true),
        isFalse,
      );
    });

    test('a deletion for a message this device does not have is dropped', () {
      final store = storeWith([text('c1')]);
      expect(
        store.deleteMessage(conversationId: 'account-bob', clientId: 'gone', tombstone: true),
        isFalse,
        reason: 'inventing a tombstone would be inventing a message',
      );
      expect(store.conversationWith('account-bob')!.messages, hasLength(1));
    });
  });

  group('taking a message back', () {
    test('replaces it here and asks the other side to do the same', () async {
      final store = storeWith([text('c1', isMine: true)]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.deleteForEveryone(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
      );

      expect(
        store.conversationWith('account-bob')!.messages.single.kind,
        MessageKind.deleted,
      );
      expect(messaging.sent, hasLength(1));
      expect(messaging.sent.single.isDeletion, isTrue);
      expect(messaging.sent.single.deleteTo, 'c1');
    });

    test('is refused for a message somebody else wrote', () async {
      final store = storeWith([text('c1')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.deleteForEveryone(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
      );

      expect(
        store.conversationWith('account-bob')!.messages.single.kind,
        MessageKind.text,
        reason: 'a protocol that let anyone delete anyone is a way to erase an argument',
      );
      expect(messaging.sent, isEmpty);
    });

    test('deleting for me alone tells nobody', () async {
      final store = storeWith([text('c1', isMine: true)]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.deleteForMe(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
      );

      expect(store.conversationWith('account-bob')!.messages, isEmpty);
      expect(messaging.sent, isEmpty);
    });

    test('a send that fails still leaves it gone here, and says so', () async {
      final store = storeWith([text('c1', isMine: true)]);
      final (services, messaging) = await buildServices(store);
      messaging.failSends = true;
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.deleteForEveryone(
        'account-bob',
        store.conversationWith('account-bob')!.messages.single,
      );

      expect(
        store.conversationWith('account-bob')!.messages.single.kind,
        MessageKind.deleted,
      );
      expect(
        controller.error,
        contains('did not go out'),
        reason: 'the user has to know the other side still has it',
      );
    });
  });

  group('a deletion that arrives', () {
    test('takes the message back on this device too', () async {
      final store = storeWith([text('c1'), text('c2')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(deletionOf('c2'));
      await controller.drain();

      final messages = store.conversationWith('account-bob')!.messages;
      expect(
        messages,
        hasLength(2),
        reason: 'the marker stays in the transcript',
      );
      expect(messages[1].kind, MessageKind.deleted);
      expect(messages[0].kind, MessageKind.text);
    });

    test('cannot take back a message this account wrote', () async {
      final store = storeWith([text('c1', isMine: true, body: 'was ich schrieb')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      // Refusing to *send* one of these keeps this app honest and does nothing
      // about a modified one, so the rule is checked here too.
      messaging.inbox.add(deletionOf('c1'));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.text);
      expect(message.body, 'was ich schrieb');
    });

    test('cannot take back a message a third person wrote', () async {
      final store = storeWith([text('c1', author: 'account-carol')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(deletionOf('c1'));
      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages.single.kind, MessageKind.text);
    });

    test('never becomes a bubble of its own', () async {
      final store = storeWith([text('c1')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(deletionOf('nothing-here'));
      await controller.drain();

      expect(store.conversationWith('account-bob')!.messages, hasLength(1));
      expect(store.conversationWith('account-bob')!.messages.single.kind, MessageKind.text);
    });
  });

  group('clearing the history on this device', () {
    test('empties the store and the archive, and keeps the keys', () async {
      final store = storeWith([text('c1', isMine: true), text('c2')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await services.archive.save(store.conversations());
      expect(await services.archive.sizeInBytes(), greaterThan(0));
      final identity = await services.crypto.identityFingerprint();

      await controller.clearHistory();

      expect(store.conversations(), isEmpty);
      expect(await services.archive.sizeInBytes(), 0);
      expect((await services.archive.load()).conversations, isEmpty);
      expect(messaging.sent, isEmpty, reason: 'nobody else is told');
      expect(
        await services.crypto.identityFingerprint(),
        identity,
        reason: 'this is not the wipe: the account and its keys stay',
      );
    });

    test('what it costs is measured from the things that hold it', () async {
      final store = storeWith([text('c1'), text('c2')]);
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await services.archive.save(store.conversations());
      final size = await controller.historySize();
      expect(size.conversations, 1);
      expect(size.messages, 2);
      expect(size.sealedBytes, greaterThan(0));

      await controller.clearHistory();
      final after = await controller.historySize();
      expect(after, (sealedBytes: 0, messages: 0, conversations: 0));
    });
  });

  test('who wrote a message survives the archive, so a deletion can be checked',
      () async {
    final store = storeWith([text('c1', author: 'account-carol')]);
    final archive = EncryptedMessageArchive(
      storage: InMemoryArchiveStorage(),
      keyStore: InMemorySecureStore(),
    );
    await archive.save(store.conversations());

    final restored = (await archive.load()).conversations.single;
    expect(restored.messages.single.senderAccountId, 'account-carol');
  });

  test('a tombstone survives being written to the archive and read back', () async {
    final store = storeWith([text('c1', isMine: true), text('c2')]);
    store.deleteMessage(conversationId: 'account-bob', clientId: 'c1', tombstone: true);

    final storage = InMemoryArchiveStorage();
    final archive = EncryptedMessageArchive(
      storage: storage,
      keyStore: InMemorySecureStore(),
    );
    await archive.save(store.conversations());

    final restored = (await archive.load()).conversations.single;
    expect(restored.messages.first.kind, MessageKind.deleted);
    expect(restored.messages.first.body, isEmpty);
  });
}
