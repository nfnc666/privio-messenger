import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'display_name.dart';
import 'failure.dart';

/// This account's own two names.
///
/// They are different kinds of thing and this holds them apart:
///
///  * [username] is the address. It was chosen once, it is what an invite link
///    carries, and nothing in the app can change it — there is no method here
///    that tries, and the server would refuse one if there were.
///  * [displayName] is what the person calls themselves. It may be anything,
///    it may be nothing, and it may change as often as they like.
///
/// Per account, like every other controller here: [load] takes the id it is
/// loading for and every answer is dropped if the account changed while the
/// request was in flight. A name left over from the previous account would be
/// the wrong name on somebody else's profile screen.
class ProfileNameController extends ChangeNotifier {
  ProfileNameController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  String? _username;
  String? _displayName;
  bool _loaded = false;
  bool _saving = false;
  Failure? _failure;

  String? get accountId => _accountId;

  /// The fixed `@name`, without the `@`.
  String? get username => _username;

  /// The chosen name, or null when there is none.
  String? get displayName => _displayName;

  /// What to draw: the chosen name where there is one, the username otherwise.
  ///
  /// The fallback lives here rather than in each screen, so that "no display
  /// name" cannot be drawn as an empty row in one place and as a username in
  /// another.
  String get label => _displayName?.isNotEmpty == true ? _displayName! : (_username ?? '');

  bool get loaded => _loaded;
  bool get saving => _saving;
  Failure? get failure => _failure;

  bool _stillOn(String accountId) => _accountId == accountId;

  /// Reads both names for [accountId].
  ///
  /// Resets first when the account changed, for the same reason the status
  /// controller does: the previous account's name on screen while this one
  /// loads is somebody else's name on screen.
  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _username = null;
      _displayName = null;
      _loaded = false;
      _failure = null;
      notifyListeners();
    }

    try {
      final me = await _api.me();
      if (!_stillOn(accountId)) return;
      _username = me['username'] as String?;
      _displayName = me['displayName'] as String?;
      _loaded = true;
      _failure = null;
    } on ApiException catch (failure) {
      if (!_stillOn(accountId)) return;
      _failure = Failure.server(failure.message);
    } on Object {
      if (!_stillOn(accountId)) return;
      _failure = const Failure(FailureKind.unreachable);
    }
    notifyListeners();
  }

  /// Saves a display name, or clears it when [value] cleans to nothing.
  ///
  /// What is held is only ever what the server returned, and only after it has
  /// returned: there is no optimistic write, so a name that did not save is
  /// never on screen as though it had. Returns false with [failure] set when
  /// it did not take.
  Future<bool> save(String value) async {
    if (_saving) return false;
    final account = _accountId;
    if (account == null) {
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return false;
    }

    // Refused here rather than sent and bounced: the rule is the same on both
    // sides, and the person is still looking at the field.
    if (displayNameProblem(value) == DisplayNameProblem.tooLong) {
      _failure = const Failure(FailureKind.displayNameTooLong);
      notifyListeners();
      return false;
    }

    _saving = true;
    _failure = null;
    notifyListeners();

    try {
      final answer = await _api.setDisplayName(cleanDisplayName(value));
      if (!_stillOn(account)) return false;
      _displayName = answer['displayName'] as String?;
      _username = (answer['username'] as String?) ?? _username;
      _loaded = true;
      return true;
    } on Object {
      if (!_stillOn(account)) return false;
      _failure = const Failure(FailureKind.displayNameNotSaved);
      return false;
    } finally {
      if (_stillOn(account)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  /// Forgets everything on sign-out. The next account loads its own.
  void clear() {
    _accountId = null;
    _username = null;
    _displayName = null;
    _loaded = false;
    _failure = null;
    notifyListeners();
  }
}
