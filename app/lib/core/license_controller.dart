import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'edition.dart';
import 'license_key.dart';

/// What the server says about this account's license.
///
/// [enforced] comes from the server, not from the build: a self-hosted
/// deployment answers false and no key is ever asked for. A license for
/// infrastructure you already own would mean nothing.
@immutable
class LicenseState {
  const LicenseState({
    required this.licensed,
    required this.enforced,
    this.source,
    this.redeemedAt,
  });

  factory LicenseState.fromJson(Map<String, dynamic> json, {bool? fallback}) {
    final at = json['redeemedAt'] as String?;
    return LicenseState(
      licensed: json['licensed'] as bool? ?? false,
      enforced: json['required'] as bool? ?? fallback ?? false,
      source: json['source'] as String?,
      redeemedAt: at == null ? null : DateTime.tryParse(at),
    );
  }

  final bool licensed;

  /// Whether this server requires a license at all. Named for what it does,
  /// rather than after the `required` field on the wire, which would sit badly
  /// next to Dart's own `required`.
  final bool enforced;

  /// How it was paid for: `key`, `apple` or `google`.
  final String? source;

  final DateTime? redeemedAt;

  /// The one state that needs the user to do something.
  bool get needsActivation => enforced && !licensed;
}

/// Activation, and the state the activation screen renders.
///
/// Nothing here enforces anything. Privio Libre is open source and can be
/// built with this screen deleted, so the client only ever *reports* what the
/// server already decided — the gate is a preHandler on the server, and that is
/// the only place it can honestly live.
class LicenseController extends ChangeNotifier {
  LicenseController(this._api);

  final PrivioApiClient _api;

  LicenseState? _state;
  String? _error;
  bool _busy = false;

  /// Null until the first successful fetch. Rendering "unlicensed" before the
  /// server has answered would accuse a paying user of not having paid.
  LicenseState? get state => _state;

  String? get error => _error;

  bool get busy => _busy;

  /// Whether to put a license entry in front of the user at all.
  ///
  /// Before the first answer, fall back to what this build was made for: the
  /// store editions are paid for in the store and have nothing to activate.
  bool get isOffered {
    final state = _state;
    if (state == null) return PrivioEdition.current.usesLicenseKey;
    return state.enforced || state.licensed;
  }

  /// True once the server has said this account has to activate something.
  bool get needsActivation => _state?.needsActivation ?? false;

  /// Re-reads the license. Never throws: this runs unprompted after sign-in,
  /// and a licensing hiccup must not be what stops someone reading their
  /// messages.
  Future<void> refresh() async {
    try {
      final body = await _api.licenseStatus();
      _state = LicenseState.fromJson(body);
      _error = null;
    } on Object {
      // Leave the last known state in place. Offline is not unlicensed.
    }
    notifyListeners();
  }

  /// Redeems a key. Returns true only when the account came back licensed.
  Future<bool> redeem(String key) async {
    if (!isWellFormedLicenseKey(key)) {
      _error = 'That key is not complete. It looks like $licenseKeyFormat.';
      notifyListeners();
      return false;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      // The server normalises too; sending the canonical form keeps what is
      // logged on the way (nothing, deliberately) identical to what is stored.
      final body = await _api.redeemLicense(formatLicenseKey(key));
      _state = LicenseState.fromJson(body, fallback: _state?.enforced ?? true);
      return _state?.licensed ?? false;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection and try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Server error codes, said in words someone can act on.
  ///
  /// `license_already_redeemed` is the one that matters: a key belongs to one
  /// account for good, so the honest answer is that it is gone, not that they
  /// should try again.
  static String _explain(ApiException failure) => switch (failure.code) {
        'license_not_found' => 'No license matches that key. Check it and try again.',
        'license_already_redeemed' =>
          'That key has already been used by another account. A key can only be redeemed once.',
        'license_revoked' => 'That license was revoked. Contact support if you paid for it.',
        'account_already_licensed' =>
          'This account already has a license, so the key you entered has not been used.',
        'rate_limited' => 'Too many attempts. Wait a few minutes and try again.',
        'invalid_request' => 'That does not look like a Privio license key.',
        _ => failure.message,
      };
}
