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

  /// A language somebody picked on the welcome screen, before there was an
  /// account to keep it.
  ///
  /// The sign-in screens start in English, for the reason above. But a person
  /// who chose German there and then created an account was handed an English
  /// app and had to find the setting again. A choice made on this screen is
  /// that person's own, so it becomes the language of the account they create
  /// — and only of an account with no language of its own: somebody signing
  /// back in to an account that already has one gets theirs.
  AppLanguage? _chosenBeforeSignIn;

  AppLanguage get language => _language;
  Locale get locale => _language.locale;
  String? get accountId => _accountId;

  /// Loads the language for an account that has just signed in.
  ///
  /// Resets to English first, so a slow read cannot leave the previous
  /// account's language on screen while this one's is being fetched — which is
  /// exactly the kind of leak between accounts this app has had to fix before.
  Future<void> load(String accountId) async {
    final chosen = _chosenBeforeSignIn;
    _chosenBeforeSignIn = null;
    _accountId = accountId;
    // The choice just made on this screen stays on screen while the account's
    // own is read; anything else resets to English first, so a slow read
    // cannot show the previous account's language.
    _language = chosen ?? AppLanguage.fallback;
    notifyListeners();

    final stored = await _store.readLanguage(accountId);
    final found = AppLanguage.forCode(stored);
    if (found == null) {
      // Nothing stored is a new account. It starts in the language chosen on
      // the welcome screen, if one was, and otherwise in English.
      if (chosen != null) await _store.writeLanguage(accountId, chosen.code);
      return;
    }
    if (found != _language) {
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
    // Before sign-in there is nowhere to put it yet. It is held for the
    // account about to be created on this screen — see [_chosenBeforeSignIn].
    if (account == null) {
      _chosenBeforeSignIn = language;
      return;
    }
    await _store.writeLanguage(account, language.code);
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
    _chosenBeforeSignIn = null;
    if (_language == AppLanguage.fallback) return;
    _language = AppLanguage.fallback;
    if (notify) notifyListeners();
  }
}
