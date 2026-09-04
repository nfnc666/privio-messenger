import 'package:flutter_test/flutter_test.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';

Future<PrivioCrypto> device() async {
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  await crypto.buildRegistration(name: 'Test', platform: 'ios', preKeyCount: 2);
  return crypto;
}

void main() {
  test('a fresh device is not due for a rotation', () async {
    final crypto = await device();
    expect(await crypto.signedPreKeyIsDue(DateTime.now()), isFalse);
  });

  test('it comes due once the key has been on offer long enough', () async {
    final crypto = await device();
    final generated = (await crypto.newestSignedPreKeyAt())!;

    expect(
      await crypto.signedPreKeyIsDue(
        generated.add(PrivioCrypto.signedPreKeyLifetime - const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(
      await crypto.signedPreKeyIsDue(generated.add(PrivioCrypto.signedPreKeyLifetime)),
      isTrue,
    );
  });

  test('a device with no signed prekey at all is overdue, not up to date', () async {
    final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    expect(await crypto.signedPreKeyIsDue(DateTime.now()), isTrue);
  });

  test('rotating publishes a new key and keeps the old one for now', () async {
    final crypto = await device();
    final before = await crypto.newestSignedPreKeyAt();

    final published = await crypto.rotateSignedPreKey();
    expect(published['keyId'], isA<int>());
    expect(published['publicKey'], isA<String>());
    expect(published['signature'], isA<String>());

    // Two on the device: a message sealed against the old one an hour ago has
    // to still open.
    expect(await crypto.store.loadSignedPreKeys(), hasLength(2));
    expect(await crypto.newestSignedPreKeyAt(), isNot(before));
    expect(await crypto.signedPreKeyIsDue(DateTime.now()), isFalse);
  });

  test('the old one goes once nothing can still be sealed to it', () async {
    final crypto = await device();
    final first = (await crypto.store.loadSignedPreKeys()).single.id;
    await crypto.rotateSignedPreKey();

    // Inside the grace period: both stay.
    expect(await crypto.pruneSignedPreKeys(DateTime.now()), 0);
    expect(await crypto.store.loadSignedPreKeys(), hasLength(2));

    final later = DateTime.now().add(
      PrivioCrypto.signedPreKeyGrace + const Duration(days: 1),
    );
    expect(await crypto.pruneSignedPreKeys(later), 1);
    final left = await crypto.store.loadSignedPreKeys();
    expect(left, hasLength(1), reason: 'the newest is never pruned');
    expect(left.single.id, isNot(first));
  });

  test('pruning never leaves the device without a signed prekey', () async {
    final crypto = await device();
    final far = DateTime.now().add(const Duration(days: 3650));

    expect(await crypto.pruneSignedPreKeys(far), 0);
    expect(
      await crypto.store.loadSignedPreKeys(),
      hasLength(1),
      reason: 'a device with no signed prekey cannot be written to at all',
    );
  });
}
