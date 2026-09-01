import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// A device signed in to this account.
@immutable
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.current,
    required this.lastSeenAt,
    required this.activeSessions,
  });

  factory LinkedDevice.fromJson(Map<String, dynamic> json) => LinkedDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unnamed device',
        platform: json['platform'] as String? ?? 'unknown',
        current: json['current'] as bool? ?? false,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '')?.toLocal(),
        activeSessions: json['activeSessions'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String platform;

  /// Whether this row is the device reading it.
  final bool current;

  final DateTime? lastSeenAt;

  /// How many sessions on this device are still valid. Zero means it holds the
  /// keys but cannot reach the server until someone signs in on it again.
  final int activeSessions;
}

/// Someone this account has blocked.
@immutable
class BlockedUser {
  const BlockedUser({required this.accountId, required this.username, this.displayName});

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        accountId: json['accountId'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
      );

  final String accountId;
  final String username;
  final String? displayName;

  String get label => displayName ?? username;
}

/// The account settings that are security, not messaging: the second factor,
/// who may see when you were last online, and who has been blocked.
///
/// It exists because the Privacy screen used to state all three from constants
/// in the widget tree — "Two-Factor Authentication: On" over an account that
/// had none. A screen about security is the last place to guess.
class SecurityController extends ChangeNotifier {
  SecurityController(this._api);

  final PrivioApiClient _api;

  bool? _twoFactorEnabled;
  bool _duressCodeSet = false;
  String _lastSeen = 'everyone';
  List<BlockedUser>? _blocked;
  bool _busy = false;
  String? _error;

  /// Null until the server has answered. The screen shows nothing rather than
  /// claiming a state it has not been told.
  bool? get twoFactorEnabled => _twoFactorEnabled;

  bool get duressCodeSet => _duressCodeSet;

  /// One of `everyone`, `contacts`, `nobody`, matching what the server stores.
  String get lastSeen => _lastSeen;

  /// The whole privacy object from the last read, so a screen that needs the
  /// messaging switches as well does not have to ask for the account twice.
  /// Reading your own account is cheap but not free: it is rate limited, and a
  /// settings screen that spends two of that budget on one open is wasteful.
  Map<String, dynamic>? get privacy => _privacy;
  Map<String, dynamic>? _privacy;

  List<BlockedUser>? get blocked => _blocked;

  /// Null until the list has been read. The devices screen showed four
  /// invented ones for as long as it existed, on the screen whose whole job is
  /// answering "is anyone else signed in to my account".
  List<LinkedDevice>? get devices => _devices;
  List<LinkedDevice>? _devices;

  bool get busy => _busy;

  String? get error => _error;

  /// The secret behind the QR code, held only while setup is in progress.
  ///
  /// Cleared the moment the factor is enabled or the screen is left: it is the
  /// factor, and keeping it in memory for longer than the seconds it takes to
  /// scan is keeping the thing the second factor is supposed to be.
  String? get setUpSecret => _setUpSecret;
  String? get setUpUrl => _setUpUrl;
  String? _setUpSecret;
  String? _setUpUrl;

  static const List<String> lastSeenChoices = ['everyone', 'contacts', 'nobody'];

  static String labelForLastSeen(String value) => switch (value) {
        'contacts' => 'My contacts',
        'nobody' => 'Nobody',
        _ => 'Everyone',
      };

  /// Reads what the server says about this account. Never throws: this runs
  /// when a settings screen opens, and a failed read leaves the last known
  /// state on screen with the error under it.
  Future<void> load() async {
    try {
      final me = await _api.me();
      _twoFactorEnabled = me['twoFactorEnabled'] as bool? ?? false;
      _duressCodeSet = me['duressCodeSet'] as bool? ?? false;
      final privacy = me['privacy'] as Map<String, dynamic>? ?? const {};
      _privacy = privacy;
      _lastSeen = privacy['lastSeen'] as String? ?? 'everyone';
      _error = null;
      // The blocked count belongs to the same screen, and a row that says
      // nothing until you open it is only marginally better than one that
      // said 3 whatever the truth was.
      await loadBlocks();
    } on ApiException catch (failure) {
      _error = failure.message;
    } on Object {
      _error = 'Could not reach Privio.';
    }
    notifyListeners();
  }

  Future<void> setLastSeen(String value) async {
    if (!lastSeenChoices.contains(value)) return;
    final previous = _lastSeen;
    _lastSeen = value;
    notifyListeners();
    try {
      await _api.updatePrivacy({'lastSeen': value});
    } on Object {
      // Put it back rather than show a setting the server did not accept.
      _lastSeen = previous;
      _error = 'Could not save that. Check your connection.';
      notifyListeners();
    }
  }

  /// Sets or clears the duress code.
  ///
  /// Pass null for [duressCode] to remove it. Both need the password: this is the
  /// setting that destroys the account, and an unlocked phone is not authority
  /// to change it in either direction.
  Future<bool> setDuressCode({
    required String currentPassword,
    required String? duressCode,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _api.setDuressCode(
        currentPassword: currentPassword,
        duressCode: duressCode,
      );
      _duressCodeSet = body['duressCodeSet'] as bool? ?? duressCode != null;
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Step one: ask the server for a secret to show as a QR code.
  Future<bool> beginTotpSetup() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _api.setUpTotp();
      _setUpSecret = body['secret'] as String?;
      _setUpUrl = body['otpauthUrl'] as String?;
      return _setUpSecret != null;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Step two: prove the authenticator produces the right code, which is what
  /// turns the factor on. Getting this wrong is why the step exists — a factor
  /// enabled without proof locks out the person who set it up.
  Future<bool> confirmTotp(String code) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _api.enableTotp(code.trim());
      _twoFactorEnabled = true;
      _forgetSetup();
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> disableTotp(String currentPassword) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _api.disableTotp(currentPassword);
      _twoFactorEnabled = false;
      _forgetSetup();
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on Object {
      _error = 'Could not reach Privio.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Drops a setup that was started and not finished. The server keeps the
  /// secret it issued until the next setup replaces it, and it is not in force
  /// until a code has been confirmed, so leaving mid-way is safe.
  void cancelTotpSetup() {
    if (_setUpSecret == null && _error == null) return;
    _forgetSetup();
    _error = null;
    notifyListeners();
  }

  void _forgetSetup() {
    _setUpSecret = null;
    _setUpUrl = null;
  }

  Future<void> loadDevices() async {
    try {
      final body = await _api.devices();
      _devices = [
        for (final entry in body['devices'] as List<dynamic>? ?? const [])
          LinkedDevice.fromJson(entry as Map<String, dynamic>),
      ];
      _error = null;
    } on ApiException catch (failure) {
      _error = failure.message;
    } on Object {
      _error = 'Could not reach Privio.';
    }
    notifyListeners();
  }

  /// Signs a device out for good: its sessions are revoked and whatever was
  /// still queued for it is deleted. It keeps the copy of the history it has
  /// already decrypted — nothing here can reach that.
  Future<bool> revokeDevice(String deviceId) async {
    try {
      await _api.revokeDevice(deviceId);
    } on ApiException catch (failure) {
      _error = _explain(failure);
      notifyListeners();
      return false;
    } on Object {
      _error = 'Could not reach Privio.';
      notifyListeners();
      return false;
    }
    _devices = [...?_devices?.where((device) => device.id != deviceId)];
    notifyListeners();
    return true;
  }

  Future<void> loadBlocks() async {
    try {
      final body = await _api.blocks();
      _blocked = [
        for (final entry in body['blocked'] as List<dynamic>? ?? const [])
          BlockedUser.fromJson(entry as Map<String, dynamic>),
      ];
      _error = null;
    } on ApiException catch (failure) {
      _error = failure.message;
    } on Object {
      _error = 'Could not reach Privio.';
    }
    notifyListeners();
  }

  Future<void> unblock(String accountId) async {
    final before = _blocked;
    _blocked = [...?before?.where((user) => user.accountId != accountId)];
    notifyListeners();
    try {
      await _api.unblock(accountId);
    } on Object {
      _blocked = before;
      _error = 'Could not lift that block.';
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  static String _explain(ApiException failure) => switch (failure.code) {
        'invalid_totp' => 'That code is not right. Check the clock on your phone and try again.',
        'totp_already_enabled' => 'Two-factor is already on for this account.',
        'totp_not_set_up' => 'Start the setup again — the secret is gone.',
        'invalid_credentials' => 'That password is not right.',
        'duress_code_matches_password' =>
          'The duress code has to be different from your password, or an ordinary '
              'sign-in would destroy the account.',
        'rate_limited' => 'Too many attempts. Wait a few minutes.',
        'device_not_found' => 'That device is already signed out.',
        _ => failure.message,
      };
}
