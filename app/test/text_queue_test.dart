import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';

import 'support/fake_server.dart';
import 'support/fake_voice.dart';

/// A text message written without a connection waits, and goes when it can.
///
/// Found by switching the server off in the middle of a conversation in a
/// browser: the message went straight to "could not be sent", stayed that way
/// after the server came back, and there was no way to send it again but to
/// type it again.
void main() {
  late FakeServer server;
  late Participant alice;
  late Participant bob;
  late InMemoryMessageStore store;
  late ConversationController alices;

  setUp(() async {
    server = FakeServer();
    alice = Participant('alice', 'account-alice', 1);
    bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);
    store = InMemoryMessageStore()
      ..upsertUser(KnownUser(accountId: bob.accountId, username: bob.username));
    alices = ConversationController(
      PrivioServices(
        api: alice.api,
        crypto: alice.crypto,
        messaging: alice.messaging,
        channels: ChannelService(api: alice.api, crypto: alice.crypto, messaging: alice.messaging),
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(
          api: alice.api,
          store: InMemorySecureStore(),
          messages: InMemoryMessageStore(),
        ),
        store: store,
        secureStore: InMemorySecureStore(),
      ),
    )..accountId = alice.accountId;
    addTearDown(alices.stop);
  });

  Message only() => store.conversationWith(bob.accountId)!.messages.single;

  test('without a connection it waits instead of failing, and goes when the server is back',
      () async {
    server.offline = true;
    await alices.send(bob.accountId, 'ohne Netz geschrieben');

    expect(only().state, DeliveryState.queued);
    expect(alices.failure, isNull, reason: 'waiting for a network is not an error');
    expect(alices.isQueued(only().clientId!), isTrue, reason: 'and it can be sent or dropped');

    server.offline = false;
    await alices.flushOutbox();

    expect(only().state, DeliveryState.sent);
    final received = await bob.messaging.receive();
    expect(received.messages.map((m) => m.body), ['ohne Netz geschrieben']);
    await alices.flushOutbox();
    expect((await bob.messaging.receive()).messages, isEmpty, reason: 'sent once, not twice');
  });

  test('a refusal is a failure, and "Try again" sends it once the cause is gone', () async {
    server.refuseSendsWith = 'license_required';
    await alices.send(bob.accountId, 'abgelehnt');

    expect(only().state, DeliveryState.failed);
    expect(alices.failure, isNotNull);
    await alices.flushOutbox();
    expect(only().state, DeliveryState.failed, reason: 'a refusal is not retried by itself');
    expect(alices.isQueued(only().clientId!), isTrue, reason: 'but it can be retried');

    server.refuseSendsWith = null;
    await alices.retry(only().clientId!);
    expect(only().state, DeliveryState.sent);
    expect((await bob.messaging.receive()).messages.single.body, 'abgelehnt');
  });

  test('a message nobody wants to send any more can be dropped', () async {
    server.offline = true;
    await alices.send(bob.accountId, 'doch nicht');
    alices.discard(only().clientId!);
    expect(store.conversationWith(bob.accountId)!.messages, isEmpty);

    server.offline = false;
    await alices.flushOutbox();
    expect((await bob.messaging.receive()).messages, isEmpty);
  });
}
