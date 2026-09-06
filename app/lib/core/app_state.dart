import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'api_client.dart';
import 'channel_controller.dart';
import 'conversation_controller.dart';
import '../disguise/launcher_disguise.dart';
import '../disguise/skin.dart';
import 'passcode.dart';
import 'edition.dart';
import 'license_controller.dart';
import '../services/wake_up.dart';
import 'privio_services.dart';
import 'security_controller.dart';
import 'secure_store.dart';

/// Where the app is in the launch sequence, matching screens 1-5 of the design.
///
/// [activation] is the key screen, and it is reached from two directions.
///
/// Before the account, on a fresh install of a build that is activated with a
/// key: what the hosted service is paid for is asked for first, and the key is
/// held until there is an account to bind it to. And after signing in, once
/// per account, for anyone who walked past it the first time and is still
/// unlicensed — because walking past is allowed, and being nagged every launch
/// is not.
///
/// Neither is a wall. The server lets an unlicensed account sign in and read
/// what has already arrived; only sending is gated. A screen that refused
/// entry would be claiming a restriction the server does not apply.
enum AppStage { splash, initialising, activation, welcome, locked, ready }

/// App-wide session and lock state.
///
/// Owns [PrivioServices] and the stage transitions between them. Feature state
/// belongs in the feature; this is only what every screen needs to know.
class AppState extends ChangeNotifier {
  AppState({
    PrivioServices? services,
    SecureStore? store,
    PrivioEdition? edition,
    LauncherDisguise? launcher,
    bool? supportsDisguise,
  })  : _injectedServices = services,
        _store = store ?? KeystoreSecureStore(),
        _launcherDisguise = launcher ?? const PlatformLauncherDisguise(),
        disguiseSupported = supportsDisguise ?? platformSupportsDisguise,
        edition = edition ?? PrivioEdition.current;

  /// Whether this platform can wear the disguise at all.
  ///
  /// iOS cannot, so it is not offered there. An app's display name on iOS is
  /// fixed when it is built and there is no public API to change it, which
  /// would leave an iPhone showing a calculator icon still labelled Privio —
  /// a disguise that says its own name underneath itself. Half a disguise is
  /// not a small version of one; it is the thing it was meant to prevent.
  static bool get platformSupportsDisguise =>
      defaultTargetPlatform != TargetPlatform.iOS;

  /// False on iOS. Injectable so a test can be either kind of device.
  final bool disguiseSupported;

  final PrivioServices? _injectedServices;
  final SecureStore _store;

  /// The app's entry in the launcher. Injectable so a test can drive a device
  /// that refuses the change, which is a case no emulator here can produce.
  final LauncherDisguise _launcherDisguise;

  /// Which build this is. Injectable only so a test can be a store build; a
  /// shipped app has exactly one, fixed at compile time.
  final PrivioEdition edition;

  PrivioServices? _services;
  ConversationController? _conversations;
  ChannelController? _channels;
  LicenseController? _license;
  SecurityController? _security;
  WakeUpController? _wakeUp;

  AppStage _stage = AppStage.splash;
  String? _username;
  String? _accountId;
  double _initProgress = 0;
  String? _sessionToken;
  bool _screenLockSet = false;
  PasscodeKind? _passcodeKind;
  CalculatorSkin? _disguise;
  LauncherCapability _launcher = LauncherCapability.none;
  String? _disguiseError;
  double _textScale = 1;
  bool _busy = false;
  String? _authError;

  /// Which tab of the shell is showing.
  ///
  /// The tabs are kept alive by an `IndexedStack`, so `initState` fires once
  /// and a screen that loaded something on the way in never loads it again.
  /// This is how one finds out it is being looked at.
  int get selectedTab => _selectedTab;
  int _selectedTab = 0;

  set selectedTab(int index) {
    if (_selectedTab == index) return;
    _selectedTab = index;
    notifyListeners();
  }

  AppStage get stage => _stage;
  String? get username => _username;
  String? get accountId => _accountId;
  double get initProgress => _initProgress;

  /// Whether this device has a passcode on the app. Read at launch, because the
  /// stage machine needs it anyway.
  bool get screenLockSet => _screenLockSet;

  /// What shape it has, so the lock screen knows what to draw before anything
  /// is typed.
  PasscodeKind? get passcodeKind => _passcodeKind;

  /// Which calculator this device opens to when locked, or null for the lock
  /// screen.
  CalculatorSkin? get disguise => _disguise;

  /// True when a disguise could be switched on at all.
  ///
  /// A calculator has ten keys and no letters, so a passphrase cannot be typed
  /// into one. Rather than quietly offering a disguise that could never be got
  /// past, the setting says so and points at the screen lock.
  bool get disguiseAvailable =>
      disguiseSupported && _screenLockSet && (_passcodeKind?.isNumeric ?? false);

  /// What this device can change about the launcher entry: on Android both the
  /// icon and the name, on iOS the icon only, and on the web neither.
  LauncherCapability get launcherCapability => _launcher;

  /// Set when the launcher refused a change, so the screen can say the icon did
  /// not move rather than leaving someone to find out from the home screen.
  String? get disguiseError => _disguiseError;

  /// How much larger or smaller than the design's size text is drawn. The one
  /// appearance setting that does something: the rest of that screen used to be
  /// four rows that did nothing at all.
  double get textScale => _textScale;

  /// The sizes offered, as multipliers of the design.
  static const Map<String, double> textScales = {
    'Small': 0.9,
    'Medium': 1,
    'Large': 1.15,
    'Larger': 1.3,
  };

  String get textScaleLabel => textScales.entries
      .firstWhere(
        (entry) => (entry.value - _textScale).abs() < 0.01,
        orElse: () => const MapEntry('Medium', 1),
      )
      .key;

  Future<void> setTextScale(double scale) async {
    _textScale = scale;
    notifyListeners();
    await _store.writeTextScale(scale);
  }

  /// True while a sign-in or sign-up is in flight.
  bool get busy => _busy;

  /// Whether there is a session behind the current screen.
  ///
  /// The activation screen asks this to know which of its two jobs it is
  /// doing: holding a key for an account that does not exist yet, or redeeming
  /// one for an account that does.
  bool get signedIn => _sessionToken != null;

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
  LicenseController get license => _license ??= LicenseController(services.api, store: _store);

  /// How this device asks to be told that something arrived.
  WakeUpController get wakeUp => _wakeUp ??= WakeUpController(services.api);

  /// The second factor, who may see your last-seen, and who is blocked.
  SecurityController get security => _security ??= SecurityController(services.api);

  /// Runs the "initialising secure environment" step: opens the keystore, loads
  /// this device's identity, restores a session if there is one, and reads
  /// whether this device has an app lock.
  Future<void> initialise() async {
    _stage = AppStage.initialising;
    notifyListeners();

    _setProgress(0.15);
    // The store goes in rather than being made again inside: it holds the
    // archive key the passcode opened, and two instances would mean the lock
    // screen unlocking one of them while the archive waits on the other.
    _services = _injectedServices ?? await PrivioServices.create(secureStore: _store);
    _setProgress(0.45);

    final token = await _store.readToken();
    _username = await _store.readUsername();
    _accountId = await _store.readAccountId();
    _setProgress(0.7);

    _textScale = await _store.readTextScale() ?? 1;
    final hasPasscode = await _store.hasPasscode();
    _screenLockSet = hasPasscode;
    _passcodeKind = await _store.passcodeKind();
    _disguise = CalculatorSkin.parse(await _store.readDisguise());
    if (!disguiseSupported && _disguise != null) {
      // A device that cannot wear it must not be left locked behind it — a
      // restored install, or a build where support was withdrawn.
      _disguise = null;
      await _store.writeDisguise(null);
    }
    // Deliberately not awaited. Nothing about starting up depends on what the
    // launcher can do — only the wording on one settings screen does — and a
    // start-up that blocks on a platform channel is a start-up that hangs
    // wherever the channel has nobody on the other end.
    unawaited(_readLauncherCapability());
    _setProgress(1);

    unawaited(license.restore());

    if (token == null) {
      _stage = await _needsActivationFirst() ? AppStage.activation : AppStage.welcome;
    } else {
      services.api.useToken(token);
      _sessionToken = token;
      _stage = hasPasscode ? AppStage.locked : AppStage.ready;
      if (_stage == AppStage.ready) _onSignedIn();
    }
    notifyListeners();
  }

  /// Whether to put the key screen in front of a brand-new install.
  ///
  /// Three ways to answer no, and all of them matter: this build is sold
  /// through a store, a key is already waiting to be redeemed, or the server
  /// does not require one. The last is the only question that needs the
  /// network — and if it cannot be reached, the answer is still no. A launch
  /// screen that a flaky connection can turn into a paywall would be a bug
  /// worse than a missed prompt.
  Future<bool> _needsActivationFirst() async {
    if (!edition.usesLicenseKey) return false;
    if (await _store.readPendingLicenseKey() != null) return false;
    try {
      final info = await services.api.serverInfo();
      return info['licenseRequired'] as bool? ?? false;
    } on Object {
      return false;
    }
  }

  void _setProgress(double value) {
    _initProgress = value;
    notifyListeners();
  }

  // --- Authentication -------------------------------------------------------

  /// Registers a new account and this device's key material in one step.
  Future<bool> register({required String username, required String password}) => _authenticate(
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
    // A key request arrives on the socket, and the channels' keys live in a
    // different controller: the conversation one answers for groups and calls
    // this for the rest.
    controller.onKeyRequest = () => channels.deliverPendingKeys();
    unawaited(controller.maintainKeys());
    // A "their key changed" notice raised in an earlier run is still owed to
    // the user, so it is read back before anything else can bury it.
    unawaited(controller.loadKeyChangeAlerts());
    // So a send can address this account's own other devices. Without it the
    // copy has nowhere to go and a second device's history quietly diverges.
    services.messaging.identifyAs(_username);
    // Where a call would find a relay, fetched now rather than when someone
    // dials: asking at the moment of a call tells the server a call is about
    // to happen, and everything else about a call is sealed from it.
    unawaited(services.ice.ensure());
    // Whether this server sells access is a property of the server, so it has
    // to be asked rather than assumed. Never blocks the UI.
    //
    // A key entered before the account existed is spent first, the moment there
    // is an account to bind it to; redeeming already brings the status back, so
    // only the case where there was nothing to redeem needs the extra call. A
    // failure here leaves a signed-in, readable app and a message on the
    // licence screen, not a blocked launch.
    unawaited(
      license.redeemPending().then((redeemed) async {
        if (!redeemed) await license.refresh();
        await _askAboutLicense();
      }),
    );
  }

  /// The second chance: shows the key screen to someone who is signed in,
  /// still unlicensed, and has not been asked before.
  ///
  /// The first chance is the launch screen, before the account. This one exists
  /// because that screen can be walked past — deliberately — and an account
  /// that skipped it would otherwise only ever learn it needs a key by trying
  /// to send and being refused.
  ///
  /// Never in front of the app: the answer arrives over the network, and a
  /// launch that waits on a licence server is a launch that fails when the
  /// licence server does.
  Future<void> _askAboutLicense() async {
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

  /// Turns the app lock on, or changes the passcode.
  ///
  /// Nothing in the app could do this until recently: `AppStage.locked` existed,
  /// the lock screen existed, and no code path ever set a passcode, so the lock
  /// could never come on.
  Future<void> setScreenLock(String passcode, PasscodeKind kind) async {
    await _store.setPasscode(passcode, kind);
    _screenLockSet = true;
    _passcodeKind = kind;
    notifyListeners();
  }

  /// Turns it off. Takes the duress code with it: a code that unlocks nothing
  /// cannot be typed at a lock screen that is not there, and leaving it behind
  /// would be a wipe waiting on a screen nobody sees.
  Future<void> clearScreenLock() async {
    await _store.clearPasscode();
    await _store.setDuressCode(null);
    await _store.writeDisguise(null);
    _screenLockSet = false;
    _passcodeKind = null;
    _disguise = null;
    notifyListeners();
  }

  Future<void> _readLauncherCapability() async {
    final capability = await _launcherDisguise.capability();
    if (capability == _launcher) return;
    _launcher = capability;
    notifyListeners();
  }

  /// Puts the disguise on, or takes it off.
  ///
  /// Turning the lock off takes it with it, so this cannot outlive the code
  /// that opens it: a calculator nobody can get past is a locked-out phone.
  Future<void> setDisguise(CalculatorSkin? skin) async {
    if (skin != null && !disguiseAvailable) return;
    await _store.writeDisguise(skin?.name);
    _disguise = skin;
    _disguiseError = null;
    // The lock screen is Privio's to change and the launcher is the platform's
    // to refuse. The setting takes effect either way — a disguise that is on
    // everywhere except the home screen is still worth having — and the failure
    // is reported rather than swallowed.
    try {
      await _launcherDisguise.apply(skin);
    } on LauncherDisguiseException catch (failure) {
      _disguiseError = failure.message;
    }
    notifyListeners();
  }

  /// Stores the duress code locally so the lock screen can recognise it with no
  /// network. Only ever called with what the server has just accepted.
  Future<void> rememberDuressCode(String? code) => _store.setDuressCode(code);

  /// Leaves the activation step, for wherever it was entered from.
  ///
  /// Before the account there is nothing signed in yet, so it goes back to the
  /// welcome flow; afterwards it goes into the app. [asked] records that this
  /// account has now seen the question, which is what "Not now" means — a
  /// successful activation does not need recording, because the server stops
  /// saying a key is needed. There is nothing to record before an account
  /// exists, and nothing that needs it: that screen is only ever shown to an
  /// install with no session at all.
  Future<void> leaveActivation({bool asked = true}) async {
    if (_stage != AppStage.activation) return;
    final accountId = _accountId;
    if (asked && accountId != null && _sessionToken != null) {
      await _store.writeActivationAskedFor(accountId);
    }
    _stage = _sessionToken == null ? AppStage.welcome : AppStage.ready;
    notifyListeners();
  }

  // --- Lock -----------------------------------------------------------------

  Future<bool> unlockWithPasscode(String passcode) async {
    // The duress code is checked first and answers false either way: from the
    // outside, a wipe and a wrong passcode are the same event.
    if (await _store.verifyDuressCode(passcode)) {
      await _duressWipe(passcode);
      return false;
    }
    final ok = await _store.verifyPasscode(passcode);
    if (ok) unlock();
    return ok;
  }

  /// Destroys everything this device holds, and asks the server to destroy what
  /// it holds, after the duress code was entered at the lock screen.
  ///
  /// Local first, and unconditionally: the phone is in someone else's hands, and
  /// the network is the part that might not be there. The server call carries
  /// the code rather than the password, because under duress the password is
  /// the one thing nobody is about to type.
  Future<void> _duressWipe(String code) async {
    final services = _services;
    if (services != null) {
      _conversations?.stop();
      services.messaging.identifyAs(null);
      services.ice.clear();
      services.store.clear();
      try {
        await services.archive.clear();
      } on Object {
        // Nothing here may stop the rest of the wipe.
      }
      try {
        await services.crypto.wipe();
      } on Object {
        // Same.
      }
      unawaited(_wipeOnServer(services, code));
    }
    await _store.wipe();
    _conversations?.dispose();
    _conversations = null;
    _channels?.dispose();
    _channels = null;
    _license?.dispose();
    _license = null;
    _security?.dispose();
    _security = null;
    _screenLockSet = false;
    _passcodeKind = null;
    // In memory as well as on disk. A disguise left set after a wipe would send
    // whoever holds the phone next to a calculator with no code to get past it.
    _disguise = null;
    _sessionToken = null;
    _username = null;
    _accountId = null;
  }

  /// Best effort, and deliberately not awaited by the caller: a phone with no
  /// signal must still lose its local copy immediately.
  Future<void> _wipeOnServer(PrivioServices services, String code) async {
    try {
      await services.api.wipeAccount(code);
    } on Object {
      // The local wipe has already happened. There is nothing to report to a
      // screen that is about to be showing a wrong-PIN error.
    }
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
    // A device with no passcode has nothing to unlock with. Arming the lock
    // there is not a stricter lock, it is a device its own owner cannot get
    // back into: the lock screen has exactly one way past it, and on a device
    // that never set one, no input is the right one. Backgrounding the app
    // used to do this.
    if (!_screenLockSet) return;
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

  /// Deletes the account on the server, then destroys everything here.
  ///
  /// The server asks for the password, which is what stops a session somebody
  /// picked up from ending an account. Nothing local is touched until the
  /// server has actually done it: a failed delete that had already wiped the
  /// phone would be the worst of both.
  ///
  /// Returns null on success, or what to tell the user.
  Future<String?> deleteAccount(String currentPassword) async {
    try {
      await services.api.deleteAccount(currentPassword);
    } on ApiException catch (failure) {
      return failure.message;
    } on Object {
      return 'Could not reach the server.';
    }

    _conversations?.stop();
    services.api.useToken(null);
    services.messaging.identifyAs(null);
    services.ice.clear();
    services.store.clear();
    try {
      await services.archive.clear();
    } on Object {
      // The account is gone; nothing here may stop the rest.
    }
    try {
      // Unlike signing out, the identity goes too. There is no account left
      // for these keys to belong to, and keeping them is only a liability.
      await services.crypto.wipe();
    } on Object {
      // Same.
    }
    _conversations?.dispose();
    _conversations = null;
    _channels?.dispose();
    _channels = null;
    _license?.dispose();
    _license = null;
    _security?.dispose();
    _security = null;
    _wakeUp?.dispose();
    _wakeUp = null;
    await _store.wipe();
    _screenLockSet = false;
    _passcodeKind = null;
    _disguise = null;
    _sessionToken = null;
    _username = null;
    _accountId = null;
    _stage = AppStage.welcome;
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _conversations?.stop();
    try {
      await services.api.logout();
    } on Object {
      // A dead session on the server is no reason to keep one on the device.
    }
    services.api.useToken(null);
    services.messaging.identifyAs(null);
    _sessionToken = null;
    services.ice.clear();
    services.store.clear();
    _channels?.dispose();
    _channels = null;
    _license?.dispose();
    _wakeUp?.dispose();
    _license = null;
    _security?.dispose();
    _security = null;
    _screenLockSet = false;
    _passcodeKind = null;
    _disguise = null;
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
