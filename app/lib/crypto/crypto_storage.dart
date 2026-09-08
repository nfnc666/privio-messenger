import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the Signal protocol state is persisted.
///
/// Split out as a port so the protocol code never touches a platform API
/// directly: production uses the keystore, tests use memory, and a future
/// SQLCipher database can slot in without the crypto layer noticing.
abstract interface class CryptoStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Every key under a prefix, used to enumerate sessions and prekeys.
  Future<Map<String, String>> readPrefixed(String prefix);

  /// Destroys everything. Used by sign-out and by the wipe code.
  Future<void> wipe();
}

/// How much this device is keeping under a port that only speaks in strings.
extension CryptoStorageSize on CryptoStorage {
  /// The stored bytes: every key and value this device holds.
  ///
  /// The values are base64, so this is the size of what is *kept* rather than
  /// of the key material inside it. That is the honest number to show: it is
  /// what occupies the phone.
  Future<int> sizeInBytes() async {
    final all = await readPrefixed('');
    var total = 0;
    for (final entry in all.entries) {
      total += entry.key.length + entry.value.length;
    }
    return total;
  }
}

/// In-memory storage. Correct for tests; loses everything on restart.
class InMemoryCryptoStorage implements CryptoStorage {
  final Map<String, String> _entries = {};

  @override
  Future<String?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, String value) async => _entries[key] = value;

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<Map<String, String>> readPrefixed(String prefix) async => {
        for (final entry in _entries.entries)
          if (entry.key.startsWith(prefix)) entry.key: entry.value,
      };

  @override
  Future<void> wipe() async => _entries.clear();
}

/// Keystore-backed storage: Keychain on iOS, Keystore-backed encrypted
/// preferences on Android.
///
/// Private keys and ratchet state live here, which makes the platform keystore
/// the boundary protecting them at rest.
class KeystoreCryptoStorage implements CryptoStorage {
  const KeystoreCryptoStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _prefix = 'privio.signal.';

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  // No `encryptedSharedPreferences`: the flag was removed in
  // flutter_secure_storage 11 and is ignored in 10. Jetpack Security's
  // EncryptedSharedPreferences is deprecated by Google, and the package now
  // uses its own AES-GCM ciphers over the Android keystore — migrating
  // anything an older version wrote on first access.
  static const _androidOptions = AndroidOptions();

  @override
  Future<String?> read(String key) =>
      _storage.read(key: '$_prefix$key', iOptions: _iosOptions, aOptions: _androidOptions);

  @override
  Future<void> write(String key, String value) => _storage.write(
        key: '$_prefix$key',
        value: value,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: '$_prefix$key', iOptions: _iosOptions, aOptions: _androidOptions);

  @override
  Future<Map<String, String>> readPrefixed(String prefix) async {
    final all = await _storage.readAll(iOptions: _iosOptions, aOptions: _androidOptions);
    final wanted = '$_prefix$prefix';
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith(wanted)) entry.key.substring(_prefix.length): entry.value,
    };
  }

  @override
  Future<void> wipe() async {
    final mine = await _storage.readAll(iOptions: _iosOptions, aOptions: _androidOptions);
    for (final key in mine.keys.where((k) => k.startsWith(_prefix))) {
      await _storage.delete(key: key, iOptions: _iosOptions, aOptions: _androidOptions);
    }
  }
}

/// Binary protocol records are persisted as base64, since the storage layer is
/// a string map on every platform.
extension CryptoStorageBytes on CryptoStorage {
  Future<List<int>?> readBytes(String key) async {
    final value = await read(key);
    return value == null ? null : base64Decode(value);
  }

  Future<void> writeBytes(String key, List<int> value) =>
      write(key, base64Encode(value));
}
