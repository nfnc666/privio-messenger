import 'package:flutter/foundation.dart';

import '../theme/accent.dart';
import 'secure_store.dart';

/// Which accent the interface is drawn in, and whose choice it is.
///
/// **Per account, under the account's own id** — the same rule as the language.
/// Two people sharing a phone do not share a colour, a second account must not
/// inherit the first one's, and a new account starts at Privio green rather
/// than at whatever the last person set.
///
/// **The choice is this device's own.** It changes nothing anybody else sees:
/// there is no field for it on the wire, the server is never told, and a
/// message sent from a pink app arrives in whatever colour the reader chose.
///
/// Before sign-in there is no account to have a preference, so the welcome and
/// sign-in screens are brand green.
class AccentController extends ChangeNotifier {
  AccentController(this._store);

  final SecureStore _store;

  AppAccent _accent = AppAccent.fallback;

  /// Whose preference is loaded. Null before sign-in.
  String? _accountId;

  AppAccent get accent => _accent;
  String? get accountId => _accountId;

  /// Reads the stored accent before the first frame is drawn.
  ///
  /// Called from `main()` and awaited there, ahead of `runApp`. Everything the
  /// splash paints — the mark, the rain behind it, the progress bar — is the
  /// accent, so reading it *after* the app is on screen means a green frame on
  /// every launch of an app somebody set to something else. `initialise()` also
  /// loads it, but that runs once the splash is already visible, which is one
  /// frame too late.
  ///
  /// Two local reads and no network. It is capped by its caller rather than
  /// here: a keystore that does not answer must not hold the app on a black
  /// screen, and green is a correct answer for an app whose preference could
  /// not be read.
  ///
  /// Signed out there is nothing to read and nothing to wait for — an accent
  /// belongs to an account, and a device with none is green.
  Future<void> preload() async {
    final account = await _store.readAccountId();
    if (account == null) return;
    await load(account);
  }

  /// Loads the accent for an account.
  ///
  /// Resets to green first **when the colour on screen belongs to somebody
  /// else**, so a slow read cannot leave the previous account's choice up while
  /// this one's is being fetched. That is the account-switch case, and the only
  /// one it is right for: doing it unconditionally would make `initialise()`
  /// flash green over the colour [preload] had already put there, which is the
  /// flash this whole path exists to prevent.
  Future<void> load(String accountId) async {
    final somebodyElse = _accountId != null && _accountId != accountId;
    _accountId = accountId;
    if (somebodyElse && _accent != AppAccent.fallback) {
      _accent = AppAccent.fallback;
      notifyListeners();
    }

    final stored = await _store.readAccent(accountId);
    final found = AppAccent.forCode(stored);
    // Nothing stored is not an error: it is a new account, and a new account
    // is green. Reaching that state from another account's colour is the reset
    // above; reaching it from green is already done.
    final next = found ?? AppAccent.fallback;
    if (next != _accent) {
      _accent = next;
      notifyListeners();
    }
  }

  /// Sets the accent for the signed-in account, and repaints the app now.
  ///
  /// Immediate for the same reason the language is: the `MaterialApp` is built
  /// inside a listener on this controller, so the theme is rebuilt from the new
  /// seed and every screen already on the navigator stack redraws. Nothing is
  /// restarted and nobody signs in again.
  Future<void> choose(AppAccent accent) async {
    if (_accent == accent) return;
    _accent = accent;
    notifyListeners();

    final account = _accountId;
    // Before sign-in there is nowhere to put it, and the choice lasts as long
    // as the screen does — a preference with no account to belong to cannot
    // survive one.
    if (account != null) await _store.writeAccent(account, accent.code);
  }

  /// Back to Privio green.
  Future<void> reset() => choose(AppAccent.fallback);

  /// Back to green for a signed-out app.
  ///
  /// Nothing is deleted here because there is nothing left to delete: signing
  /// out, ending an account and the duress wipe all clear the whole secure
  /// store, and the stored accent goes with it.
  ///
  /// [notify] is false for exactly one caller: the duress wipe, which must not
  /// move anything on screen while somebody is watching. An app that changed
  /// colour the moment a wrong PIN was typed would announce the wipe it just
  /// did.
  void signedOut({bool notify = true}) {
    _accountId = null;
    if (_accent == AppAccent.fallback) return;
    _accent = AppAccent.fallback;
    if (notify) notifyListeners();
  }
}
