import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'passcode.dart';
import 'passcode_vault.dart';

/// Where the session and the app-lock state live.
///
/// An interface for the same reason [CryptoStorage] is one: the code above it
/// must never depend on a platform plugin, so tests can run it and so a
/// different backing store can be swapped in without touching call sites.
abstract interface class SecureStore {
  Future<String?> readToken();
  Future<String?> readUsername();
  Future<String?> readAccountId();
  Future<void> writeSession({
    required String token,
    required String username,
    required String accountId,
  });

  /// The app-lock passcode and its shape. The shape is stored because the lock
  /// screen has to know whether to draw a keypad or a text field before anyone
  /// has typed anything.
  Future<void> setPasscode(String passcode, PasscodeKind kind);
  Future<PasscodeKind?> passcodeKind();
  Future<bool> hasPasscode();
  Future<bool> verifyPasscode(String passcode);
  Future<void> clearPasscode();

  /// How much larger or smaller text should be drawn than the design's size.
  /// Not a secret; it lives here because this is the app's only local store
  /// that survives a relaunch, the same reason the backup interval does.
  Future<double?> readTextScale();
  Future<void> writeTextScale(double scale);

  /// Which calculator skin the disguise wears, or null when it is off.
  ///
  /// Stored beside the passcode rather than in a settings file, because it is
  /// part of the lock: whether this device opens to a calculator is exactly as
  /// sensitive as the code that gets past it.
  Future<String?> readDisguise();
  Future<void> writeDisguise(String? skin);

  /// The call log, as JSON, or null when there is none.
  ///
  /// It lives with the keys rather than in the message archive because it is
  /// not a conversation: it is a list of who this account has spoken to and
  /// when, which is exactly the kind of thing worth keeping encrypted at rest
  /// and worth being able to erase on its own.
  Future<String?> readCallLog();
  Future<void> writeCallLog(String? json);

  /// The duress code, kept here as well as on the server so the lock screen can
  /// recognise it with no network — which is the situation it exists for.
  Future<void> setDuressCode(String? code);
  Future<bool> verifyDuressCode(String code);

  /// The key the local message archive is sealed with. Small enough that a
  /// keystore is the right home for it, unlike the archive itself.
  Future<String?> readArchiveKey();
  Future<void> writeArchiveKey(String base64Key);

  /// The recovery key backups are sealed under.
  ///
  /// Kept so an automatic backup does not have to ask for it every week. It is
  /// still the user's to write down: a device that is lost takes this copy with
  /// it, which is exactly the situation a backup exists for.
  Future<String?> readRecoveryKey();
  Future<void> writeRecoveryKey(String base32Key);

  /// When the last backup went up, and how often to make one. Not secret, but
  /// they belong beside the key rather than in a second store.
  Future<DateTime?> readLastBackupAt();
  Future<void> writeLastBackupAt(DateTime when);
  Future<String?> readBackupInterval();
  Future<void> writeBackupInterval(String interval);

  /// A license key entered before there was an account to bind it to.
  ///
  /// Held only between the activation screen and the first successful sign-in,
  /// and cleared the moment it is redeemed: afterwards the key is spent, and
  /// keeping a spent bearer secret is a liability rather than a convenience.
  Future<String?> readPendingLicenseKey();
  Future<void> writePendingLicenseKey(String? key);

  /// The last answer the server gave about this account's license, as JSON.
  ///
  /// A cache, never a gate. This app is open source: a check against a value
  /// the device itself holds is one deleted line away from being bypassed, so
  /// nothing here decides whether anyone is served. It exists so the app can
  /// say something true while offline instead of accusing a paying user of not
  /// having paid.
  Future<String?> readLicenseCache();
  Future<void> writeLicenseCache(String? json);

  /// The account the activation step has already been put in front of.
  ///
  /// Stored per account rather than as a flag, so a second account created on
  /// the same device is asked in its turn, and the first one is not asked
  /// again on every launch.
  Future<String?> readActivationAskedFor();
  Future<void> writeActivationAskedFor(String accountId);

  /// Used by sign-out and by the wipe code: leaves nothing recoverable behind.
  Future<void> wipe();
}

/// Thrown when the archive key exists but is sealed under a passcode nobody has
/// typed yet.
///
/// Distinct from "there is no key", and the distinction is the whole point: a
/// caller that reads the two as the same thing generates a fresh key, writes it
/// over the old one, and the history is gone. That is not a hypothetical — it
/// is what happened the first time this was wired up, and the exception is what
/// stops it happening again.
class ArchiveLockedException implements Exception {
  const ArchiveLockedException();

  @override
  String toString() => 'The archive key is sealed under the passcode';
}

/// The platform keystore: Keychain on iOS, Keystore-backed encrypted
/// preferences on Android. Never shared preferences, never a plain file.
class KeystoreSecureStore implements SecureStore {
  KeystoreSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'privio.session.token';
  static const _usernameKey = 'privio.session.username';
  static const _accountIdKey = 'privio.session.account_id';
  static const _passcodeKey = 'privio.lock.pin';
  static const _passcodeKindKey = 'privio.lock.kind';
  static const _duressKey = 'privio.lock.duress';
  static const _textScaleKey = 'privio.appearance.text_scale';
  static const _callLogKey = 'privio.calls.log';
  static const _disguiseKey = 'privio.disguise.skin';
  static const _archiveKeyKey = 'privio.archive.key';

  /// The same key, sealed under the passcode. Present instead of
  /// [_archiveKeyKey] on a device with a lock set.
  static const _wrappedArchiveKeyKey = 'privio.archive.key.wrapped';

  /// Held for the life of the process, never written back: the passcode that
  /// opened this session, and the key it opened. A relaunch asks again, which
  /// is the whole point of wrapping it.
  String? _sessionPasscode;
  String? _sessionArchiveKey;
  static const _recoveryKeyKey = 'privio.backup.recovery_key';
  static const _lastBackupKey = 'privio.backup.last_at';
  static const _backupIntervalKey = 'privio.backup.interval';
  static const _pendingLicenseKey = 'privio.license.pending_key';
  static const _licenseCacheKey = 'privio.license.status';

  static const _activationAskedKey = 'privio.license.activation_asked_for';

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  Future<String?> _read(String key) =>
      _storage.read(key: key, iOptions: _iosOptions, aOptions: _androidOptions);

  Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value, iOptions: _iosOptions, aOptions: _androidOptions);

  Future<void> _clear(String key) =>
      _storage.delete(key: key, iOptions: _iosOptions, aOptions: _androidOptions);

  @override
  Future<String?> readToken() => _read(_tokenKey);

  @override
  Future<String?> readUsername() => _read(_usernameKey);

  @override
  Future<String?> readAccountId() => _read(_accountIdKey);

  @override
  Future<void> writeSession({
    required String token,
    required String username,
    required String accountId,
  }) async {
    await _write(_tokenKey, token);
    await _write(_usernameKey, username);
    await _write(_accountIdKey, accountId);
  }

  /// The passcode does two things, and until recently it only did one.
  ///
  /// It guards the screen, and it now also guards the key to the local history:
  /// setting one wraps that key with Argon2id under the passcode and deletes
  /// the readable copy, so a store somebody walks off with no longer opens the
  /// chats. That is also what makes the passcode stretched rather than
  /// compared — there is no stored passcode left to match a guess against.
  ///
  /// A device with no passcode is unchanged, and honestly so: there is nothing
  /// to derive from, the key has to stay readable for the app to start, and
  /// pretending otherwise would be worse than saying it.
  @override
  Future<void> setPasscode(String passcode, PasscodeKind kind) async {
    // Through `readArchiveKey`, not straight off the plain entry: on a *change*
    // of passcode there is no plain entry left — the first one took it away —
    // and reading it directly would leave the old blob sealed under the old
    // code while the new code was stored beside it. The old passcode went on
    // working and the new one opened nothing.
    final current = await readArchiveKey();
    _sessionPasscode = passcode;
    if (current != null) {
      await _write(
        _wrappedArchiveKeyKey,
        await PasscodeVault.wrap(
          passcode: passcode,
          archiveKey: Uint8List.fromList(base64Decode(current)),
        ),
      );
      await _storage.delete(key: _archiveKeyKey, iOptions: _iosOptions, aOptions: _androidOptions);
      await _storage.delete(key: _passcodeKey, iOptions: _iosOptions, aOptions: _androidOptions);
      _sessionArchiveKey = current;
    }
    // The passcode itself is no longer stored once there is a wrapped key to
    // check it against; the kind is, because the lock screen has to know which
    // keyboard to draw before anything is typed.
    await _write(_passcodeKindKey, kind.id);
    if (current == null) await _write(_passcodeKey, passcode);
  }

  @override
  Future<PasscodeKind?> passcodeKind() async => PasscodeKind.parse(await _read(_passcodeKindKey));

  @override
  Future<bool> hasPasscode() async =>
      await _read(_wrappedArchiveKeyKey) != null || await _read(_passcodeKey) != null;

  @override
  Future<void> clearPasscode() async {
    // The key goes back to being readable, because the app has to be able to
    // start without anybody typing anything. Unwrapping it first: a cleared
    // lock that left the only copy sealed would be a history nobody can open.
    final key = await readArchiveKey();
    if (key != null) await _write(_archiveKeyKey, key);
    await _storage.delete(
      key: _wrappedArchiveKeyKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    _sessionPasscode = null;
    await _storage.delete(key: _passcodeKey, iOptions: _iosOptions, aOptions: _androidOptions);
    await _storage.delete(
      key: _passcodeKindKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  @override
  Future<double?> readTextScale() async => double.tryParse(await _read(_textScaleKey) ?? '');

  @override
  Future<void> writeTextScale(double scale) => _write(_textScaleKey, '$scale');

  @override
  Future<String?> readDisguise() => _read(_disguiseKey);

  @override
  Future<void> writeDisguise(String? skin) => skin == null
      ? _storage.delete(key: _disguiseKey, iOptions: _iosOptions, aOptions: _androidOptions)
      : _write(_disguiseKey, skin);

  @override
  Future<String?> readCallLog() => _read(_callLogKey);

  @override
  Future<void> writeCallLog(String? json) => json == null
      ? _storage.delete(key: _callLogKey, iOptions: _iosOptions, aOptions: _androidOptions)
      : _write(_callLogKey, json);

  @override
  Future<void> setDuressCode(String? code) => code == null
      ? _storage.delete(key: _duressKey, iOptions: _iosOptions, aOptions: _androidOptions)
      : _write(_duressKey, code);

  @override
  Future<bool> verifyDuressCode(String code) async {
    final stored = await _read(_duressKey);
    return stored != null && stored == code;
  }

  @override
  Future<bool> verifyPasscode(String passcode) async {
    // Where the archive key is wrapped, checking the passcode *is* opening it:
    // one operation, no stored secret to compare against, and the key ends up
    // in memory where the archive needs it.
    final wrapped = await _read(_wrappedArchiveKeyKey);
    if (wrapped != null) {
      final key = await PasscodeVault.unwrap(passcode: passcode, wrapped: wrapped);
      if (key == null) return false;
      _sessionPasscode = passcode;
      _sessionArchiveKey = base64Encode(key);
      return true;
    }
    final stored = await _read(_passcodeKey);
    return stored != null && stored == passcode;
  }

  @override
  Future<String?> readArchiveKey() async {
    // Once the passcode has opened it, it lives in memory for the session:
    // writing it back would put the readable copy exactly where wrapping it
    // took it from.
    if (_sessionArchiveKey != null) return _sessionArchiveKey;
    final wrapped = await _read(_wrappedArchiveKeyKey);
    if (wrapped == null) return _read(_archiveKeyKey);
    final passcode = _sessionPasscode;
    if (passcode == null) throw const ArchiveLockedException();
    final key = await PasscodeVault.unwrap(passcode: passcode, wrapped: wrapped);
    if (key == null) throw const ArchiveLockedException();
    return _sessionArchiveKey = base64Encode(key);
  }

  @override
  Future<void> writeArchiveKey(String base64Key) async {
    final passcode = _sessionPasscode;
    if (passcode == null) {
      // Refusing rather than writing: a caller here with a wrapped key already
      // stored is a caller about to replace a history it could not read.
      if (await _read(_wrappedArchiveKeyKey) != null) {
        throw const ArchiveLockedException();
      }
      return _write(_archiveKeyKey, base64Key);
    }
    // A key generated after the lock was set — a first archive on a device that
    // had a passcode before it had any history — is wrapped straight away
    // rather than written in the clear and wrapped later.
    _sessionArchiveKey = base64Key;
    await _write(
      _wrappedArchiveKeyKey,
      await PasscodeVault.wrap(
        passcode: passcode,
        archiveKey: Uint8List.fromList(base64Decode(base64Key)),
      ),
    );
    await _storage.delete(key: _passcodeKey, iOptions: _iosOptions, aOptions: _androidOptions);
  }

  @override
  Future<String?> readRecoveryKey() => _read(_recoveryKeyKey);

  @override
  Future<void> writeRecoveryKey(String base32Key) => _write(_recoveryKeyKey, base32Key);

  @override
  Future<DateTime?> readLastBackupAt() async =>
      DateTime.tryParse(await _read(_lastBackupKey) ?? '');

  @override
  Future<void> writeLastBackupAt(DateTime when) => _write(_lastBackupKey, when.toIso8601String());

  @override
  Future<String?> readBackupInterval() => _read(_backupIntervalKey);

  @override
  Future<void> writeBackupInterval(String interval) => _write(_backupIntervalKey, interval);

  @override
  Future<String?> readPendingLicenseKey() => _read(_pendingLicenseKey);

  @override
  Future<void> writePendingLicenseKey(String? key) =>
      key == null ? _clear(_pendingLicenseKey) : _write(_pendingLicenseKey, key);

  @override
  Future<String?> readLicenseCache() => _read(_licenseCacheKey);

  @override
  Future<void> writeLicenseCache(String? json) =>
      json == null ? _clear(_licenseCacheKey) : _write(_licenseCacheKey, json);

  @override
  Future<String?> readActivationAskedFor() => _read(_activationAskedKey);

  @override
  Future<void> writeActivationAskedFor(String accountId) => _write(_activationAskedKey, accountId);

  @override
  Future<void> wipe() async {
    // The process keeps the key it was handed at unlock. Deleting the stored
    // half and leaving that behind is the mistake the crypto store made once
    // already: a wipe that leaves key material in memory is not a wipe.
    _sessionPasscode = null;
    _sessionArchiveKey = null;
    await _storage.deleteAll(iOptions: _iosOptions, aOptions: _androidOptions);
  }
}

/// In-memory store for tests. Never used in a shipped build.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _entries = {};

  @override
  Future<String?> readToken() async => _entries['token'];

  @override
  Future<String?> readUsername() async => _entries['username'];

  @override
  Future<String?> readAccountId() async => _entries['accountId'];

  @override
  Future<void> writeSession({
    required String token,
    required String username,
    required String accountId,
  }) async {
    _entries
      ..['token'] = token
      ..['username'] = username
      ..['accountId'] = accountId;
  }

  // The same rules as the real store, deliberately: a test that exercises the
  // lock should exercise the wrapping the lock actually does.
  String? _sessionPasscode;
  String? _sessionArchiveKey;

  @override
  Future<void> setPasscode(String passcode, PasscodeKind kind) async {
    final current = await readArchiveKey();
    _sessionPasscode = passcode;
    _entries.remove('archiveKey');
    if (current != null) {
      _entries['archiveKeyWrapped'] = await PasscodeVault.wrap(
        passcode: passcode,
        archiveKey: Uint8List.fromList(base64Decode(current)),
      );
      _entries.remove('pin');
      _sessionArchiveKey = current;
    } else {
      _entries['pin'] = passcode;
    }
    _entries['pinKind'] = kind.id;
  }

  @override
  Future<PasscodeKind?> passcodeKind() async => PasscodeKind.parse(_entries['pinKind']);

  @override
  Future<void> clearPasscode() async {
    final key = await readArchiveKey();
    if (key != null) _entries['archiveKey'] = key;
    _entries.remove('archiveKeyWrapped');
    _sessionPasscode = null;
    _entries.remove('pin');
    _entries.remove('pinKind');
  }

  @override
  Future<double?> readTextScale() async => double.tryParse(_entries['textScale'] ?? '');

  @override
  Future<void> writeTextScale(double scale) async => _entries['textScale'] = '$scale';

  @override
  Future<String?> readDisguise() async => _entries['disguise'];

  @override
  Future<void> writeDisguise(String? skin) async {
    if (skin == null) {
      _entries.remove('disguise');
    } else {
      _entries['disguise'] = skin;
    }
  }

  @override
  Future<String?> readCallLog() async => _entries['callLog'];

  @override
  Future<void> writeCallLog(String? json) async {
    if (json == null) {
      _entries.remove('callLog');
    } else {
      _entries['callLog'] = json;
    }
  }

  @override
  Future<void> setDuressCode(String? code) async {
    if (code == null) {
      _entries.remove('duress');
    } else {
      _entries['duress'] = code;
    }
  }

  @override
  Future<bool> verifyDuressCode(String code) async => _entries['duress'] == code;

  /// What this store would still have after a relaunch: the written-down half,
  /// without the passcode and key a running process holds in memory.
  @visibleForTesting
  Map<String, String> get entriesForTest => Map.of(_entries);

  @visibleForTesting
  void restoreForTest(Map<String, String> entries) => _entries.addAll(entries);

  @override
  Future<bool> hasPasscode() async =>
      _entries.containsKey('archiveKeyWrapped') || _entries.containsKey('pin');

  @override
  Future<bool> verifyPasscode(String passcode) async {
    final wrapped = _entries['archiveKeyWrapped'];
    if (wrapped != null) {
      final key = await PasscodeVault.unwrap(passcode: passcode, wrapped: wrapped);
      if (key == null) return false;
      _sessionPasscode = passcode;
      _sessionArchiveKey = base64Encode(key);
      return true;
    }
    return _entries['pin'] == passcode;
  }

  @override
  Future<String?> readArchiveKey() async {
    if (_sessionArchiveKey != null) return _sessionArchiveKey;
    final wrapped = _entries['archiveKeyWrapped'];
    if (wrapped == null) return _entries['archiveKey'];
    final passcode = _sessionPasscode;
    if (passcode == null) throw const ArchiveLockedException();
    final key = await PasscodeVault.unwrap(passcode: passcode, wrapped: wrapped);
    if (key == null) throw const ArchiveLockedException();
    return _sessionArchiveKey = base64Encode(key);
  }

  @override
  Future<void> writeArchiveKey(String base64Key) async {
    final passcode = _sessionPasscode;
    if (passcode == null) {
      if (_entries.containsKey('archiveKeyWrapped')) {
        throw const ArchiveLockedException();
      }
      _entries['archiveKey'] = base64Key;
      return;
    }
    _sessionArchiveKey = base64Key;
    _entries['archiveKeyWrapped'] = await PasscodeVault.wrap(
      passcode: passcode,
      archiveKey: Uint8List.fromList(base64Decode(base64Key)),
    );
    _entries.remove('pin');
  }

  @override
  Future<String?> readRecoveryKey() async => _entries['recoveryKey'];

  @override
  Future<void> writeRecoveryKey(String base32Key) async => _entries['recoveryKey'] = base32Key;

  @override
  Future<DateTime?> readLastBackupAt() async => DateTime.tryParse(_entries['lastBackupAt'] ?? '');

  @override
  Future<void> writeLastBackupAt(DateTime when) async =>
      _entries['lastBackupAt'] = when.toIso8601String();

  @override
  Future<String?> readBackupInterval() async => _entries['backupInterval'];

  @override
  Future<void> writeBackupInterval(String interval) async => _entries['backupInterval'] = interval;

  @override
  Future<String?> readPendingLicenseKey() async => _entries['pendingLicenseKey'];

  @override
  Future<void> writePendingLicenseKey(String? key) async {
    if (key == null) {
      _entries.remove('pendingLicenseKey');
    } else {
      _entries['pendingLicenseKey'] = key;
    }
  }

  @override
  Future<String?> readLicenseCache() async => _entries['licenseCache'];

  @override
  Future<void> writeLicenseCache(String? json) async {
    if (json == null) {
      _entries.remove('licenseCache');
    } else {
      _entries['licenseCache'] = json;
    }
  }

  @override
  Future<String?> readActivationAskedFor() async => _entries['activationAskedFor'];

  @override
  Future<void> writeActivationAskedFor(String accountId) async =>
      _entries['activationAskedFor'] = accountId;

  @override
  Future<void> wipe() async {
    _sessionPasscode = null;
    _sessionArchiveKey = null;
    _entries.clear();
  }
}
