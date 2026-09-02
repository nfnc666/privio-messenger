import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'passcode.dart';

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

/// The platform keystore: Keychain on iOS, Keystore-backed encrypted
/// preferences on Android. Never shared preferences, never a plain file.
class KeystoreSecureStore implements SecureStore {
  const KeystoreSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'privio.session.token';
  static const _usernameKey = 'privio.session.username';
  static const _accountIdKey = 'privio.session.account_id';
  static const _passcodeKey = 'privio.lock.pin';
  static const _passcodeKindKey = 'privio.lock.kind';
  static const _duressKey = 'privio.lock.duress';
  static const _textScaleKey = 'privio.appearance.text_scale';
  static const _archiveKeyKey = 'privio.archive.key';
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

  /// The passcode is a *local* lock on an already-encrypted database, and the
  /// keychain is the security boundary that protects it. It is deliberately not
  /// stretched here: V2 moves it into the native crypto layer, where it derives
  /// a key-encryption key with Argon2id instead of being compared.
  @override
  Future<void> setPasscode(String passcode, PasscodeKind kind) async {
    await _write(_passcodeKey, passcode);
    await _write(_passcodeKindKey, kind.id);
  }

  @override
  Future<PasscodeKind?> passcodeKind() async =>
      PasscodeKind.parse(await _read(_passcodeKindKey));

  @override
  Future<bool> hasPasscode() async => await _read(_passcodeKey) != null;

  @override
  Future<void> clearPasscode() async {
    await _storage.delete(key: _passcodeKey, iOptions: _iosOptions, aOptions: _androidOptions);
    await _storage.delete(
      key: _passcodeKindKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  @override
  Future<double?> readTextScale() async =>
      double.tryParse(await _read(_textScaleKey) ?? '');

  @override
  Future<void> writeTextScale(double scale) => _write(_textScaleKey, '$scale');

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
    final stored = await _read(_passcodeKey);
    return stored != null && stored == passcode;
  }

  @override
  Future<String?> readArchiveKey() => _read(_archiveKeyKey);

  @override
  Future<void> writeArchiveKey(String base64Key) => _write(_archiveKeyKey, base64Key);

  @override
  Future<String?> readRecoveryKey() => _read(_recoveryKeyKey);

  @override
  Future<void> writeRecoveryKey(String base32Key) => _write(_recoveryKeyKey, base32Key);

  @override
  Future<DateTime?> readLastBackupAt() async =>
      DateTime.tryParse(await _read(_lastBackupKey) ?? '');

  @override
  Future<void> writeLastBackupAt(DateTime when) =>
      _write(_lastBackupKey, when.toIso8601String());

  @override
  Future<String?> readBackupInterval() => _read(_backupIntervalKey);

  @override
  Future<void> writeBackupInterval(String interval) =>
      _write(_backupIntervalKey, interval);

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
  Future<void> writeActivationAskedFor(String accountId) =>
      _write(_activationAskedKey, accountId);

  @override
  Future<void> wipe() =>
      _storage.deleteAll(iOptions: _iosOptions, aOptions: _androidOptions);
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

  @override
  Future<void> setPasscode(String passcode, PasscodeKind kind) async {
    _entries['pin'] = passcode;
    _entries['pinKind'] = kind.id;
  }

  @override
  Future<PasscodeKind?> passcodeKind() async => PasscodeKind.parse(_entries['pinKind']);

  @override
  Future<void> clearPasscode() async {
    _entries.remove('pin');
    _entries.remove('pinKind');
  }

  @override
  Future<double?> readTextScale() async => double.tryParse(_entries['textScale'] ?? '');

  @override
  Future<void> writeTextScale(double scale) async => _entries['textScale'] = '$scale';

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

  @override
  Future<bool> hasPasscode() async => _entries.containsKey('pin');

  @override
  Future<bool> verifyPasscode(String passcode) async => _entries['pin'] == passcode;

  @override
  Future<String?> readArchiveKey() async => _entries['archiveKey'];

  @override
  Future<void> writeArchiveKey(String base64Key) async => _entries['archiveKey'] = base64Key;

  @override
  Future<String?> readRecoveryKey() async => _entries['recoveryKey'];

  @override
  Future<void> writeRecoveryKey(String base32Key) async =>
      _entries['recoveryKey'] = base32Key;

  @override
  Future<DateTime?> readLastBackupAt() async =>
      DateTime.tryParse(_entries['lastBackupAt'] ?? '');

  @override
  Future<void> writeLastBackupAt(DateTime when) async =>
      _entries['lastBackupAt'] = when.toIso8601String();

  @override
  Future<String?> readBackupInterval() async => _entries['backupInterval'];

  @override
  Future<void> writeBackupInterval(String interval) async =>
      _entries['backupInterval'] = interval;

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
  Future<void> wipe() async => _entries.clear();
}
