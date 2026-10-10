import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';

import 'support/fake_server.dart';
import 'support/fake_voice.dart';

/// "typing…" ends when the message it announced arrives.
///
/// Seen in a browser with two accounts: the reply was on screen and the
/// header still said its author was typing it, until the notice timed out.
void main() {
  test("a message ends its sender's typing notice", () async {
    final server = FakeServer();
    final alice = Participant('alice', 'account-alice', 1);
    final bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);

    final store = InMemoryMessageStore()
      ..upsertUser(KnownUser(accountId: alice.accountId, username: alice.username));
    final controller = ConversationController(
      PrivioServices(
        api: bob.api,
        crypto: bob.crypto,
        messaging: bob.messaging,
        channels: ChannelService(api: bob.api, crypto: bob.crypto, messaging: bob.messaging),
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(
          api: bob.api,
          store: InMemorySecureStore(),
          messages: InMemoryMessageStore(),
        ),
        store: store,
        secureStore: InMemorySecureStore(),
      ),
    )..accountId = bob.accountId;
    addTearDown(controller.stop);

    await alice.messaging.sendTyping(bob.username);
    await controller.drain();
    expect(controller.isTyping(alice.accountId), isTrue, reason: 'the notice arrived');

    await alice.messaging.sendToUser(bob.username, 'fertig getippt');
    await controller.drain();
    expect(
      store.conversationWith(alice.accountId)!.messages.map((m) => m.body),
      contains('fertig getippt'),
    );
    expect(controller.isTyping(alice.accountId), isFalse);
  });
}
