import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/crypto/privio_signal_store.dart';

/// Stands in for the server: holds the published key material and hands out
/// bundles the way `GET /v1/keys/:username` does, consuming a one-time prekey
/// each time.
class FakeKeyServer {
  final Map<String, Map<String, dynamic>> _registrations = {};

  void register(String accountId, String deviceId, int deviceIndex, Map<String, dynamic> payload) {
    _registrations['$accountId.$deviceIndex'] = {
      'deviceId': deviceId,
      'deviceIndex': deviceIndex,
      ...payload,
    };
  }

  Map<String, dynamic> bundleFor(String accountId, int deviceIndex) {
    final entry = _registrations['$accountId.$deviceIndex']!;
    final preKeys = entry['oneTimePreKeys'] as List<dynamic>;
    // Consumed on handout, exactly as the server deletes it.
    final preKey = preKeys.isEmpty ? null : preKeys.removeAt(0) as Map<String, dynamic>;
    return {
      'deviceId': entry['deviceId'],
      'deviceIndex': entry['deviceIndex'],
      'registrationId': entry['registrationId'],
      'identityKey': entry['identityKey'],
      'signedPreKey': entry['signedPreKey'],
      'oneTimePreKey': preKey,
    };
  }

  int remainingPreKeys(String accountId, int deviceIndex) =>
      (_registrations['$accountId.$deviceIndex']!['oneTimePreKeys'] as List<dynamic>).length;
}

/// One device: its own storage, its own crypto, its own identity.
class TestDevice {
  TestDevice(this.accountId, this.deviceId, this.deviceIndex);

  final String accountId;
  final String deviceId;
  final int deviceIndex;
  final CryptoStorage storage = InMemoryCryptoStorage();
  late PrivioCrypto crypto;

  Future<Map<String, dynamic>> boot(FakeKeyServer server, {int preKeys = 5}) async {
    crypto = await PrivioCrypto.open(storage);
    final payload = await crypto.buildRegistration(
      name: 'Test $deviceIndex',
      platform: 'ios',
      preKeyCount: preKeys,
    );
    server.register(accountId, deviceId, deviceIndex, payload);
    return payload;
  }
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
  });

  test('registration publishes public keys and no private ones', () async {
    final payload = await TestDevice('account-carol', 'device-carol-1', 1).boot(server);

    expect(payload['identityKey'], isA<String>());
    expect(payload['signedPreKey']['signature'], isA<String>());
    expect((payload['oneTimePreKeys'] as List<dynamic>).length, 5);

    // Nothing published may decrypt anything: assert the payload carries only
    // the fields the server is allowed to see.
    expect(
      payload.keys.toSet(),
      {'name', 'platform', 'registrationId', 'identityKey', 'signedPreKey', 'oneTimePreKeys'},
    );
    expect((payload['signedPreKey'] as Map).keys.toSet(), {'keyId', 'publicKey', 'signature'});
  });

  test('Alice seals a message that only Bob can open', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'Treffen um 19 Uhr',
    );

    expect(sealed, hasLength(1));
    expect(sealed.single.type, 'prekey', reason: 'the first message opens the session');
    expect(sealed.single.deviceId, bob.deviceId);

    // What the server would store must not contain the message.
    expect(utf8.decode(base64Decode(sealed.single.content), allowMalformed: true),
        isNot(contains('Treffen')),);

    final opened = await bob.crypto.openEnvelope(
      senderAccountId: alice.accountId,
      senderDeviceIndex: alice.deviceIndex,
      type: sealed.single.type,
      content: sealed.single.content,
    );
    expect(opened, 'Treffen um 19 Uhr');
  });

  test('a third party with the ciphertext cannot open it', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'nur für Bob',
    );

    final mallory = TestDevice('account-mallory', 'device-mallory-1', 1);
    await mallory.boot(server);

    await expectLater(
      mallory.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: sealed.single.type,
        content: sealed.single.content,
      ),
      throwsA(isA<Exception>()),
      reason: 'holding the ciphertext is not enough — the server holds exactly this',
    );
  });

  test('the ratchet moves forward: every message gets a different ciphertext', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    await alice.crypto.ensureSession(bob.accountId, bundle);

    final first = await alice.crypto.seal(
      accountId: bob.accountId,
      deviceId: bob.deviceId,
      deviceIndex: bob.deviceIndex,
      registrationId: bundle.registrationId,
      plaintext: 'same text',
    );
    final second = await alice.crypto.seal(
      accountId: bob.accountId,
      deviceId: bob.deviceId,
      deviceIndex: bob.deviceIndex,
      registrationId: bundle.registrationId,
      plaintext: 'same text',
    );

    expect(first.content, isNot(second.content),
        reason: 'identical plaintext must never produce identical ciphertext',);

    expect(
      await bob.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: first.type,
        content: first.content,
      ),
      'same text',
    );
    expect(
      await bob.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: second.type,
        content: second.content,
      ),
      'same text',
    );
  });

  test('a conversation runs in both directions', () async {
    final bobBundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final fromAlice = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bobBundle],
      plaintext: 'Hey!',
    );
    await bob.crypto.openEnvelope(
      senderAccountId: alice.accountId,
      senderDeviceIndex: alice.deviceIndex,
      type: fromAlice.single.type,
      content: fromAlice.single.content,
    );

    // Bob answers without fetching a bundle: the incoming message established
    // his side of the session.
    final reply = await bob.crypto.seal(
      accountId: alice.accountId,
      deviceId: alice.deviceId,
      deviceIndex: alice.deviceIndex,
      registrationId: 0,
      plaintext: 'Alles gut!',
    );
    expect(reply.type, 'ciphertext');

    expect(
      await alice.crypto.openEnvelope(
        senderAccountId: bob.accountId,
        senderDeviceIndex: bob.deviceIndex,
        type: reply.type,
        content: reply.content,
      ),
      'Alles gut!',
    );
  });

  test('tampering with one byte of ciphertext is rejected', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'Überweise 100 Euro',
    );

    final bytes = base64Decode(sealed.single.content);
    bytes[bytes.length - 12] ^= 0x01;

    await expectLater(
      bob.crypto.openEnvelope(
        senderAccountId: alice.accountId,
        senderDeviceIndex: alice.deviceIndex,
        type: sealed.single.type,
        content: base64Encode(bytes),
      ),
      throwsA(isA<Exception>()),
      reason: 'a modified message must not decrypt to anything',
    );
  });

  test('each one-time prekey is handed out once', () async {
    final before = server.remainingPreKeys(bob.accountId, bob.deviceIndex);
    final first = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final second = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));

    expect(first.preKeyId, isNot(second.preKeyId));
    expect(server.remainingPreKeys(bob.accountId, bob.deviceIndex), before - 2);
  });

  test('a used one-time prekey is deleted from the recipient store', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    final usedPreKeyId = bundle.preKeyId!;
    expect(await bob.crypto.store.containsPreKey(usedPreKeyId), isTrue);

    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: [bundle],
      plaintext: 'first contact',
    );
    await bob.crypto.openEnvelope(
      senderAccountId: alice.accountId,
      senderDeviceIndex: alice.deviceIndex,
      type: sealed.single.type,
      content: sealed.single.content,
    );

    expect(
      await bob.crypto.store.containsPreKey(usedPreKeyId),
      isFalse,
      reason: 'reusing a one-time prekey would break forward secrecy',
    );
  });

  test('multi-device sends one distinct copy per device', () async {
    final bobLaptop = TestDevice(bob.accountId, 'device-bob-2', 2);
    await bobLaptop.boot(server);

    final devices = [
      DeviceBundle.fromJson(server.bundleFor(bob.accountId, 1)),
      DeviceBundle.fromJson(server.bundleFor(bob.accountId, 2)),
    ];
    final sealed = await alice.crypto.sealForDevices(
      accountId: bob.accountId,
      devices: devices,
      plaintext: 'auf beiden Geräten',
    );

    expect(sealed, hasLength(2));
    expect(sealed[0].content, isNot(sealed[1].content));
    expect(sealed.map((c) => c.deviceId), ['device-bob-1', 'device-bob-2']);

    for (final (index, device) in [bob, bobLaptop].indexed) {
      expect(
        await device.crypto.openEnvelope(
          senderAccountId: alice.accountId,
          senderDeviceIndex: alice.deviceIndex,
          type: sealed[index].type,
          content: sealed[index].content,
        ),
        'auf beiden Geräten',
      );
    }
  });

  test('a swapped identity key is refused on send', () async {
    final real = server.bundleFor(bob.accountId, bob.deviceIndex);
    await alice.crypto.ensureSession(bob.accountId, DeviceBundle.fromJson(real));

    // A hostile server hands out someone else's identity key for Bob's device.
    final impostor = TestDevice('account-impostor', 'device-impostor-1', 1);
    await impostor.boot(server);
    final forged = {
      ...server.bundleFor(bob.accountId, bob.deviceIndex),
      'identityKey': server.bundleFor(impostor.accountId, 1)['identityKey'],
    };

    // The session already exists, so re-pinning must be what fails.
    await alice.crypto.store.deleteSession(
      SignalProtocolAddress(bob.accountId, bob.deviceIndex),
    );

    await expectLater(
      alice.crypto.ensureSession(bob.accountId, DeviceBundle.fromJson(forged)),
      throwsA(isA<IdentityChangedException>()),
      reason: 'a key change must surface, never be accepted silently',
    );
  });

  test('the identity survives a restart of the app', () async {
    final fingerprint = await alice.crypto.identityFingerprint();

    // Same storage, fresh crypto instance — this is what relaunching does.
    final reopened = await PrivioCrypto.open(alice.storage);
    expect(await reopened.identityFingerprint(), fingerprint);

    final store = await PrivioSignalStore.open(alice.storage);
    expect(store, isNotNull);
  });
  test('ciphertext length does not reveal how much was written', () async {
    final bundle = DeviceBundle.fromJson(server.bundleFor(bob.accountId, bob.deviceIndex));
    await alice.crypto.ensureSession(bob.accountId, bundle);

    Future<int> lengthOf(String text) async {
      final sealed = await alice.crypto.seal(
        accountId: bob.accountId,
        deviceId: bob.deviceId,
        deviceIndex: bob.deviceIndex,
        registrationId: bundle.registrationId,
        plaintext: text,
      );
      return base64Decode(sealed.content).length;
    }

    final short = await lengthOf('ja');
    final longer = await lengthOf(
      'Ich komme heute etwas spaeter, warte bitte nicht auf mich mit dem Essen.',
    );

    expect(
      short,
      longer,
      reason: 'a yes and a paragraph must look the same to the server',
    );
  });
}
