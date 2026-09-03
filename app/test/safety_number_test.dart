import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/crypto/safety_number.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;

/// Seals one message each way, which is what pins the identity keys on both
/// sides — a safety number has nothing to show before anyone has talked.
Future<void> introduce(FakeKeyServer server, TestDevice from, TestDevice to) async {
  final bundle = DeviceBundle.fromJson(server.bundleFor(to.accountId, to.deviceIndex));
  final sealed = await from.crypto.sealForDevices(
    accountId: to.accountId,
    devices: [bundle],
    plaintext: 'hallo',
  );
  await to.crypto.openEnvelope(
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
    await alice.boot(server);
    await bob.boot(server);
    await introduce(server, alice, bob);
    await introduce(server, bob, alice);
  });

  Future<SafetyNumbers> aliceOnBob() => alice.crypto.safetyNumbers(
        localAccountId: alice.accountId,
        remoteAccountId: bob.accountId,
      );

  Future<SafetyNumbers> bobOnAlice() => bob.crypto.safetyNumbers(
        localAccountId: bob.accountId,
        remoteAccountId: alice.accountId,
      );

  test('both people see the same digits', () async {
    final mine = await aliceOnBob();
    final theirs = await bobOnAlice();

    expect(mine.numbers, hasLength(1));
    expect(theirs.numbers, hasLength(1));
    // The whole point: two devices that never exchanged this number arrive at
    // it independently, so reading it aloud proves the keys match.
    expect(mine.numbers.single.digits, theirs.numbers.single.digits);
    expect(mine.numbers.single.digits, hasLength(60));
    expect(mine.numbers.single.digits, matches(RegExp(r'^[0-9]{60}$')));
  });

  test('a different pair of people gets a different number', () async {
    final carol = TestDevice('account-carol', 'device-carol-1', 1);
    await carol.boot(server);
    await introduce(server, alice, carol);

    final onBob = await aliceOnBob();
    final onCarol = await alice.crypto.safetyNumbers(
      localAccountId: alice.accountId,
      remoteAccountId: carol.accountId,
    );
    expect(onCarol.numbers.single.digits, isNot(onBob.numbers.single.digits));
  });

  test('the number is read in twelve groups of five', () async {
    final number = (await aliceOnBob()).numbers.single;
    final groups = number.formatted.split(' ');
    expect(groups, hasLength(12));
    expect(groups.every((g) => g.length == 5), isTrue);
    expect(groups.join(), number.digits);
  });

  test('comparing ignores how the other side spaced or pasted it', () async {
    final number = (await aliceOnBob()).numbers.single;
    expect(number.matches(number.formatted), isTrue);
    expect(number.matches(number.digits), isTrue);
    expect(number.matches('  ${number.formatted}\n'), isTrue);
    expect(number.matches(number.digits.replaceRange(0, 1, '9')), isFalse);
    expect(number.matches(number.digits.substring(1)), isFalse,
        reason: 'a truncated number is not a match',
    );
  });

  test('a conversation starts unverified and stays verified once checked', () async {
    expect((await aliceOnBob()).state, VerificationState.unverified);

    final numbers = await aliceOnBob();
    await alice.crypto.markVerified(bob.accountId, numbers);
    expect((await aliceOnBob()).state, VerificationState.verified);

    await alice.crypto.clearVerified(bob.accountId);
    expect((await aliceOnBob()).state, VerificationState.unverified);
  });

  test('a changed identity key breaks the verification it was checked at', () async {
    await alice.crypto.markVerified(bob.accountId, await aliceOnBob());

    // Bob reinstalls: same account, same device index, a brand-new identity.
    final reinstalled = TestDevice(bob.accountId, bob.deviceId, bob.deviceIndex);
    await reinstalled.boot(server);
    await alice.crypto.acceptIdentityChange(bob.accountId, bob.deviceIndex);
    await alice.crypto.store.deleteSession(
      SignalProtocolAddress(bob.accountId, bob.deviceIndex),
    );
    await introduce(server, alice, reinstalled);

    final after = await aliceOnBob();
    expect(after.numbers.single.digits, isNot(hasLength(0)));
    expect(after.state, VerificationState.unverified,
        reason: 'accepting a change also drops what was verified before it',
    );
  });

  test('a device appearing on a verified account breaks the verification', () async {
    await alice.crypto.markVerified(bob.accountId, await aliceOnBob());

    // The case a per-key check would miss: nothing Alice pinned changed. A
    // second device simply joined Bob's account — which is also what a server
    // adding a device of its own would look like.
    final bobsLaptop = TestDevice(bob.accountId, 'device-bob-2', 2);
    await bobsLaptop.boot(server);
    await introduce(server, alice, bobsLaptop);

    final after = await aliceOnBob();
    expect(after.numbers, hasLength(2));
    expect(after.state, VerificationState.changed);
    expect(
      after.numbers.map((n) => n.digits).toSet(),
      hasLength(2),
      reason: 'each device of the same account has its own number',
    );
  });

  test('a key that arrives with a message is reported, not swallowed', () async {
    expect(alice.crypto.takeIdentityReplacements(), isEmpty,
        reason: 'the first pin is not a change',
    );

    // Bob reinstalls and writes. Refusing this would let anyone silence a
    // conversation by sending one message, so it is accepted — and reported.
    final reinstalled = TestDevice(bob.accountId, bob.deviceId, bob.deviceIndex);
    await reinstalled.boot(server);
    await introduce(server, reinstalled, alice);

    final reported = alice.crypto.takeIdentityReplacements();
    expect(reported, hasLength(1));
    expect(reported.single.accountId, bob.accountId);
    expect(reported.single.deviceIndex, bob.deviceIndex);

    // Drained, so the same change is not reported twice.
    expect(alice.crypto.takeIdentityReplacements(), isEmpty);
  });

  test('a reported change outlives a restart until it is answered', () async {
    final reinstalled = TestDevice(bob.accountId, bob.deviceId, bob.deviceIndex);
    await reinstalled.boot(server);
    await introduce(server, reinstalled, alice);

    for (final change in alice.crypto.takeIdentityReplacements()) {
      await alice.crypto.raiseKeyChangeAlert(change.accountId);
    }

    // Same storage, fresh instance: what relaunching the app does.
    final reopened = await PrivioCrypto.open(alice.storage);
    expect(await reopened.keyChangeAlerts(), {bob.accountId});

    await reopened.clearKeyChangeAlert(bob.accountId);
    expect(await reopened.keyChangeAlerts(), isEmpty);
  });

  test('the changed key is what the number is computed from afterwards', () async {
    final before = (await aliceOnBob()).numbers.single.digits;

    final reinstalled = TestDevice(bob.accountId, bob.deviceId, bob.deviceIndex);
    await reinstalled.boot(server);
    await introduce(server, reinstalled, alice);

    final after = (await aliceOnBob()).numbers.single.digits;
    expect(after, isNot(before),
        reason: 'a number that did not move would hide the change it exists to show',
    );

    // And it is the number the other side now sees.
    await introduce(server, alice, reinstalled);
    final theirs = await reinstalled.crypto.safetyNumbers(
      localAccountId: bob.accountId,
      remoteAccountId: alice.accountId,
    );
    expect(theirs.numbers.single.digits, after);
  });

  test('nothing to compare before a first message', () async {
    final stranger = TestDevice('account-stranger', 'device-stranger-1', 1);
    await stranger.boot(server);

    final numbers = await alice.crypto.safetyNumbers(
      localAccountId: alice.accountId,
      remoteAccountId: stranger.accountId,
    );
    expect(numbers.isEmpty, isTrue);
    expect(numbers.state, VerificationState.unverified);
  });
}
