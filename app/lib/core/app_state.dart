import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'api_client.dart';
import 'biometric_gate.dart';
import 'channel_controller.dart';
import 'conversation_controller.dart';
import 'edition.dart';
import 'license_controller.dart';
import 'privio_services.dart';
import 'security_controller.dart';
import 'secure_store.dart';

/// Where the app is in the launch sequence, matching screens 1-5 of the design.
///
/// [activation] sits between signing in and the app itself: on a server that
/// sells access, a brand new account is asked for its key once, before it is
/// dropped into an empty chat list it cannot write to.
enum AppStage { splash, initialising, welcome, locked, activation, ready }

/// App-wide session and lock state.
///
/// Owns [PrivioServices] and the stage transitions between them. Feature state
/// belongs in the feature; this is only what every screen needs to know.
class AppState extends ChangeNotifier {
  AppState({
    PrivioServices? services,
    SecureStore? store,
    BiometricGate? biometrics,
    PrivioEdition? edition,
  })  : _injectedServices = services,
        _store = store ?? const KeystoreSecureStore(),
        _biometrics = biometrics ?? LocalAuthBiometricGate(),
        edition = edition ?? PrivioEdition.current;

  final PrivioServices? _injectedServices;
  final SecureStore _store;
  final BiometricGate _biometrics;

  /// Which build this is. Injectable only so a test can be a store build; a
  /// shipped app has exactly one, fixed at compile time.
  final PrivioEdition edition;

  PrivioServices? _services;
  ConversationController? _conversations;
  ChannelController? _channels;
  LicenseController? _license;
  SecurityController? _security;

  AppStage _stage = AppStage.splash;
  String? _username;
  String? _accountId;
  double _initProgress = 0;
  String? _sessionToken;
  bool _biometricsAvailable = false;
  bool _screenLockSet = false;
  bool _busy = false;
  String? _authError;

  AppStage get stage => _stage;
  String? get username => _username;
  String? get accountId => _accountId;
  double get initProgress => _initProgress;
  bool get biometricsAvailable => _biometricsAvailable;

  /// Whether this device has a PIN on the app. Read at launch, because the
  /// stage machine needs it anyway.
  bool get screenLockSet => _screenLockSet;

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

  /// Activation state. Created lazily like the others, and refreshed on sign-in
  /// so the settings entry knows whether it has anything to say.
  LicenseController get license => _license ??= LicenseController(services.api);

  /// The second factor, who may see your last-seen, and who is blocked.
  SecurityController get security => _security ??= SecurityController(services.api);

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
    _screenLockSet = hasPin;
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
    final controller = conversations..accountId = _accountId;
    unawaited(controller.restore().then((_) => controller.start(token: _sessionToken)));
    unawaited(controller.refreshContacts());
    unawaited(controller.maintainKeys());
    // Whether this server sells access is a property of the server, so it has
    // to be asked rather than assumed. Never blocks the UI.
    unawaited(_askAboutLicense());
  }

  /// Asks the server about the license and, on the one answer that needs the
  /// user, shows the activation step.
  ///
  /// Deliberately after the app is already usable rather than in front of it:
  /// the answer arrives over the network, and a launch that waits on a licence
  /// server is a launch that fails when the licence server does.
  Future<void> _askAboutLicense() async {
    await license.refresh();
    if (!license.needsActivation) return;
    // Only the builds that are activated with a key ask for one. An App Store
    // or Play build was paid for at the moment it was installed, so there is
    // nothing for its owner to type — putting a key field in front of them
    // would be asking for something this build cannot have. If such a build
    // still comes back unlicensed, that is a receipt to settle with the store,
    // and the License row in Settings is where it says so.
    if (!edition.usesLicenseKey) return;
    // Never over the lock screen, and never over a sign-out that happened while
    // the request was in flight.
    if (_stage != AppStage.ready) return;
    final accountId = _accountId;
    if (accountId == null) return;
    // Asked once per account. Someone who said "Not now" is not asked again on
    // every launch — the Settings row and the send error are enough after that.
    if (await _store.readActivationAskedFor() == accountId) return;
    if (_stage != AppStage.ready) return;
    _stage = AppStage.activation;
    notifyListeners();
  }

  /// Leaves the activation step for the app itself.
  ///
  /// [asked] records that this account has now seen it, which is what "Not now"
  /// means; a successful activation does not need recording, because the server
  /// will not ask again.
  Future<void> leaveActivation({bool asked = true}) async {
    if (_stage != AppStage.activation) return;
    final accountId = _accountId;
    if (asked && accountId != null) {
      await _store.writeActivationAskedFor(accountId);
    }
    _stage = AppStage.ready;
    notifyListeners();
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
    // Activation counts as being inside the app: the account is signed in, and
    // what is on screen is a key someone is typing. Unlocking runs the license
    // question again, so the step comes back rather than being skipped.
    if (_stage == AppStage.ready || _stage == AppStage.activation) {
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
    _security?.dispose();
    _security = null;
    _screenLockSet = false;
    await services.archive.clear();
    await _store.wipe();
    _username = null;
    _accountId = null;
    _stage = AppStage.welcome;
    notifyListeners();
  }

  @override
  void dispose() {
    _security?.dispose();
    _license?.dispose();
    _channels?.dispose();
    _conversations?.dispose();
    _license?.dispose();
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
