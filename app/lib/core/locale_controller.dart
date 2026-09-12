import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'secure_store.dart';

/// The five languages Privio speaks, with the names they call themselves.
///
/// Always the endonym — "Deutsch", not "German". Somebody looking for their own
/// language is looking for the word they would use for it, and a list that
/// names them all in English is a list only an English speaker can read.
enum AppLanguage {
  english('en', 'English'),
  german('de', 'Deutsch'),
  spanish('es', 'Español'),
  french('fr', 'Français'),
  italian('it', 'Italiano');

  const AppLanguage(this.code, this.endonym);

  /// The language tag, which is also the ARB file's suffix.
  final String code;

  /// What speakers of it call it.
  final String endonym;

  Locale get locale => Locale(code);

  static AppLanguage? forCode(String? code) {
    if (code == null) return null;
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// The one the app falls back to, everywhere: before anybody signs in, for a
  /// new account, and for any string a translation has not caught up with.
  static const AppLanguage fallback = AppLanguage.english;
}

/// Which language the interface is in, and whose choice it is.
///
/// **Per account, and stored under the account's own id.** Two people sharing a
/// phone do not share a language, and signing in to a second account must not
/// inherit the first one's choice — the same rule as everything else that is
/// per account here. A new account starts at English rather than at whatever
/// the last person set.
///
/// **Before anybody signs in there is no account to have a preference**, so the
/// sign-in and onboarding screens are English. Reading the device's own locale
/// there was tempting and is wrong for this app: it would mean a phone set to
/// German shows a German sign-in screen to somebody whose Privio account is in
/// French, and the language would change under them the moment they signed in.
class LocaleController extends ChangeNotifier {
  LocaleController(this._store);

  final SecureStore _store;

  AppLanguage _language = AppLanguage.fallback;

  /// Whose preference is loaded. Null before sign-in, which is English.
  String? _accountId;

  AppLanguage get language => _language;
  Locale get locale => _language.locale;
  String? get accountId => _accountId;

  /// Loads the language for an account that has just signed in.
  ///
  /// Resets to English first, so a slow read cannot leave the previous
  /// account's language on screen while this one's is being fetched — which is
  /// exactly the kind of leak between accounts this app has had to fix before.
  Future<void> load(String accountId) async {
    _accountId = accountId;
    _language = AppLanguage.fallback;
    notifyListeners();

    final stored = await _store.readLanguage(accountId);
    final found = AppLanguage.forCode(stored);
    // Nothing stored is not an error: it is a new account, and a new account
    // starts in English.
    if (found != null && found != _language) {
      _language = found;
      notifyListeners();
    }
  }

  /// Sets the language for the signed-in account, and changes the interface now.
  ///
  /// [notifyListeners] is what makes it immediate: the `MaterialApp` is built
  /// inside a listener on this controller, so every screen already on the
  /// navigator stack rebuilds in the new language. Nothing is restarted and
  /// nobody signs in again.
  Future<void> choose(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();

    final account = _accountId;
    // Before sign-in there is nowhere to put it, and the choice lasts as long
    // as the screen does. That is the honest behaviour: a preference with no
    // account to belong to cannot survive one.
    if (account != null) await _store.writeLanguage(account, language.code);
  }

  /// Back to English, for a signed-out app.
  ///
  /// Nothing is deleted here because there is nothing left to delete: signing
  /// out, ending an account and the duress wipe all clear the whole secure
  /// store, and the stored language goes with it. Signing back in is a new
  /// account as far as this is concerned, and starts in English.
  ///
  /// [notify] is false for exactly one caller: the duress wipe, which must not
  /// move anything on screen while somebody is watching it. A sign-in screen
  /// that changed language at the moment a wrong PIN was typed would announce
  /// the wipe it just did. The stage change that comes later rebuilds the app
  /// anyway — [AppState] and this are listened to together.
  void signedOut({bool notify = true}) {
    _accountId = null;
    if (_language == AppLanguage.fallback) return;
    _language = AppLanguage.fallback;
    if (notify) notifyListeners();
  }
}
