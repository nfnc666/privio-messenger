import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/secure_store.dart';
import '../models/security_event.dart';

/// Where the sealed security log is kept.
///
/// A port, the same one the message archive has and for the same reason: the
/// sealing above it never depends on a platform API, so every case below can be
/// reached in a test without a phone.
abstract interface class SecurityLogStorage {
  Future<Uint8List?> read();
  Future<void> write(Uint8List bytes);
  Future<void> delete();
}

class InMemorySecurityLogStorage implements SecurityLogStorage {
  Uint8List? _bytes;

  /// Exposed so a test can assert what actually sits at rest — in particular
  /// that it is not readable.
  Uint8List? get bytes => _bytes;

  @override
  Future<Uint8List?> read() async => _bytes;

  @override
  Future<void> write(Uint8List bytes) async => _bytes = bytes;

  @override
  Future<void> delete() async => _bytes = null;
}

class KeystoreSecurityLogStorage implements SecurityLogStorage {
  const KeystoreSecurityLogStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _key = 'privio.security.log';
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions();

  @override
  Future<Uint8List?> read() async {
    final stored = await _storage.read(key: _key, iOptions: _iosOptions, aOptions: _androidOptions);
    return stored == null ? null : base64Decode(stored);
  }

  @override
  Future<void> write(Uint8List bytes) => _storage.write(
        key: _key,
        value: base64Encode(bytes),
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  @override
  Future<void> delete() =>
      _storage.delete(key: _key, iOptions: _iosOptions, aOptions: _androidOptions);
}

/// What the security activity screen reads and writes.
abstract interface class SecurityLog {
  /// Newest first, and only this account's. Empty for a device that has
  /// recorded nothing, and empty for a log belonging to somebody else.
  Future<List<SecurityEvent>> load({required String accountId});

  Future<void> append(SecurityEvent event, {required String accountId});

  /// Forgets everything. Called on sign-out and on wipe.
  Future<void> clear();
}

/// A log that keeps nothing. What a build with no storage reports.
class NoSecurityLog implements SecurityLog {
  const NoSecurityLog();

  @override
  Future<List<SecurityEvent>> load({required String accountId}) async => const [];

  @override
  Future<void> append(SecurityEvent event, {required String accountId}) async {}

  @override
  Future<void> clear() async {}
}

/// The security log, sealed on this device and never sent anywhere.
///
/// **There is no server side to this.** A server-held activity log would be a
/// record of when each account's owner changed a password, linked a phone or
/// verified a contact — held by the one party the rest of this app is built to
/// not trust with content. The events are produced on the device that performed
/// the action and stay there. The cost is honest and is written on the screen:
/// a device that was never told about an event does not show it, so a password
/// changed on a second phone appears in that phone's list and not in this one's.
///
/// Sealed with the archive key, which is deliberate rather than lazy: it means
/// the log shares the message history's lifecycle exactly. Wipe the account and
/// the key goes, so the log is unreadable in the same instant the messages are —
/// one key to protect, one key to destroy.
class EncryptedSecurityLog implements SecurityLog {
  EncryptedSecurityLog({
    required SecurityLogStorage storage,
    required SecureStore keyStore,
    AesGcm? cipher,
  })  : _storage = storage,
        _keyStore = keyStore,
        _cipher = cipher ?? AesGcm.with256bits();

  final SecurityLogStorage _storage;
  final SecureStore _keyStore;
  final AesGcm _cipher;

  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _formatVersion = 1;

  /// How many events are kept. A security list nobody can get to the bottom of
  /// is a list nobody reads, and an unbounded one grows in a keystore entry.
  /// Oldest go first.
  static const int keep = 200;

  SecretKey? _cachedKey;

  Future<SecretKey?> _key() async {
    final cached = _cachedKey;
    if (cached != null) return cached;
    final stored = await _keyStore.readArchiveKey();
    // Null rather than generating one. The archive owns that decision — it is
    // the thing whose absence means "first run" — and a key minted here would
    // be written over the history's own on a device where the archive has not
    // been opened yet.
    if (stored == null) return null;
    return _cachedKey = SecretKey(base64Decode(stored));
  }

  @override
  Future<List<SecurityEvent>> load({required String accountId}) async {
    final sealed = await _storage.read();
    if (sealed == null || sealed.length < 1 + _nonceLength + _macLength) return const [];
    if (sealed.first != _formatVersion) return const [];

    final key = await _key();
    if (key == null) return const [];

    try {
      final plain = await _cipher.decrypt(
        SecretBox(
          sealed.sublist(1 + _nonceLength, sealed.length - _macLength),
          nonce: sealed.sublist(1, 1 + _nonceLength),
          mac: Mac(sealed.sublist(sealed.length - _macLength)),
        ),
        secretKey: key,
      );
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      // Whose log this is, from inside the sealed payload — an owner written
      // beside the ciphertext could be rewritten by whoever holds the phone.
      // A log naming a different account is refused outright rather than shown
      // to whoever signed in next.
      if (map['accountId'] != accountId) return const [];
      final events = [
        for (final raw in map['events'] as List<dynamic>? ?? const [])
          if (SecurityEvent.fromJson(raw as Map<String, dynamic>) case final event?) event,
      ];
      events.sort((a, b) => b.at.compareTo(a.at));
      return events;
    } on Object {
      // A wrong key, a tampered blob, or a passcode nobody has typed. An empty
      // list is the honest answer; guessing at half-decrypted content on a
      // security screen would be worse than showing nothing.
      return const [];
    }
  }

  @override
  Future<void> append(SecurityEvent event, {required String accountId}) async {
    final key = await _key();
    // Nothing to seal it with yet. Dropping the event is right: the alternative
    // is writing it in the clear, and an unencrypted list of when this account
    // changed its password is exactly what must not exist on a lost phone.
    if (key == null) return;

    final existing = await load(accountId: accountId);
    final events = [event, ...existing].take(keep).toList();

    final plain = utf8.encode(
      jsonEncode({
        'accountId': accountId,
        'events': [for (final entry in events) entry.toJson()],
      }),
    );
    final box = await _cipher.encrypt(plain, secretKey: key);
    // version | nonce | ciphertext | mac — the archive's layout, so there is
    // one framing in this app rather than two.
    await _storage.write(
      Uint8List.fromList([_formatVersion, ...box.nonce, ...box.cipherText, ...box.mac.bytes]),
    );
  }

  @override
  Future<void> clear() async {
    _cachedKey = null;
    await _storage.delete();
  }
}
