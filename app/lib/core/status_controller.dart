import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'failure.dart';

/// A profile status: a line somebody published about themselves.
///
/// Immutable, and deliberately separate from anything to do with presence. When
/// somebody was last online is an observation the server makes; this is a
/// sentence the user wrote. The screens keep them apart and so does the server
/// — see `server/src/services/status.ts`.
@immutable
class ProfileStatus {
  const ProfileStatus({this.text, this.emoji, this.expiresAt, this.updatedAt});

  /// Reads the shape the API returns. A missing or malformed object reads as
  /// [none] rather than throwing: a profile that cannot be parsed still has a
  /// name and a picture worth showing.
  factory ProfileStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    final text = (json['text'] as String?)?.trim();
    final emoji = (json['emoji'] as String?)?.trim();
    return ProfileStatus(
      text: (text?.isEmpty ?? true) ? null : text,
      emoji: (emoji?.isEmpty ?? true) ? null : emoji,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal(),
    );
  }

  static const ProfileStatus none = ProfileStatus();

  final String? text;
  final String? emoji;

  /// When this stops being shown, or null for "until I change it".
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  /// Whether there is anything to show at all.
  ///
  /// An expired status is not set, on this side as well as on the server's.
  /// Checked against the clock at the moment of asking rather than cached,
  /// because the whole promise of an expiry is that it takes effect on time —
  /// a screen left open across the deadline must stop showing it without
  /// needing a round trip to be told.
  bool get isSet => !isExpired && (text != null || emoji != null);

  bool get isExpired {
    final at = expiresAt;
    return at != null && !at.isAfter(DateTime.now());
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileStatus &&
      other.text == text &&
      other.emoji == emoji &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(text, emoji, expiresAt);
}

/// Holds this account's own profile status, and changes it.
///
/// Two rules shape everything here, and both come from the same place — the
/// status belongs to an account, and this object outlives none of them:
///
/// 1. **It is loaded per account.** [load] takes the id it is loading for and
///    records it. Nothing is ever carried from one account into the next.
/// 2. **A late answer is dropped, not applied.** Every request captures the
///    account it was made for and checks, on completion, that the controller is
///    still on that account. A save that was in flight when somebody switched
///    accounts finishes into nothing — it does not write one person's status
///    onto another person's screen. This is the case a `mounted` check or a
///    `dispose` does not cover, because the object may legitimately still be
///    alive and simply be looking at somebody else.
class StatusController extends ChangeNotifier {
  StatusController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  ProfileStatus _status = ProfileStatus.none;
  bool _saving = false;
  bool _loaded = false;
  Failure? _failure;

  /// The account these values belong to, or null before the first load.
  String? get accountId => _accountId;

  ProfileStatus get status => _status;

  /// Whether a save or a removal is in flight.
  ///
  /// The dialog disables its buttons on this, which is what stops a second
  /// request being sent — and [save] refuses re-entry as well, so a race the
  /// UI does not catch cannot produce two writes either.
  bool get saving => _saving;

  /// Whether the server has answered at least once for this account. The row
  /// shows nothing rather than "no status" until it has.
  bool get loaded => _loaded;

  /// The last failure, as a case. The screen turns it into a sentence.
  Failure? get failure => _failure;

  /// Adopts what a `/v1/accounts/me` read already returned.
  ///
  /// Sign-in and start-up both read the account anyway, and asking a second
  /// time would spend the same rate-limit budget for an answer already in hand.
  void adopt(String accountId, Map<String, dynamic>? json) {
    _accountId = accountId;
    _status = ProfileStatus.fromJson(json);
    _loaded = true;
    _failure = null;
    notifyListeners();
  }

  /// Reads this account's status from the server.
  ///
  /// Resets first. A controller that showed the previous account's line while
  /// the new account's read was in flight would be showing somebody else's
  /// words, and the gap is long enough to see on a slow connection.
  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _status = ProfileStatus.none;
      _loaded = false;
      _failure = null;
      notifyListeners();
    }

    try {
      final me = await _api.me();
      if (!_stillOn(accountId)) return;
      _status = ProfileStatus.fromJson(me['status'] as Map<String, dynamic>?);
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

  /// Saves a status. Returns false and leaves [failure] set if it did not take.
  ///
  /// The stored value is updated **only** from what the server returns, and
  /// only after it has returned. There is no optimistic write: a status that
  /// appeared on the row and then had to be taken back would be exactly the
  /// "looks saved but isn't" this is meant to avoid.
  Future<bool> save({String? text, String? emoji, DateTime? expiresAt}) async {
    if (_saving) return false;
    final account = _accountId;
    if (account == null) {
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return false;
    }

    _saving = true;
    _failure = null;
    notifyListeners();

    try {
      final answer = await _api.setStatus(text: text, emoji: emoji, expiresAt: expiresAt);
      if (!_stillOn(account)) return false;
      _status = ProfileStatus.fromJson(answer['status'] as Map<String, dynamic>?);
      _loaded = true;
      return true;
    } on Object {
      // One case for every way this fails, and deliberately not the server's
      // own words: `expiry_in_past` is accurate and means nothing to the person
      // reading it. What they need to know is that it did not save and that
      // what they typed is still there, which is what this case says.
      if (!_stillOn(account)) return false;
      _failure = const Failure(FailureKind.statusNotSaved);
      return false;
    } finally {
      // Guarded for the same reason as everything else: an account switch
      // during the request means this controller is somebody else's now, and
      // clearing *their* busy flag would unblock a save they never started.
      if (_stillOn(account)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  /// Removes the status. Same rules as [save].
  Future<bool> remove() async {
    if (_saving) return false;
    final account = _accountId;
    if (account == null) return false;

    _saving = true;
    _failure = null;
    notifyListeners();

    try {
      await _api.clearStatus();
      if (!_stillOn(account)) return false;
      _status = ProfileStatus.none;
      _loaded = true;
      return true;
    } on Object {
      if (!_stillOn(account)) return false;
      _failure = const Failure(FailureKind.statusNotSaved);
      return false;
    } finally {
      if (_stillOn(account)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  /// Drops the error so a reopened dialog does not start with the last one.
  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  /// Forgets everything, on the way out of an account.
  void signedOut({bool notify = true}) {
    _accountId = null;
    _status = ProfileStatus.none;
    _loaded = false;
    _saving = false;
    _failure = null;
    if (notify) notifyListeners();
  }

  /// Whether this controller is still looking at the account a request was
  /// made for.
  bool _stillOn(String account) => _accountId == account;
}
