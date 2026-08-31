import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'edition.dart';
import 'license_key.dart';
import 'secure_store.dart';

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
    this.maxDevices,
    this.devices,
  });

  factory LicenseState.fromJson(Map<String, dynamic> json, {bool? fallback}) {
    final at = json['redeemedAt'] as String?;
    return LicenseState(
      licensed: json['licensed'] as bool? ?? false,
      enforced: json['required'] as bool? ?? fallback ?? false,
      source: json['source'] as String?,
      redeemedAt: at == null ? null : DateTime.tryParse(at),
      maxDevices: json['maxDevices'] as int?,
      devices: json['devices'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'licensed': licensed,
        'required': enforced,
        if (source != null) 'source': source,
        if (redeemedAt != null) 'redeemedAt': redeemedAt!.toIso8601String(),
        if (maxDevices != null) 'maxDevices': maxDevices,
        if (devices != null) 'devices': devices,
      };

  final bool licensed;

  /// Whether this server requires a license at all. Named for what it does,
  /// rather than after the `required` field on the wire, which would sit badly
  /// next to Dart's own `required`.
  final bool enforced;

  /// How it was paid for: `key`, `apple` or `google`.
  final String? source;

  final DateTime? redeemedAt;

  /// Active devices this license covers, and how many are in use.
  final int? maxDevices;
  final int? devices;

  /// The one state that needs the user to do something.
  bool get needsActivation => enforced && !licensed;

  /// True when adding another device would be refused. Null-safe on purpose:
  /// an older server that does not report the numbers must not make the app
  /// claim a limit it cannot see.
  bool get atDeviceLimit {
    final limit = maxDevices;
    final used = devices;
    if (limit == null || used == null) return false;
    return used >= limit;
  }
}

/// Activation, and the state the activation screen renders.
///
/// Nothing here enforces anything. Privio Libre is open source and can be
/// built with this screen deleted, so the client only ever *reports* what the
/// server already decided — the gate is a preHandler on the server, and that is
/// the only place it can honestly live. The cache below is a cache for the same
/// reason: it exists so the app can say something true while offline, not so it
/// can decide anything.
class LicenseController extends ChangeNotifier {
  LicenseController(this._api, {SecureStore? store}) : _store = store;

  final PrivioApiClient _api;
  final SecureStore? _store;

  LicenseState? _state;
  String? _error;
  bool _busy = false;

  /// Null until the first answer — from the server, or from the cache the last
  /// answer was written to. Rendering "unlicensed" before either would accuse a
  /// paying user of not having paid.
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

  /// Reads back the last known status, so the first frame after a cold start
  /// is not a question mark on a device with no signal.
  Future<void> restore() async {
    final cached = await _store?.readLicenseCache();
    if (cached == null || _state != null) return;
    try {
      _state = LicenseState.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      notifyListeners();
    } on FormatException {
      // A cache that will not parse is a cache worth losing.
      await _store?.writeLicenseCache(null);
    }
  }

  /// Re-reads the license. Never throws: this runs unprompted after sign-in,
  /// and a licensing hiccup must not be what stops someone reading their
  /// messages.
  Future<void> refresh() async {
    try {
      final body = await _api.licenseStatus();
      await _adopt(LicenseState.fromJson(body));
      _error = null;
    } on Object {
      // Leave the last known state in place. Offline is not unlicensed.
    }
    notifyListeners();
  }

  /// Keeps a key entered before there was an account to bind it to.
  ///
  /// Returns false, with [error] set, if it is not even the right shape —
  /// there is no point carrying a typo all the way to the sign-up screen.
  Future<bool> hold(String key) async {
    if (!isWellFormedLicenseKey(key)) {
      _error = 'That key is not complete. It looks like $licenseKeyFormat.';
      notifyListeners();
      return false;
    }
    await _store?.writePendingLicenseKey(formatLicenseKey(key));
    _error = null;
    notifyListeners();
    return true;
  }

  Future<bool> get hasPendingKey async => (await _store?.readPendingLicenseKey()) != null;

  /// Redeems the key that was entered before the account existed.
  ///
  /// Runs after the first successful sign-in. A failure here is deliberately
  /// quiet: the account is signed in and usable, the settings screen shows what
  /// went wrong, and the key is kept so it can be tried again rather than lost.
  Future<bool> redeemPending() async {
    final pending = await _store?.readPendingLicenseKey();
    if (pending == null) return false;
    return redeem(pending);
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
      await _adopt(LicenseState.fromJson(body, fallback: _state?.enforced ?? true));
      if (_state?.licensed ?? false) {
        // Spent. Keeping a used bearer secret on the device buys nothing.
        await _store?.writePendingLicenseKey(null);
        return true;
      }
      return false;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      // A key that will never work again should not sit there being retried.
      if (failure.code == 'license_already_redeemed' || failure.code == 'license_revoked') {
        await _store?.writePendingLicenseKey(null);
      }
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection and try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _adopt(LicenseState state) async {
    _state = state;
    await _store?.writeLicenseCache(jsonEncode(state.toJson()));
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
