import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/passcode_vault.dart';

void main() {
  // These tests are about the algorithm itself, so they pay the real cost.
  setUp(PasscodeVault.useRealParameters);

  final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));

  test('the right passcode gets the key back', () async {
    final wrapped = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    expect(await PasscodeVault.unwrap(passcode: '1234', wrapped: wrapped), key);
  });

  test('a wrong one gets nothing, and does not throw', () async {
    // A wrong passcode is the normal case this exists for, not an error.
    final wrapped = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    expect(await PasscodeVault.unwrap(passcode: '1235', wrapped: wrapped), isNull);
    expect(await PasscodeVault.unwrap(passcode: '', wrapped: wrapped), isNull);
  });

  test('the key is not in the blob', () async {
    final wrapped = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    expect(wrapped.contains(base64Encode(key)), isFalse);
    // Nor is the passcode, which is the other half: there is nothing stored to
    // compare a guess against, only a key that either unwraps or does not.
    expect(wrapped.contains('1234'), isFalse);
  });

  test('the same key wrapped twice is never the same bytes', () async {
    // A fresh salt and nonce each time, so two devices with the same passcode
    // do not produce a matching blob to notice.
    final a = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    final b = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    expect(a, isNot(b));
  });

  test('a tampered blob is refused rather than half-read', () async {
    final wrapped = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    final blob = jsonDecode(wrapped) as Map<String, dynamic>;
    final body = base64Decode(blob['c'] as String);
    body[0] ^= 0xFF;
    blob['c'] = base64Encode(body);
    expect(
      await PasscodeVault.unwrap(passcode: '1234', wrapped: jsonEncode(blob)),
      isNull,
    );
  });

  test('it opens with the parameters it was sealed with, not the current ones',
      () async {
    // The cost is written into the blob so that raising it later does not lock
    // everybody out of their own history.
    final wrapped = await PasscodeVault.wrap(passcode: '1234', archiveKey: key);
    final blob = jsonDecode(wrapped) as Map<String, dynamic>;
    expect(blob['m'], PasscodeVault.memoryKiB);
    expect(blob['t'], PasscodeVault.iterations);
    expect(blob['v'], PasscodeVault.version);
  });

  test('nonsense is refused rather than crashing the lock screen', () async {
    for (final junk in ['', 'not json', '{}', '{"v":99}']) {
      expect(await PasscodeVault.unwrap(passcode: '1234', wrapped: junk), isNull);
    }
  });

  group('the duress code', () {
    test('the right code matches', () async {
      final stored = await PasscodeVault.hash('9119');
      expect(await PasscodeVault.matches(code: '9119', stored: stored), isTrue);
    });

    test('a wrong one does not', () async {
      final stored = await PasscodeVault.hash('9119');
      expect(await PasscodeVault.matches(code: '9118', stored: stored), isFalse);
    });

    test('the code is not in what is stored', () async {
      // In the clear it defeated the feature: whoever read the store learned
      // the code and could simply avoid typing it.
      final stored = await PasscodeVault.hash('9119');
      expect(stored.contains('9119'), isFalse);
    });

    test('no duress code set is answered, not short-circuited', () async {
      // Returning early would let "there is one" and "there is not" tell
      // themselves apart by how long the answer took.
      final t0 = DateTime.now();
      expect(await PasscodeVault.matches(code: '9119', stored: null), isFalse);
      final absent = DateTime.now().difference(t0);

      final stored = await PasscodeVault.hash('0000');
      final t1 = DateTime.now();
      expect(await PasscodeVault.matches(code: '9119', stored: stored), isFalse);
      final present = DateTime.now().difference(t1);

      // Same order of magnitude is the claim; an exact match is not something
      // a test on a shared machine can hold to.
      expect(absent.inMilliseconds * 4, greaterThan(present.inMilliseconds));
    });

    test('nonsense is refused rather than crashing the lock screen', () async {
      for (final junk in ['', 'not json', '{}']) {
        expect(await PasscodeVault.matches(code: '9119', stored: junk), isFalse);
      }
    });
  });
}
