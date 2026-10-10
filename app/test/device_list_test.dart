import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// A conversation is not a prekey fetch per message.
///
/// Seen between two accounts in a browser: after a few minutes of quick
/// messages the server answered "too many requests" for the other person's
/// keys. Every direct send fetched their prekey bundles — message, typing
/// notice, receipt, and once more for the copy to this account's own devices.
/// The server allows sixty fetches an hour, and each one uses up one of the
/// recipient's one-time prekeys.
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
  });

  test('a conversation fetches the other side\'s keys once', () async {
    for (var i = 0; i < 10; i++) {
      await alice.messaging.sendToUser('bob', 'Nachricht $i');
    }
    expect(server.bundleFetches['bob'], 1);
    expect(
      server.bundleFetches['alice'],
      1,
      reason: '"no other devices of mine" is remembered, not asked ten times',
    );
    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty);
    expect(received.messages, hasLength(10));
  });

  test('a new device of theirs is found by the server\'s correction, and gets the message',
      () async {
    await alice.messaging.sendToUser('bob', 'vorher');
    await bob.messaging.receive();

    // Bob signs in on a second phone.
    final bobsTablet = Participant('bob', 'account-bob', 2);
    await bobsTablet.join(server);

    await alice.messaging.sendToUser('bob', 'nachher');
    expect(server.bundleFetches['bob'], 2, reason: 'fetched again only because the list was out of date');
    expect((await bob.messaging.receive()).messages.single.body, 'nachher');
    expect((await bobsTablet.messaging.receive()).messages.single.body, 'nachher');
  });

  test('a session that was reset is opened again from fresh keys', () async {
    await alice.messaging.sendToUser('bob', 'eins');
    await bob.messaging.receive();

    await alice.crypto.resetSession(bob.accountId, 1);
    await alice.messaging.sendToUser('bob', 'zwei');

    expect(server.bundleFetches['bob'], 2);
    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty);
    expect(received.messages.single.body, 'zwei');
  });
}
