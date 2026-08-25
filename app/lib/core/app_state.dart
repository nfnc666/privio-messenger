import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_store.dart';

/// Where the app is in the launch sequence, matching screens 1-5 of the mockups.
enum AppStage { splash, initialising, welcome, locked, ready }

/// App-wide session and lock state.
///
/// Kept deliberately small and dependency-free: a [ChangeNotifier] handed down
/// through [PrivioScope]. Feature state belongs in the feature, not here.
class AppState extends ChangeNotifier {
  AppState({SecureStore? store, LocalAuthentication? localAuth})
      : _store = store ?? const SecureStore(),
        _localAuth = localAuth ?? LocalAuthentication();

  final SecureStore _store;
  final LocalAuthentication _localAuth;

  AppStage _stage = AppStage.splash;
  String? _username;
  double _initProgress = 0;
  bool _biometricsAvailable = false;

  AppStage get stage => _stage;
  String? get username => _username;
  double get initProgress => _initProgress;
  bool get biometricsAvailable => _biometricsAvailable;

  /// Runs the "initialising secure environment" step (screen 2): opens the
  /// keystore, checks for a session, and finds out whether biometrics exist.
  Future<void> initialise() async {
    _stage = AppStage.initialising;
    notifyListeners();

    _setProgress(0.2);
    final token = await _store.readToken();
    _setProgress(0.5);
    _username = await _store.readUsername();
    _biometricsAvailable = await _canUseBiometrics();
    _setProgress(0.85);
    final hasPin = await _store.hasPin();
    _setProgress(1);

    _stage = token == null
        ? AppStage.welcome
        : hasPin
            ? AppStage.locked
            : AppStage.ready;
    notifyListeners();
  }

  void _setProgress(double value) {
    _initProgress = value;
    notifyListeners();
  }

  Future<bool> _canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } on Exception {
      // A device without biometric hardware is not an error; it just means the
      // PIN is the only way in.
      return false;
    }
  }

  /// Face ID / Touch ID / Android biometric prompt.
  Future<bool> unlockWithBiometrics() async {
    if (!_biometricsAvailable || !await _store.biometricsEnabled()) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock Privio',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) unlock();
      return ok;
    } on Exception {
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await _store.verifyPin(pin);
    if (ok) unlock();
    return ok;
  }

  void unlock() {
    _stage = AppStage.ready;
    notifyListeners();
  }

  /// Re-locks on backgrounding, so a shoulder-surfer gets the PIN pad.
  void lock() {
    if (_stage == AppStage.ready) {
      _stage = AppStage.locked;
      notifyListeners();
    }
  }

  void completeOnboarding(String username) {
    _username = username;
    _stage = AppStage.ready;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _store.wipe();
    _username = null;
    _stage = AppStage.welcome;
    notifyListeners();
  }
}

/// Makes [AppState] available to the widget tree without a state-management
/// package: `PrivioScope.of(context)` rebuilds dependents on change.
class PrivioScope extends InheritedNotifier<AppState> {
  const PrivioScope({required AppState super.notifier, required super.child, super.key});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PrivioScope>();
    assert(scope?.notifier != null, 'PrivioScope is missing from the tree');
    return scope!.notifier!;
  }
}
