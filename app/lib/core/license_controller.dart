import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// What the server says about this account's license.
@immutable
class LicenseStatus {
  const LicenseStatus({
    required this.licensed,
    required this.requiredByServer,
    this.source,
    this.redeemedAt,
  });

  /// This account holds an active license.
  final bool licensed;

  /// Whether this server sells access at all. False on a self-hosted
  /// deployment, where a licence for infrastructure you already run would mean
  /// nothing — and the app then has no business asking for a key.
  final bool requiredByServer;

  /// 'key' for a website purchase, 'apple' or 'google' for a store purchase.
  final String? source;
  final DateTime? redeemedAt;

  /// Nothing to do: either the server does not ask, or this account has paid.
  bool get settled => !requiredByServer || licensed;

  factory LicenseStatus.fromJson(Map<String, dynamic> json) {
    final redeemedAt = json['redeemedAt'];
    return LicenseStatus(
      licensed: json['licensed'] == true,
      requiredByServer: json['required'] == true,
      source: json['source'] as String?,
      redeemedAt: redeemedAt is String ? DateTime.tryParse(redeemedAt) : null,
    );
  }
}

/// Formats a key the way it is printed, without changing what is sent.
///
/// The server folds case, separators and the Crockford aliases itself, so this
/// is only so that what the user sees while typing matches what they are
/// copying from.
String formatLicenseKey(String input) {
  final body = input
      .toUpperCase()
      .replaceAll(RegExp('[^0-9A-Z]'), '')
      .replaceFirst(RegExp('^PRIVIO'), '');

  final groups = <String>[];
  for (var i = 0; i < body.length && groups.length < 4; i += 4) {
    groups.add(body.substring(i, i + 4 > body.length ? body.length : i + 4));
  }

  if (groups.isEmpty) return input.isEmpty ? '' : 'PRIVIO-';
  return 'PRIVIO-${groups.join('-')}';
}

/// Drives the license screen and the settings row.
///
/// Deliberately thin: the client never decides whether anyone is licensed. It
/// asks, it shows the answer, and it turns error codes into sentences.
class LicenseController extends ChangeNotifier {
  LicenseController(this._api);

  final PrivioApiClient _api;

  LicenseStatus? _status;
  bool _busy = false;
  String? _error;

  LicenseStatus? get status => _status;
  bool get busy => _busy;
  String? get error => _error;

  /// True only once the server has actually said so.
  bool get licensed => _status?.licensed ?? false;

  /// Whether to offer the license screen at all.
  bool get shouldPrompt => _status != null && !_status!.settled;

  Future<void> refresh() async {
    try {
      _status = LicenseStatus.fromJson(await _api.licenseStatus());
      _error = null;
    } on ApiException catch (failure) {
      // An older server without the endpoint is not an error worth showing:
      // it simply does not require a license.
      if (failure.statusCode == 404) {
        _status = const LicenseStatus(licensed: false, requiredByServer: false);
        _error = null;
      } else {
        _error = explain(failure);
      }
    } on Object {
      _error = 'Could not reach Privio. Check your connection.';
    }
    notifyListeners();
  }

  /// Redeems a key. Returns whether the account came out licensed.
  Future<bool> redeem(String licenseKey) async {
    final key = licenseKey.trim();
    if (key.isEmpty) {
      _error = 'Enter your license key.';
      notifyListeners();
      return false;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.redeemLicense(key);
      _status = LicenseStatus(
        licensed: result['licensed'] == true,
        requiredByServer: _status?.requiredByServer ?? true,
        source: result['source'] as String?,
        redeemedAt: DateTime.tryParse(result['redeemedAt'] as String? ?? ''),
      );
      return licensed;
    } on ApiException catch (failure) {
      _error = explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection.';
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

  /// Server error codes turned into something a person can act on.
  static String explain(ApiException failure) => switch (failure.code) {
        'license_not_found' =>
          'That key does not exist. Check it for typos — the groups matter, '
              'but upper and lower case do not.',
        'license_already_redeemed' =>
          'That key has already been used on another account. A key can only '
              'be activated once.',
        'license_revoked' =>
          'That key was revoked, usually because the payment was reversed. '
              'Contact support with your order reference.',
        'account_already_licensed' =>
          'This account already has an active license. Keep the new key — it '
              'has not been used.',
        'rate_limited' => 'Too many attempts. Wait a few minutes and try again.',
        'invalid_request' => 'That does not look like a Privio license key.',
        _ => failure.message,
      };
}
