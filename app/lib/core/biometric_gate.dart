import 'package:local_auth/local_auth.dart';

/// Face ID / Touch ID / the Android biometric prompt.
///
/// Behind an interface for the same reason the key stores are: awaiting a
/// platform channel is not something the pure logic should do, and a test must
/// be able to run the launch sequence without one.
abstract interface class BiometricGate {
  /// Whether this device has usable biometric hardware.
  Future<bool> isAvailable();

  /// Prompts the user. Returns false when they cancel or it fails.
  Future<bool> authenticate(String reason);
}

class LocalAuthBiometricGate implements BiometricGate {
  LocalAuthBiometricGate([this._injected]);

  final LocalAuthentication? _injected;

  /// Constructed lazily and inside the guard: on a platform with no local_auth
  /// implementation, even creating it throws.
  LocalAuthentication get _auth => _injected ?? LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      final auth = _auth;
      return await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } on Object {
      // No biometric hardware is not an error; it means the PIN is the only way in.
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on Object {
      return false;
    }
  }
}

/// Used in tests and on devices without biometrics.
class NoBiometrics implements BiometricGate {
  const NoBiometrics();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}
