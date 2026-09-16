import 'package:flutter/foundation.dart';

import '../models/contact_profile.dart';
import 'api_client.dart';
import 'failure.dart';

/// Why a report was not filed, or that it already was.
enum ReportOutcome {
  filed,

  /// The server already had a standing report from this account about this
  /// person. Not a failure — the complaint is on file — and said differently
  /// so the screen does not claim to have filed a second one.
  alreadyFiled,
  failed,
}

/// Where a profile is: still being fetched, here, gone, or unreadable.
///
/// A sealed set of cases rather than a profile plus two booleans, because the
/// screen has to draw four genuinely different things and "null profile and
/// null failure" is not a state anybody can reason about at the call site.
@immutable
sealed class ProfileView {
  const ProfileView();
}

/// The first read has not come back yet.
class ProfileLoading extends ProfileView {
  const ProfileLoading();
}

class ProfileReady extends ProfileView {
  const ProfileReady(this.profile);

  final ContactProfile profile;
}

/// The account is not there: deleted, or never existed.
///
/// Its own case rather than a failure, because it is an answer rather than a
/// breakdown, and the two need different words: "this account no longer exists"
/// is a fact, and "could not reach the server" is a suggestion to try again.
class ProfileGone extends ProfileView {
  const ProfileGone();
}

class ProfileUnavailable extends ProfileView {
  const ProfileUnavailable(this.failure);

  final Failure failure;
}

/// Other people's profiles, for whoever is signed in.
///
/// Two rules, both from the fact that a profile is read *by* an account and
/// says different things depending on which account asked:
///
/// 1. **The cache belongs to a viewer.** [bindTo] records whose it is and drops
///    everything the moment that changes. Bob's status may be visible to Alice
///    and hidden from Carol; holding one map across an account switch would put
///    Alice's answer on Carol's screen.
/// 2. **A late answer is dropped, not applied.** Every read captures the viewer
///    it was made for and checks on completion that this controller is still
///    that viewer. A lookup in flight when somebody switches accounts finishes
///    into nothing.
///
/// Profiles are keyed by account id and never by name. A display name is not
/// unique, is chosen by the person it names, and can be changed to somebody
/// else's at any time.
class ProfileController extends ChangeNotifier {
  ProfileController(this._api);

  final PrivioApiClient _api;

  String? _viewerId;
  final Map<String, ProfileView> _views = {};

  /// Which reads are in flight, so a screen that rebuilds does not start a
  /// second one for the same person.
  final Set<String> _inFlight = {};

  /// The account whose view of the world this holds, or null before sign-in.
  String? get viewerId => _viewerId;

  /// Points this controller at an account, clearing anything the previous one
  /// had read.
  void bindTo(String accountId) {
    if (_viewerId == accountId) return;
    _viewerId = accountId;
    _views.clear();
    _inFlight.clear();
    notifyListeners();
  }

  /// What is known about [accountId] right now. Never null: a profile nobody
  /// has asked for yet is [ProfileLoading], which is what a screen that has
  /// just been pushed should draw.
  ProfileView viewOf(String accountId) => _views[accountId] ?? const ProfileLoading();

  /// Reads a profile from the server.
  ///
  /// Returns what is cached without asking again, unless [force]. The screen
  /// forces a re-read after anything that changes the relationship — adding,
  /// blocking — so the buttons come from the server's answer rather than from
  /// an optimistic guess this device made.
  Future<void> load(String accountId, {bool force = false}) async {
    final viewer = _viewerId;
    if (viewer == null) return;
    if (!force && _views[accountId] is ProfileReady) return;
    if (_inFlight.contains(accountId)) return;

    _inFlight.add(accountId);
    if (_views[accountId] == null) {
      _views[accountId] = const ProfileLoading();
      notifyListeners();
    }

    try {
      final json = await _api.lookupById(accountId);
      if (!_stillOn(viewer)) return;
      _views[accountId] = ProfileReady(ContactProfile.fromJson(json));
    } on ApiException catch (failure) {
      if (!_stillOn(viewer)) return;
      // 404 is the deleted account and the never-existed account alike, and the
      // server deliberately does not tell them apart — doing so would answer
      // "did this id ever exist" for anybody who asks.
      _views[accountId] = failure.statusCode == 404
          ? const ProfileGone()
          : ProfileUnavailable(Failure.server(failure.message));
    } on Object {
      if (!_stillOn(viewer)) return;
      _views[accountId] = const ProfileUnavailable(Failure(FailureKind.unreachable));
    } finally {
      // Guarded like everything else: an account switch mid-request means this
      // controller is somebody else's now, and clearing the flag would let a
      // second read start against a cache that has already been emptied.
      if (_stillOn(viewer)) {
        _inFlight.remove(accountId);
        notifyListeners();
      }
    }
  }

  /// Files a report about somebody.
  ///
  /// Deliberately does **not** block them as a side effect. The two sit next to
  /// each other on the profile screen and a user may well want both, but a
  /// report that silently blocked would turn an accusation into a change to
  /// your own account without being asked.
  Future<ReportOutcome> report(String accountId, String reason) async {
    final viewer = _viewerId;
    if (viewer == null) return ReportOutcome.failed;
    try {
      final answer = await _api.reportUser(accountId, reason);
      if (!_stillOn(viewer)) return ReportOutcome.failed;
      return (answer['alreadyReported'] as bool? ?? false)
          ? ReportOutcome.alreadyFiled
          : ReportOutcome.filed;
    } on Object {
      return ReportOutcome.failed;
    }
  }

  /// Forgets everything, on the way out of an account.
  void signedOut({bool notify = true}) {
    _viewerId = null;
    _views.clear();
    _inFlight.clear();
    if (notify) notifyListeners();
  }

  bool _stillOn(String viewer) => _viewerId == viewer;
}
