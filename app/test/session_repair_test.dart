import 'package:flutter_test/flutter_test.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/media/attachment.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;

/// Seals [text] from [from] to [to] and opens it there, returning what arrived.
Future<String> deliver(
  TestDevice from,
  TestDevice to,
  FakeKeyServer server,
  String text,
) async {
  final bundle = DeviceBundle.fromJson(server.bundleFor(to.accountId, to.deviceIndex));
  final sealed = await from.crypto.sealForDevices(
    accountId: to.accountId,
    devices: [bundle],
    plaintext: text,
  );
  return to.crypto.openEnvelope(
    senderAccountId: from.accountId,
    senderDeviceIndex: from.deviceIndex,
    type: sealed.single.type,
    content: sealed.single.content,
  );
}

void main() {
  late FakeKeyServer server;
  late TestDevice alice;
  late TestDevice bob;

  setUp(() async {
    server = FakeKeyServer();
    alice = TestDevice('account-alice', 'device-alice-1', 1);
    bob = TestDevice('account-bob', 'device-bob-1', 1);
    await alice.boot(server, preKeys: 10);
    await bob.boot(server, preKeys: 10);
  });

  test('a broken session stays broken until something resets it', () async {
    expect(await deliver(alice, bob, server, 'erste'), 'erste');

    // Bob reinstalls: same account and device index, a brand-new identity and
    // no session. This is what a restore, a reinstall or a wiped device looks
    // like from Alice's side, and it is the case that used to end the
    // conversation for good.
    bob = TestDevice('account-bob', 'device-bob-1', 1);
    await bob.boot(server, preKeys: 10);

    // Alice still holds the old session, so she seals to a ratchet that is gone.
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final stale = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'kommt nicht an',
    );
    await expectLater(
      bob.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: stale.single.type,
        content: stale.single.content,
      ),
      throwsA(anything),
      reason: 'the message is lost — that part cannot be undone',
    );
  });

  test('the side that cannot read resets, and both directions work again',
      () async {
    expect(await deliver(alice, bob, server, 'erste'), 'erste');

    bob = TestDevice('account-bob', 'device-bob-1', 1);
    await bob.boot(server, preKeys: 10);

    // Bob receives something he cannot open, throws his side away, and sends
    // the reset. With no session left it goes out as a prekey message, which
    // is the whole repair: Alice archives her old state on opening it.
    await bob.crypto.resetSession(alice.accountId, alice.deviceIndex);
    final aliceBundle =
        DeviceBundle.fromJson(server.bundleFor(alice.accountId, alice.deviceIndex));
    final reset = await bob.crypto.sealForDevices(
      accountId: alice.accountId,
      devices: [aliceBundle],
      plaintext: const MessagePayload.sessionReset().encode(),
    );
    expect(reset.single.type, 'prekey', reason: 'a reset is a fresh handshake');

    final arrived = await alice.crypto.openEnvelope(
      senderAccountId: bob.accountId,
      senderDeviceIndex: bob.deviceIndex,
      type: reset.single.type,
      content: reset.single.content,
    );
    expect(MessagePayload.decode(arrived).isSessionReset, isTrue);

    // Alice → Bob is the direction that was broken. It is the one that has to
    // work now, and it does without her doing anything.
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'jetzt wieder',
    );
    expect(
      await bob.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: sealed.single.type,
        content: sealed.single.content,
      ),
      'jetzt wieder',
    );

    // And so does Bob → Alice, on the same new session.
    expect(await deliver(bob, alice, server, 'und zurück'), 'und zurück');
  });

  test('a reset is machinery: it carries nothing and shows nothing', () {
    const payload = MessagePayload.sessionReset();
    expect(payload.isSessionReset, isTrue);
    expect(payload.isControl, isTrue, reason: 'it must never become a bubble');
    expect(payload.body, isEmpty);
    expect(MessagePayload.decode(payload.encode()).isSessionReset, isTrue);
  });
}
