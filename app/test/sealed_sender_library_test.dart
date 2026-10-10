import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart' as rs;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Sealed sender's building blocks, as the app will use them.
///
/// Not the feature yet — nothing in the app seals a message today — but the
/// thing the feature stands on: Signal's libsignal, built from source by
/// `app/scripts/build_libsignal.sh` and loaded through the vendored binding's
/// build hook, sealing a message that the app's *existing* Signal sessions
/// encrypted, and opening it again. If this test runs, the library was found,
/// loaded and called; if the hook could not find a library built from source,
/// it fails the build before any of this. See docs/sealed-sender.md.
const _aliceId = '9d0652a3-dcc3-4d11-975f-74d61598733f';
const _bobId = '1b9e5a55-6c2a-4d1e-8a0f-2b7f8a6e1c11';

void main() {
  late InMemorySignalProtocolStore alice;
  late InMemorySignalProtocolStore bob;
  late IdentityKeyPair aliceIdentity;
  late IdentityKeyPair bobIdentity;
  late Uint8List trustRoot;
  late Uint8List certificate;
  late Uint8List foreignCertificate;

  /// A server's trust root, server certificate and a sender certificate for
  /// Alice. The real ones come from the server (`@signalapp/libsignal-client`);
  /// these are made with the same library's Rust side, which is all a test of
  /// the client needs.
  ({Uint8List root, Uint8List cert}) issueFor(IdentityKeyPair sender) {
    final rootPair = Curve.generateKeyPair();
    final serverPair = Curve.generateKeyPair();
    final serverCert = rs.createServerCertificate(
      keyId: 1,
      serverPublicKey: serverPair.publicKey.serialize(),
      trustRootPrivateKey: rootPair.privateKey.serialize(),
    );
    final cert = rs.createSenderCertificate(
      senderUuid: _aliceId,
      senderDeviceId: 1,
      senderIdentityKey: sender.getPublicKey().serialize(),
      expiration: BigInt.from(DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch),
      serverCertificate: serverCert,
      serverPrivateKey: serverPair.privateKey.serialize(),
    );
    return (root: rootPair.publicKey.serialize(), cert: cert);
  }

  setUpAll(() async {
    await rs.LibSignal.init();
    aliceIdentity = generateIdentityKeyPair();
    bobIdentity = generateIdentityKeyPair();
    alice = InMemorySignalProtocolStore(aliceIdentity, generateRegistrationId(false));
    bob = InMemorySignalProtocolStore(bobIdentity, generateRegistrationId(false));

    final pre = generatePreKeys(1, 1).single;
    final signed = generateSignedPreKey(bobIdentity, 1);
    await bob.storePreKey(pre.id, pre);
    await bob.storeSignedPreKey(signed.id, signed);
    await SessionBuilder.fromSignalStore(alice, const SignalProtocolAddress(_bobId, 1))
        .processPreKeyBundle(PreKeyBundle(
      await bob.getLocalRegistrationId(),
      1,
      pre.id,
      pre.getKeyPair().publicKey,
      signed.id,
      signed.getKeyPair().publicKey,
      signed.signature,
      bobIdentity.getPublicKey(),
    ));

    final issued = issueFor(aliceIdentity);
    trustRoot = issued.root;
    certificate = issued.cert;
    // The same sender, vouched for by a different server.
    foreignCertificate = issueFor(aliceIdentity).cert;
  });

  /// Identity lookups must never throw: the Rust side treats a Dart exception
  /// in a callback as a panic. An unknown sender is "no identity stored yet".
  Future<Uint8List?> identityIn(InMemorySignalProtocolStore store, String name, int device) async {
    try {
      return (await store.getIdentity(SignalProtocolAddress(name, device)))?.serialize();
    } on Object {
      return null;
    }
  }

  Future<Uint8List> seal(List<int> cert, CiphertextMessage inner) {
    final usmc = rs.UnidentifiedSenderMessageContent(
      messageType: inner.getType(),
      senderCertificate: cert,
      contents: inner.serialize(),
      contentHint: 0,
    );
    return rs.sealedSenderEncryptFromUsmcWithCallbacks(
      recipientName: _bobId,
      recipientDeviceId: 1,
      usmc: usmc.serialize(),
      getIdentityKeyPair: () => aliceIdentity.serialize(),
      getLocalRegistrationId: () => alice.getLocalRegistrationId(),
      getIdentity: (name, device) => identityIn(alice, name, device),
    );
  }

  Future<Uint8List> unseal(List<int> sealed) => rs.sealedSenderDecryptToUsmcWithCallbacks(
        ciphertext: sealed,
        trustRoot: trustRoot,
        timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        localName: _bobId,
        localDeviceId: 1,
        getIdentityKeyPair: () => bobIdentity.serialize(),
        getLocalRegistrationId: () => bob.getLocalRegistrationId(),
        getIdentity: (name, device) => identityIn(bob, name, device),
      );

  Future<CiphertextMessage> encrypt(String text) =>
      SessionCipher.fromStore(alice, const SignalProtocolAddress(_bobId, 1))
          .encrypt(Uint8List.fromList(utf8.encode(text)));

  test('seals a message from the existing sessions and opens it again', () async {
    final sealed = await seal(certificate, await encrypt('hallo bob'));

    final usmc = rs.UnidentifiedSenderMessageContent.deserialize(data: await unseal(sealed));
    final cert = usmc.senderCertificate();
    final sender = rs.senderCertificateGetSenderName(certificate: cert);
    final device = rs.senderCertificateGetSenderDeviceId(certificate: cert);
    expect(sender, _aliceId);
    expect(device, 1);
    expect(usmc.messageType(), CiphertextMessage.prekeyType);

    final plain = await SessionCipher.fromStore(bob, SignalProtocolAddress(sender, device))
        .decrypt(PreKeySignalMessage(usmc.contents()));
    expect(utf8.decode(plain), 'hallo bob');

    // The certificate's key is the key the session now trusts for Alice.
    final trusted = await bob.getIdentity(SignalProtocolAddress(sender, device));
    expect(trusted!.serialize(), rs.senderCertificateGetKey(certificate: cert));
  });

  test('a certificate from another server is refused', () async {
    final sealed = await seal(foreignCertificate, await encrypt('forged'));
    await expectLater(unseal(sealed), throwsA(anything));
  });

  test('one flipped byte and nothing opens', () async {
    final sealed = await seal(certificate, await encrypt('tamper'));
    sealed[sealed.length ~/ 2] ^= 0x01;
    await expectLater(unseal(sealed), throwsA(anything));
  });

  test('the sealed bytes do not carry the sender in the clear', () async {
    final sealed = await seal(certificate, await encrypt('quiet'));
    final text = latin1.decode(sealed, allowInvalid: true);
    expect(text.contains(_aliceId), isFalse);
    expect(text.contains(_aliceId.replaceAll('-', '')), isFalse);
    final key = aliceIdentity.getPublicKey().serialize().sublist(1);
    expect(_contains(sealed, key), isFalse, reason: 'sender identity key visible');
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
