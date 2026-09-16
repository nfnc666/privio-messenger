import 'package:flutter/foundation.dart';

import '../data/security_log.dart';
import '../models/security_event.dart';

/// The security activity list, per account.
///
/// Per account and guarded the same way every other controller here is: the
/// log is read asynchronously, and an answer that arrives after a switch is
/// dropped rather than shown to whoever is signed in by then. Account
/// separation is not a property of the screen; it is a property of this class
/// and of the sealed payload underneath it.
///
/// Writing is deliberately fire-and-forget from the caller's point of view.
/// Recording that a device was linked must never be able to fail the linking,
/// and a screen that waits on a keystore write before it can say "done" is a
/// screen that hangs on a locked phone.
class SecurityEventController extends ChangeNotifier {
  SecurityEventController(this._log);

  final SecurityLog _log;

  String? _accountId;
  List<SecurityEvent> _events = const [];
  bool _loaded = false;

  /// Newest first. Empty until [load] has answered, which is not the same as
  /// "nothing happened" — [loaded] says which.
  List<SecurityEvent> get events => _events;

  bool get loaded => _loaded;

  /// Whose list this is, or null when nobody is signed in.
  String? get accountId => _accountId;

  /// How many of the events shown are the kind worth noticing.
  int get warnings => _events.where((event) => event.isWarning).length;

  Future<void> load(String accountId) async {
    _accountId = accountId;
    _loaded = false;
    notifyListeners();

    final events = await _log.load(accountId: accountId);
    if (!_stillOn(accountId)) return;
    _events = events;
    _loaded = true;
    notifyListeners();
  }

  /// Files an event for the account that is signed in.
  ///
  /// Silently does nothing when nobody is. That is not a swallowed error: the
  /// events that can happen while signed out — a wipe, a failed unlock — belong
  /// to no account, and inventing an owner for them would file them under
  /// whoever signs in next.
  Future<void> record(SecurityEventKind kind, {String? subject, DateTime? at}) async {
    final account = _accountId;
    if (account == null) return;

    final event = SecurityEvent(kind: kind, at: at ?? DateTime.now(), subject: subject);
    // Shown before it is stored. The write is a keystore round trip and the
    // list is what the user is looking at; a row that appears half a second
    // after the thing it describes reads as a bug.
    _events = [event, ..._events];
    notifyListeners();

    await _log.append(event, accountId: account);
    if (!_stillOn(account)) return;
    // Re-read rather than trusting the optimistic insert: the log trims to its
    // limit, and the screen should show what is actually kept.
    _events = await _log.load(accountId: account);
    if (!_stillOn(account)) return;
    notifyListeners();
  }

  /// Sign-out. The events stay sealed on disk under the account they belong to
  /// and are simply not this controller's any more; [SecurityLog.clear] is for
  /// a wipe, which is a different decision and is made elsewhere.
  void signedOut({bool notify = true}) {
    _accountId = null;
    _events = const [];
    _loaded = false;
    if (notify) notifyListeners();
  }

  /// Deletes the log outright. Only from a wipe or an account deletion.
  Future<void> forget() async {
    await _log.clear();
    _events = const [];
    _loaded = true;
    notifyListeners();
  }

  bool _stillOn(String account) => _accountId == account;
}
