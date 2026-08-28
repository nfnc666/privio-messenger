import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'api_client.dart';
import 'biometric_gate.dart';
import 'channel_controller.dart';
import 'conversation_controller.dart';
import 'license_controller.dart';
import 'privio_services.dart';
import 'secure_store.dart';

/// Where the app is in the launch sequence, matching screens 1-5 of the design.
enum AppStage { splash, initialising, welcome, locked, ready }

/// App-wide session and lock state.
///
/// Owns [PrivioServices] and the stage transitions between them. Feature state
/// belongs in the feature; this is only what every screen needs to know.
class AppState extends ChangeNotifier {
  AppState({
    PrivioServices? services,
    SecureStore? store,
    BiometricGate? biometrics,
  })  : _injectedServices = services,
        _store = store ?? const KeystoreSecureStore(),
        _biometrics = biometrics ?? LocalAuthBiometricGate();

  final PrivioServices? _injectedServices;
  final SecureStore _store;
  final BiometricGate _biometrics;

  PrivioServices? _services;
  ConversationController? _conversations;
  ChannelController? _channels;
  LicenseController? _license;

  AppStage _stage = AppStage.splash;
  String? _username;
  String? _accountId;
  double _initProgress = 0;
  String? _sessionToken;
  bool _biometricsAvailable = false;
  bool _busy = false;
  String? _authError;

  AppStage get stage => _stage;
  String? get username => _username;
  String? get accountId => _accountId;
  double get initProgress => _initProgress;
  bool get biometricsAvailable => _biometricsAvailable;

  /// True while a sign-in or sign-up is in flight.
  bool get busy => _busy;

  /// The last authentication failure, in words a user can act on.
  String? get authError => _authError;

  PrivioServices get services {
    final services = _services;
    if (services == null) throw StateError('Services are not ready yet');
    return services;
  }

  ConversationController get conversations {
    return _conversations ??= ConversationController(services);
  }

  ChannelController get channels => _channels ??= ChannelController(services);

  LicenseController get license => _license ??= LicenseController(services.api);

  /// Runs the "initialising secure environment" step: opens the keystore, loads
  /// this device's identity, restores a session if there is one, and finds out
  /// whether biometrics exist.
  Future<void> initialise() async {
    _stage = AppStage.initialising;
    notifyListeners();

    _setProgress(0.15);
    _services = _injectedServices ?? await PrivioServices.create();
    _setProgress(0.45);

    final token = await _store.readToken();
    _username = await _store.readUsername();
    _accountId = await _store.readAccountId();
    _setProgress(0.7);

    _biometricsAvailable = await _biometrics.isAvailable();
    final hasPin = await _store.hasPin();
    _setProgress(1);

    if (token == null) {
      _stage = AppStage.welcome;
    } else {
      services.api.useToken(token);
      _sessionToken = token;
      _stage = hasPin ? AppStage.locked : AppStage.ready;
      if (_stage == AppStage.ready) _onSignedIn();
    }
    notifyListeners();
  }

  void _setProgress(double value) {
    _initProgress = value;
    notifyListeners();
  }

  // --- Authentication -------------------------------------------------------

  /// Registers a new account and this device's key material in one step.
  Future<bool> register({required String username, required String password}) =>
      _authenticate(
        () async => services.api.register(
          username: username,
          password: password,
          device: await _deviceRegistration(),
        ),
      );

  Future<bool> signIn({
    required String username,
    required String password,
    String? totpCode,
  }) =>
      _authenticate(
        () async => services.api.login(
          username: username,
          password: password,
          totpCode: totpCode,
          device: await _deviceRegistration(),
        ),
      );

  Future<bool> _authenticate(Future<Map<String, dynamic>> Function() call) async {
    _busy = true;
    _authError = null;
    notifyListeners();
    try {
      final result = await call();
      final token = result['token'] as String;
      _sessionToken = token;
      _username = result['username'] as String;
      _accountId = result['accountId'] as String;
      services.api.useToken(token);
      await _store.writeSession(
        token: token,
        username: _username!,
        accountId: _accountId!,
      );
      _stage = AppStage.ready;
      _onSignedIn();
      return true;
    } on ApiException catch (failure) {
      _authError = _explain(failure);
      return false;
    } on Object {
      _authError = 'Could not reach Privio. Check your connection.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Server error codes turned into something a person can act on.
  static String _explain(ApiException failure) => switch (failure.code) {
        'username_taken' => 'That username is already taken.',
        'invalid_credentials' => 'Username or password is incorrect.',
        'totp_required' => 'Enter your two-factor code.',
        'invalid_totp' => 'That two-factor code is not right.',
        'invalid_request' => 'Check the username and password: ${failure.message}',
        'rate_limited' => 'Too many attempts. Wait a few minutes.',
        'too_many_devices' => 'This account already has the maximum number of devices.',
        _ => failure.message,
      };

  /// The public key material this device publishes when it registers.
  Future<Map<String, dynamic>> _deviceRegistration() => services.crypto.buildRegistration(
        name: _deviceName(),
        platform: _platformName(),
      );

  static String _deviceName() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.android => 'Android phone',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'Windows PC',
        TargetPlatform.linux => 'Linux PC',
        _ => 'Privio device',
      };

  static String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'desktop',
    };
  }

  void _onSignedIn() {
    // Read the sealed history back first, then start draining the queue and top
    // up prekeys — but never block the UI on any of it.
    final controller = conversations;
    unawaited(controller.restore().then((_) => controller.start(token: _sessionToken)));
    unawaited(controller.refreshContacts());
    unawaited(controller.maintainKeys());
    // Whether this server sells access is a property of the server, so it has
    // to be asked rather than assumed. Never blocks the UI.
    unawaited(license.refresh());
  }

  // --- Lock -----------------------------------------------------------------

  Future<bool> unlockWithBiometrics() async {
    if (!_biometricsAvailable || !await _store.biometricsEnabled()) return false;
    final ok = await _biometrics.authenticate('Unlock Privio');
    if (ok) unlock();
    return ok;
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await _store.verifyPin(pin);
    if (ok) unlock();
    return ok;
  }

  void unlock() {
    _stage = AppStage.ready;
    _onSignedIn();
    notifyListeners();
  }

  /// Re-locks on backgrounding, so a shoulder-surfer gets the PIN pad.
  ///
  /// Also the moment an automatic backup happens: the history has just been
  /// flushed, the app is not being used, and it is the point at which "I lost
  /// my phone" starts being a possibility.
  void lock() {
    if (_stage == AppStage.ready) {
      _conversations
        ?..stop()
        ..flush();
      unawaited(_services?.backup.backUpIfDue() ?? Future<bool>.value(false));
      _stage = AppStage.locked;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _conversations?.stop();
    try {
      await services.api.logout();
    } on Object {
      // A dead session on the server is no reason to keep one on the device.
    }
    services.api.useToken(null);
    _sessionToken = null;
    services.store.clear();
    _channels?.dispose();
    _channels = null;
    _license?.dispose();
    _license = null;
    await services.archive.clear();
    await _store.wipe();
    _username = null;
    _accountId = null;
    _stage = AppStage.welcome;
    notifyListeners();
  }

  @override
  void dispose() {
    _license?.dispose();
    _channels?.dispose();
    _conversations?.dispose();
    _services?.dispose();
    super.dispose();
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
