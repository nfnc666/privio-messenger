import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Locks the archive key behind the passcode.
///
/// Without this the passcode guards the screen and nothing else: the key that
/// opens the local history sits in the same store as the history, so whoever
/// can read that store reads the chats — which is not hypothetical on the web
/// build, where `tools/web-storage-recovery.cjs` does exactly that.
///
/// With it, the stored form of the archive key is ciphertext under a key
/// derived from the passcode with Argon2id, and nothing on the device opens it
/// without the passcode being typed. That is also what makes the passcode
/// itself stretched rather than compared: there is no stored passcode to match
/// against any more, only a key that either unwraps or does not.
///
/// What it cannot do: help a device with no passcode set. There is nothing to
/// derive from, the key has to stay readable so the app can start, and the
/// honest thing is to say so rather than pretend a default protects anything.
abstract final class PasscodeVault {
  /// RFC 9106's second recommended setting: 19 MiB, two passes, one lane.
  ///
  /// The first (2 GiB) is not something to ask a phone for on every unlock, and
  /// this one is the parameter set written for exactly this case. Argon2id
  /// rather than PBKDF2 because a passcode is four to six digits on most
  /// devices: the whole defence is making each guess cost memory, which is the
  /// thing an attacker's hardware has least of.
  static const int memoryKiB = 19 * 1024;
  static const int iterations = 2;
  static const int parallelism = 1;

  /// Bumped when the parameters change, so an old blob is still openable and a
  /// new one is not silently read with the wrong cost.
  static const int version = 1;

  static const int _saltLength = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  static Argon2id _kdf() => Argon2id(
        memory: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      );

  static Future<SecretKey> _derive(String passcode, List<int> salt) => _kdf().deriveKey(
        secretKey: SecretKey(utf8.encode(passcode)),
        nonce: salt,
      );

  /// Seals [archiveKey] under [passcode]. The result is safe to store beside
  /// the data it protects, which is the point.
  static Future<String> wrap({
    required String passcode,
    required Uint8List archiveKey,
  }) async {
    final salt = _randomBytes(_saltLength);
    final kek = await _derive(passcode, salt);
    final box = await _cipher.encrypt(archiveKey, secretKey: kek);
    return jsonEncode({
      'v': version,
      'm': memoryKiB,
      't': iterations,
      'p': parallelism,
      's': base64Encode(salt),
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText + box.mac.bytes),
    });
  }

  /// Opens it, or answers null when the passcode is wrong.
  ///
  /// Null rather than an exception because a wrong passcode is not an error
  /// condition — it is the normal case this exists to handle, and the caller
  /// answers it the same way it answers any other wrong one.
  static Future<Uint8List?> unwrap({
    required String passcode,
    required String wrapped,
  }) async {
    final Map<String, dynamic> blob;
    try {
      blob = jsonDecode(wrapped) as Map<String, dynamic>;
    } on Object {
      return null;
    }
    if (blob['v'] != version) return null;

    final kdf = Argon2id(
      // Read from the blob, not from the constants: the parameters that sealed
      // it are the only ones that open it.
      memory: blob['m'] as int,
      iterations: blob['t'] as int,
      parallelism: blob['p'] as int,
      hashLength: 32,
    );
    final kek = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passcode)),
      nonce: base64Decode(blob['s'] as String),
    );
    final body = base64Decode(blob['c'] as String);
    final macLength = _cipher.macAlgorithm.macLength;
    if (body.length <= macLength) return null;

    try {
      final plain = await _cipher.decrypt(
        SecretBox(
          body.sublist(0, body.length - macLength),
          nonce: base64Decode(blob['n'] as String),
          mac: Mac(body.sublist(body.length - macLength)),
        ),
        secretKey: kek,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final key = SecretKeyData.random(length: length);
    return Uint8List.fromList(key.bytes);
  }
}
