import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

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

  /// What a derivation actually costs right now.
  ///
  /// Production is [memoryKiB]. Tests turn it down, because the cost is the
  /// whole point of the algorithm and a suite that pays it hundreds of times
  /// takes minutes to say nothing new — the widget tests for the calculator
  /// disguise alone went from seconds to over ten minutes. What is being tested
  /// there is that the right code unlocks and a wrong one does not, and that is
  /// true at any cost setting; the parameters live in the blob, so one sealed
  /// cheaply still opens.
  static int _memoryKiB = memoryKiB;
  static int _iterations = iterations;

  @visibleForTesting
  static void useCheapParameters() {
    _memoryKiB = 64;
    _iterations = 1;
  }

  @visibleForTesting
  static void useRealParameters() {
    _memoryKiB = memoryKiB;
    _iterations = iterations;
  }

  /// Bumped when the parameters change, so an old blob is still openable and a
  /// new one is not silently read with the wrong cost.
  static const int version = 1;

  static const int _saltLength = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  static Argon2id _kdf() => Argon2id(
        memory: _memoryKiB,
        iterations: _iterations,
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
      'm': _memoryKiB,
      't': _iterations,
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

  /// A verifier for a code that has to be checked *before* anything is
  /// unlocked — the duress code, which cannot be wrapped under the passcode
  /// because typing it is precisely the case where the passcode is not coming.
  ///
  /// Stored as salt and hash rather than as itself. In the clear it defeated
  /// the feature outright: whoever read the store learned the duress code and
  /// could simply avoid typing it, and learned that one existed at all, which
  /// under coercion is its own kind of dangerous.
  static Future<String> hash(String code) async {
    final salt = _randomBytes(_saltLength);
    final derived = await _derive(code, salt);
    return jsonEncode({
      'v': version,
      'm': _memoryKiB,
      't': _iterations,
      'p': parallelism,
      's': base64Encode(salt),
      'h': base64Encode(await derived.extractBytes()),
    });
  }

  /// Whether [code] is the one behind [stored].
  ///
  /// [stored] may be null, and the work is done anyway: returning early when no
  /// duress code is set would make "there is one" and "there is not" tell
  /// themselves apart by how long the answer took.
  static Future<bool> matches({required String code, required String? stored}) async {
    Map<String, dynamic>? blob;
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored) as Map<String, dynamic>;
        // A map that parses but carries none of the fields is as good as
        // nothing here, and must take the same path as nothing — including the
        // work, so the timing does not give it away.
        blob = decoded['s'] is String && decoded['h'] is String ? decoded : null;
      } on Object {
        blob = null;
      }
    }
    final salt = blob == null
        ? _randomBytes(_saltLength)
        : base64Decode(blob['s'] as String);
    final kdf = Argon2id(
      memory: (blob?['m'] as int?) ?? _memoryKiB,
      iterations: (blob?['t'] as int?) ?? _iterations,
      parallelism: (blob?['p'] as int?) ?? parallelism,
      hashLength: 32,
    );
    final derived = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: salt,
    );
    final bytes = await derived.extractBytes();
    if (blob == null) return false;
    final expected = base64Decode(blob['h'] as String);
    if (expected.length != bytes.length) return false;
    // Constant time: a code compared byte by byte can be walked into.
    var diff = 0;
    for (var i = 0; i < bytes.length; i++) {
      diff |= bytes[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Uint8List _randomBytes(int length) {
    final key = SecretKeyData.random(length: length);
    return Uint8List.fromList(key.bytes);
  }
}
