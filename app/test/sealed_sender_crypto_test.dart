import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart' as rs;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/crypto/sealed_sender.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;

/// Sealing and opening, in the app's own crypto layer, between two devices
/// with real Signal sessions. The library underneath is tested in
/// `sealed_sender_library_test.dart`; this is what Privio builds on it.

const aliceId = '9d0652a3-dcc3-4d11-975f-74d61598733f';
const bobId = '1b9e5a55-6c2a-4d1e-8a0f-2b7f8a6e1c11';

/// A server's trust root and its way of issuing sender certificates, made
/// with the library's own Rust side, as `server/src/services/sealed_sender.ts`
/// does with the TypeScript one.
class FakeIssuer {
  FakeIssuer() {
    final root = Curve.generateKeyPair();
    _server = Curve.generateKeyPair();
    trustRoot = root.publicKey.serialize();
    _serverCertificate = rs.createServerCertificate(
      keyId: 1,
      serverPublicKey: _server.publicKey.serialize(),
      trustRootPrivateKey: root.privateKey.serialize(),
    );
  }

  late final Uint8List trustRoot;
  late final ECKeyPair _server;
  late final Uint8List _serverCertificate;

  Future<Uint8List> issue(TestDevice device, {Duration validFor = const Duration(hours: 24)}) async {
    final identity = await device.crypto.store.getIdentityKeyPair();
    return rs.createSenderCertificate(
      senderUuid: device.accountId,
      senderDeviceId: device.deviceIndex,
      senderIdentityKey: identity.getPublicKey().serialize(),
      expiration: BigInt.from(DateTime.now().add(validFor).millisecondsSinceEpoch),
      serverCertificate: _serverCertificate,
      serverPrivateKey: _server.privateKey.serialize(),
    );
  }
}

void main() {
  late FakeKeyServer server;
  late FakeIssuer issuer;
  late TestDevice alice;
  late TestDevice bob;

  setUpAll(() async => expect(await SealedSender.load(), isTrue));

  setUp(() async {
    server = FakeKeyServer();
    issuer = FakeIssuer();
    alice = TestDevice(aliceId, 'device-alice-1', 1);
    bob = TestDevice(bobId, 'device-bob-1', 1);
    await alice.boot(server);
    await bob.boot(server);
  });

  DeviceBundle bobsBundle() => DeviceBundle.fromJson(server.bundleFor(bobId, 1));

  Future<SealedCopy> sealFromAlice(String text, {Uint8List? certificate}) async => (await alice.crypto
          .sealSealedForDevices(
        accountId: bobId,
        devices: [bobsBundle()],
        plaintext: text,
        senderCertificate: certificate ?? await issuer.issue(alice),
      ))
          .single;

  Future<SealedOpened> openAtBob(SealedCopy copy, {Uint8List? trustRoot, DateTime? sentAt}) =>
      bob.crypto.openSealed(
        content: copy.content,
        trustRoot: trustRoot ?? issuer.trustRoot,
        sentAt: sentAt ?? DateTime.now(),
        localAccountId: bobId,
        localDeviceIndex: 1,
      );

  group('a sealed message', () {
    test('opens at the recipient, who learns the sender from inside it', () async {
      final copy = await sealFromAlice('hallo bob');
      expect(copy.type, 'sealed');

      final opened = await openAtBob(copy);
      expect(opened.senderAccountId, aliceId);
      expect(opened.senderDeviceIndex, 1);
      expect(opened.opened.body, 'hallo bob');
      expect(opened.opened.trust, PeerTrust.firstContact);
    });

    test('keeps working once the session is running', () async {
      await openAtBob(await sealFromAlice('eins'));
      final second = await openAtBob(await sealFromAlice('zwei'));
      expect(second.opened.body, 'zwei');
      expect(second.opened.trust, PeerTrust.pinned);
    });

    test('does not carry the sender in the clear', () async {
      final copy = await sealFromAlice('leise');
      final bytes = base64Decode(copy.content);
      expect(latin1.decode(bytes, allowInvalid: true).contains(aliceId), isFalse);
      final key = (await alice.crypto.store.getIdentityKeyPair()).getPublicKey().serialize().sublist(1);
      expect(_contains(bytes, key), isFalse, reason: 'the sender identity key is visible');
    });
  });

  group('refused', () {
    test('a certificate from another server', () async {
      final copy = await sealFromAlice('fremd', certificate: await FakeIssuer().issue(alice));
      await expectLater(openAtBob(copy), throwsA(anything));
    });

    test('a certificate that had run out when the message was sent', () async {
      final copy = await sealFromAlice('alt');
      await expectLater(
        openAtBob(copy, sentAt: DateTime.now().add(const Duration(days: 2))),
        throwsA(anything),
      );
    });

    test('one flipped byte', () async {
      final copy = await sealFromAlice('kaputt');
      final bytes = base64Decode(copy.content);
      bytes[bytes.length ~/ 2] ^= 0x01;
      await expectLater(
        openAtBob(SealedCopy(
          deviceId: copy.deviceId,
          registrationId: copy.registrationId,
          type: copy.type,
          content: base64Encode(bytes),
        )),
        throwsA(anything),
      );
    });

    test('a certificate that names somebody other than the message inside', () async {
      // Mallory's session with Bob, under a certificate for Alice. The outer
      // layer is sealed with Alice's own key, so only this check can catch it.
      final mallory = TestDevice(aliceId, 'device-mallory-1', 1);
      await mallory.boot(server);
      final bundle = bobsBundle();
      await mallory.crypto.ensureSession(bobId, bundle);
      final inner = await mallory.crypto.seal(
        accountId: bobId,
        deviceId: bundle.deviceId,
        deviceIndex: 1,
        registrationId: bundle.registrationId,
        plaintext: 'untergeschoben',
      );
      final usmc = rs.UnidentifiedSenderMessageContent(
        messageType: CiphertextMessage.prekeyType,
        senderCertificate: await issuer.issue(alice),
        contents: base64Decode(inner.content),
        contentHint: 0,
      );
      final aliceIdentity = await alice.crypto.store.getIdentityKeyPair();
      final outer = await rs.sealedSenderEncryptFromUsmcWithCallbacks(
        recipientName: bobId,
        recipientDeviceId: 1,
        usmc: usmc.serialize(),
        getIdentityKeyPair: () => aliceIdentity.serialize(),
        getLocalRegistrationId: () => alice.crypto.store.getLocalRegistrationId(),
        getIdentity: (_, _) => bundle.identityKey,
      );

      await expectLater(
        openAtBob(SealedCopy(deviceId: 'd', registrationId: 1, type: 'sealed', content: base64Encode(outer))),
        throwsA(isA<SealedSenderMismatch>()),
      );
      expect(await bob.crypto.hasSessionWith(aliceId, 1), isFalse,
          reason: 'the refused message changed a session');
    });
  });

  test('a changed key is accepted and reported, as on any other message', () async {
    // Alice reinstalls: same account and device index, a new identity, a new
    // certificate. Refusing her would lose her messages without even saying
    // whose they were.
    await openAtBob(await sealFromAlice('vorher'));

    final reinstalled = TestDevice(aliceId, 'device-alice-1', 1);
    await reinstalled.boot(server);
    final copy = (await reinstalled.crypto.sealSealedForDevices(
      accountId: bobId,
      devices: [bobsBundle()],
      plaintext: 'neu installiert',
      senderCertificate: await issuer.issue(reinstalled),
    ))
        .single;

    final opened = await openAtBob(copy);
    expect(opened.opened.body, 'neu installiert');
    expect(opened.opened.trust, PeerTrust.replaced);
  });

  group('the access key', () {
    test('is sixteen bytes of HKDF-SHA256 over the profile key, always the same', () async {
      final key = await SealedSender.accessKey(List.filled(32, 1));
      expect(key, hasLength(SealedSender.accessKeyLength));
      // Pinned: a recipient and a sender on different versions must still agree.
      expect(base64Encode(key), 'z8ZpFpu+aISrdovYevhPsg==');
      expect(await SealedSender.accessKey(List.filled(32, 2)), isNot(key));
    });
  });

  test('a certificate says whom it vouches for, and until when', () async {
    final certificate = SenderCertificate.parse(
      await issuer.issue(alice, validFor: const Duration(hours: 2)),
    );
    expect(certificate.accountId, aliceId);
    expect(certificate.deviceIndex, 1);
    expect(certificate.isFreshAt(DateTime.now()), isTrue);
    expect(certificate.isFreshAt(DateTime.now().add(const Duration(minutes: 61))), isFalse);
  });
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
