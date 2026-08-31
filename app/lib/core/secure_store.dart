import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Future<void> setPin(String pin);
  Future<bool> hasPin();
  Future<bool> verifyPin(String pin);

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

  Future<bool> biometricsEnabled();
  Future<void> setBiometricsEnabled(bool enabled);

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
  static const _pinKey = 'privio.lock.pin';
  static const _archiveKeyKey = 'privio.archive.key';
  static const _recoveryKeyKey = 'privio.backup.recovery_key';
  static const _lastBackupKey = 'privio.backup.last_at';
  static const _backupIntervalKey = 'privio.backup.interval';
  static const _biometricsKey = 'privio.lock.biometrics';
  static const _activationAskedKey = 'privio.license.activation_asked_for';

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  Future<String?> _read(String key) =>
      _storage.read(key: key, iOptions: _iosOptions, aOptions: _androidOptions);

  Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value, iOptions: _iosOptions, aOptions: _androidOptions);

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

  /// The PIN is a *local* lock on an already-encrypted database, and the
  /// keychain is the security boundary that protects it. It is deliberately not
  /// stretched here: V2 moves PIN handling into the native crypto layer, where
  /// it derives a key-encryption key with Argon2id instead of being compared.
  @override
  Future<void> setPin(String pin) => _write(_pinKey, pin);

  @override
  Future<bool> hasPin() async => await _read(_pinKey) != null;

  @override
  Future<bool> verifyPin(String pin) async {
    final stored = await _read(_pinKey);
    return stored != null && stored == pin;
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
  Future<bool> biometricsEnabled() async => await _read(_biometricsKey) == 'true';

  @override
  Future<void> setBiometricsEnabled(bool enabled) => _write(_biometricsKey, '$enabled');

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
  Future<void> setPin(String pin) async => _entries['pin'] = pin;

  @override
  Future<bool> hasPin() async => _entries.containsKey('pin');

  @override
  Future<bool> verifyPin(String pin) async => _entries['pin'] == pin;

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
  Future<bool> biometricsEnabled() async => _entries['biometrics'] == 'true';

  @override
  Future<void> setBiometricsEnabled(bool enabled) async =>
      _entries['biometrics'] = '$enabled';

  @override
  Future<String?> readActivationAskedFor() async => _entries['activationAskedFor'];

  @override
  Future<void> writeActivationAskedFor(String accountId) async =>
      _entries['activationAskedFor'] = accountId;

  @override
  Future<void> wipe() async => _entries.clear();
}
