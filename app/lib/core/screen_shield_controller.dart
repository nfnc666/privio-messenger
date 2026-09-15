import 'package:flutter/foundation.dart';

import '../security/screen_shield.dart';
import 'secure_store.dart';

/// Whether this account has asked the operating system to protect its screen.
///
/// Per account, and loaded at sign-in, for the reason every other per-account
/// setting here is: two people sharing a phone do not share a threat model, and
/// a second account must not inherit the first one's answer. A new account
/// starts off, which is what the platform does when nobody has said otherwise.
///
/// What "protected" means is **not** the same on the two platforms, and this
/// class does not pretend otherwise. It holds the capability the device
/// reported and hands it to the screen, which says what is actually true here
/// rather than one sentence that is true on Android and a lie on iOS.
class ScreenShieldController extends ChangeNotifier {
  ScreenShieldController(this._shield, this._store);

  final ScreenShield _shield;
  final SecureStore _store;

  String? _accountId;
  bool _enabled = false;
  bool _captured = false;
  ScreenShieldCapability _capability = ScreenShieldCapability.none;
  bool _asked = false;

  /// Bumped by every deliberate change. A [load] that started before one and
  /// finishes after it must not overwrite the answer the person just gave:
  /// signing in kicks off a read, and somebody who reaches this switch while it
  /// is still in flight would otherwise watch their own choice revert. Found by
  /// a test that turned the switch on during sign-in.
  int _choice = 0;

  /// The account these values belong to, or null before the first load.
  String? get accountId => _accountId;

  /// What the account chose. False until something has been read — never a
  /// guess that the platform is already protecting anything.
  bool get enabled => _enabled;

  /// What this device can actually do about it.
  ScreenShieldCapability get capability => _capability;

  /// Whether the platform has been asked. The screen shows nothing rather than
  /// "unavailable" until it has.
  bool get asked => _asked;

  /// Whether a recording or a mirrored display is running right now.
  ///
  /// Only ever true on a platform that detects capture, and only while the
  /// setting is on: a device that is not protecting anything has no business
  /// covering the screen.
  bool get captured => _captured;

  /// Whether the interface should be covered this instant.
  ///
  /// The one thing the app itself has to act on. On Android it is never true —
  /// the window manager has already refused the recorder, so there is nothing
  /// for Privio to hide and hiding it would blank the screen for a person who
  /// is simply using their phone.
  ///
  /// The capability term is a **second** guard, not the one doing the work:
  /// [_apply] never starts listening on a platform that cannot detect anything,
  /// so `_captured` is already false there. It stays because the cost is one
  /// `&&` and the failure it guards against — the whole app going blank on a
  /// phone in ordinary use — is the worst outcome this feature has.
  bool get shouldCover => _enabled && _capability.detectsCapture && _captured;

  /// Reads this account's choice and applies it.
  ///
  /// Resets first, so a slow keystore cannot leave the previous account's
  /// protection in force while this one's answer is being read — and the reset
  /// clears the flag rather than leaving it, because the safe direction to fail
  /// in is "off but about to be on", not "on for somebody who never asked".
  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _enabled = false;
      _captured = false;
      notifyListeners();
    }

    _capability = await _shield.capability();
    _asked = true;
    if (!_stillOn(accountId)) return;

    final choice = _choice;
    final wanted = await _store.readScreenShield(accountId);
    if (!_stillOn(accountId)) return;
    // Somebody changed it while this read was in flight. Their answer is newer
    // than the stored one this read returned, and it has already been applied.
    if (choice != _choice) return;

    _enabled = wanted;
    await _apply(wanted);
    if (!_stillOn(accountId)) return;
    notifyListeners();
  }

  /// Turns it on or off, stores the answer and tells the platform.
  ///
  /// Stored first and applied second, which is the opposite order from the app
  /// icon and deliberately so: there the platform is the truth and a refusal
  /// must not be recorded, here the *account's choice* is the truth and it has
  /// to survive a device that cannot honour it. Somebody who turns this on, is
  /// told their phone cannot block screenshots, and signs in on a phone that
  /// can should find it on there.
  Future<void> setEnabled(bool on) async {
    final account = _accountId;
    if (account == null) return;
    if (_enabled == on) return;

    _choice += 1;
    _enabled = on;
    notifyListeners();

    await _store.writeScreenShield(account, on);
    if (!_stillOn(account)) return;
    await _apply(on);
    if (!_stillOn(account)) return;
    notifyListeners();
  }

  /// Applies the current choice to the platform, and starts or stops watching.
  Future<void> _apply(bool on) async {
    // The capability decides whether there is anything to watch, so it has to
    // be known before this runs. Normally [load] has already asked — but the
    // switch can be thrown while that read is still in flight, and a capability
    // of "none" at that moment would mean the setting goes on and nothing ever
    // starts listening. Found by a test that turned it on too quickly.
    if (!_asked) {
      _capability = await _shield.capability();
      _asked = true;
    }
    await _shield.setProtected(on);
    if (on && _capability.detectsCapture) {
      _shield.listen(_onCaptureChanged);
      _captured = await _shield.isCaptured();
    } else {
      _shield.stopListening();
      _captured = false;
    }
  }

  void _onCaptureChanged(bool captured) {
    if (_captured == captured) return;
    _captured = captured;
    notifyListeners();
  }

  /// Clears the protection and forgets the account, on the way out.
  ///
  /// The flag is cleared rather than left set. A signed-out phone showing the
  /// welcome screen has nothing to protect, and leaving `FLAG_SECURE` on would
  /// hand the next account a setting it never chose — which is the whole of the
  /// rule this class exists to keep.
  Future<void> signedOut({bool notify = true}) async {
    _accountId = null;
    _enabled = false;
    _captured = false;
    _shield.stopListening();
    await _shield.setProtected(false);
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _shield.stopListening();
    super.dispose();
  }

  bool _stillOn(String account) => _accountId == account;
}
