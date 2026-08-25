import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps the platform keystore: Keychain on iOS, Keystore-backed encrypted
/// preferences on Android. This is where the session token and the app-lock
/// state live — never in shared preferences, never on disk in the clear.
class SecureStore {
  const SecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'privio.session.token';
  static const _usernameKey = 'privio.session.username';
  static const _pinKey = 'privio.lock.pin';
  static const _biometricsKey = 'privio.lock.biometrics';

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  Future<String?> readToken() => _storage.read(
        key: _tokenKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<void> writeSession({required String token, required String username}) async {
    await _storage.write(
      key: _tokenKey,
      value: token,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.write(
      key: _usernameKey,
      value: username,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<String?> readUsername() => _storage.read(
        key: _usernameKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  /// The PIN is a *local* lock on an already-encrypted database, and the
  /// keychain is the security boundary that protects it. It is deliberately not
  /// stretched here: V2 moves PIN handling into the native crypto layer, where
  /// it derives a key-encryption key with Argon2id instead of being compared.
  Future<void> setPin(String pin) => _storage.write(
        key: _pinKey,
        value: pin,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<bool> hasPin() async => (await _storage.read(
        key: _pinKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      )) !=
      null;

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(
      key: _pinKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    return stored != null && stored == pin;
  }

  Future<bool> biometricsEnabled() async =>
      (await _storage.read(
        key: _biometricsKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      )) ==
      'true';

  Future<void> setBiometricsEnabled(bool enabled) => _storage.write(
        key: _biometricsKey,
        value: '$enabled',
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  /// Used by sign-out and by the wipe code: leaves nothing recoverable behind.
  Future<void> wipe() => _storage.deleteAll(
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
}
