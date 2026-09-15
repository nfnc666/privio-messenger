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

  /// Loads the accent for an account.
  ///
  /// Resets to green first, so a slow read cannot leave the previous account's
  /// colour on screen while this one's is being fetched.
  ///
  /// On a cold start this is **awaited before the app leaves the splash**, which
  /// is what stops a stored pink app showing a frame of green on every launch.
  /// The reset above is therefore invisible there; it earns its keep on an
  /// account switch, where the app is already drawn.
  Future<void> load(String accountId) async {
    _accountId = accountId;
    if (_accent != AppAccent.fallback) {
      _accent = AppAccent.fallback;
      notifyListeners();
    }

    final stored = await _store.readAccent(accountId);
    final found = AppAccent.forCode(stored);
    // Nothing stored is not an error: it is a new account, and a new account
    // is green.
    if (found != null && found != _accent) {
      _accent = found;
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
