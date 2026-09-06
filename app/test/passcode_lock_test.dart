import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/core/secure_store.dart';

void main() {
  final key = base64Encode(List.generate(32, (i) => (i * 11) % 256));

  test('setting a lock takes the readable archive key away', () async {
    final store = InMemorySecureStore();
    await store.writeArchiveKey(key);
    expect(await store.readArchiveKey(), key);

    await store.setPasscode('1234', PasscodeKind.digits4);

    // Still readable in *this* session, because the passcode was just typed.
    expect(await store.readArchiveKey(), key);
    expect(await store.hasPasscode(), isTrue);
  });

  test('a fresh process has nothing until the passcode is typed', () async {
    final store = InMemorySecureStore();
    await store.writeArchiveKey(key);
    await store.setPasscode('1234', PasscodeKind.digits4);
    // What survives a relaunch is what was written down, not what was in RAM.
    final relaunched = InMemorySecureStore()..restoreForTest(store.entriesForTest);

    expect(await relaunched.readArchiveKey(), isNull, reason: 'locked');
    expect(await relaunched.verifyPasscode('9999'), isFalse);
    expect(await relaunched.readArchiveKey(), isNull, reason: 'still locked');

    expect(await relaunched.verifyPasscode('1234'), isTrue);
    expect(await relaunched.readArchiveKey(), key, reason: 'and now it opens');
  });

  test('turning the lock off puts the key back, or the history is gone', () async {
    final store = InMemorySecureStore();
    await store.writeArchiveKey(key);
    await store.setPasscode('1234', PasscodeKind.digits4);
    await store.clearPasscode();

    final relaunched = InMemorySecureStore()..restoreForTest(store.entriesForTest);
    expect(await relaunched.readArchiveKey(), key);
    expect(await relaunched.hasPasscode(), isFalse);
  });

  test('a key generated after the lock is wrapped, not written in the clear', () async {
    // A device that set a passcode before it had any history: the archive key
    // is generated later, and must not land readable because of the order.
    final store = InMemorySecureStore();
    await store.setPasscode('1234', PasscodeKind.digits4);
    await store.writeArchiveKey(key);

    final relaunched = InMemorySecureStore()..restoreForTest(store.entriesForTest);
    expect(await relaunched.readArchiveKey(), isNull);
    expect(await relaunched.verifyPasscode('1234'), isTrue);
    expect(await relaunched.readArchiveKey(), key);
  });

  test('no lock is the old behaviour, unchanged', () async {
    final store = InMemorySecureStore();
    await store.writeArchiveKey(key);
    final relaunched = InMemorySecureStore()..restoreForTest(store.entriesForTest);
    expect(await relaunched.readArchiveKey(), key);
  });
}
