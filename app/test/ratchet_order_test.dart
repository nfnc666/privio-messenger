import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// Session operations run one at a time.
///
/// Seen between two accounts in a browser: "a message from Alice could not be
/// read — it was sealed to a key this device no longer has". Two operations on
/// the same session at once each read the same state and the second write
/// threw the first away — two messages under one key, or a lost ratchet step.
/// A typing notice going out with the message after it is enough.
void main() {
  late FakeServer server;
  late Participant alice;
  late Participant bob;

  setUp(() async {
    server = FakeServer();
    alice = Participant('alice', 'account-alice', 1);
    bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);
    // A session in both directions first, so what follows is the ordinary
    // case of an ongoing conversation.
    await alice.messaging.sendToUser('bob', 'hallo');
    await bob.messaging.receive();
    await bob.messaging.sendToUser('alice', 'hallo zurück');
    await alice.messaging.receive();
  });

  test('messages sent at the same moment can all be read', () async {
    await Future.wait([
      for (var i = 0; i < 5; i++) alice.messaging.sendToUser('bob', 'gleichzeitig $i'),
    ]);

    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty, reason: 'two messages went out under one key');
    expect(
      received.messages.map((m) => m.body).toSet(),
      {for (var i = 0; i < 5; i++) 'gleichzeitig $i'},
    );
  });

  test('sending while a reply is being opened loses nothing', () async {
    for (var i = 0; i < 3; i++) {
      await bob.messaging.sendToUser('alice', 'von bob $i');
    }
    await Future.wait([
      alice.messaging.receive(),
      alice.messaging.sendToUser('bob', 'während des Lesens'),
    ]);
    await alice.messaging.sendToUser('bob', 'danach');

    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty, reason: 'a step of the ratchet was lost');
    expect(received.messages.map((m) => m.body), containsAll(['während des Lesens', 'danach']));
  });
}
