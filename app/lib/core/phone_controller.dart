import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'failure.dart';
import '../models/security_event.dart';
import 'phone_number.dart';

/// What this account's phone link looks like right now.
@immutable
class PhoneLink {
  const PhoneLink({
    this.linked = false,
    this.hint,
    this.discoverable = false,
    this.contactSync = false,
    this.verifiedAt,
    this.smsAvailable = false,
    this.discoveryAvailable = false,
  });

  factory PhoneLink.fromJson(Map<String, dynamic> json) => PhoneLink(
        linked: json['linked'] as bool? ?? false,
        hint: json['hint'] as String?,
        discoverable: json['discoverable'] as bool? ?? false,
        contactSync: json['contactSync'] as bool? ?? false,
        verifiedAt: DateTime.tryParse(json['verifiedAt'] as String? ?? '')?.toLocal(),
        smsAvailable: json['smsAvailable'] as bool? ?? false,
        discoveryAvailable: json['discoveryAvailable'] as bool? ?? false,
      );

  final bool linked;

  /// "+49 … 87". The server cannot return the number, only this.
  final String? hint;

  /// Whether other people may find this account by its number. **Off unless
  /// asked for**, and reset to off whenever the number changes.
  final bool discoverable;

  /// Whether this account syncs its device contacts at all. Separate consent.
  final bool contactSync;

  final DateTime? verifiedAt;

  /// Whether this deployment can send a text at all. False means the button to
  /// add a number is not offered, rather than offered and always failing.
  final bool smsAvailable;

  /// Whether this deployment has a discovery key configured.
  final bool discoveryAvailable;

  /// Whether adding or changing a number is possible here at all.
  bool get canVerify => smsAvailable && discoveryAvailable;
}

/// One account found by its number.
@immutable
class DiscoveredContact {
  const DiscoveredContact({
    required this.blinded,
    required this.accountId,
    required this.username,
    this.displayName,
  });

  factory DiscoveredContact.fromJson(Map<String, dynamic> json) => DiscoveredContact(
        blinded: json['blinded'] as String? ?? '',
        accountId: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
      );

  /// Which submitted entry this answers, so the app can put its own address
  /// book name to it without the server ever being told one.
  final String blinded;

  final String accountId;
  final String username;
  final String? displayName;
}

/// Where a verification has got to.
enum PhoneStage {
  /// Nothing in flight.
  idle,

  /// A code has been sent and is being waited for.
  awaitingCode,
}

/// This account's phone number, its two consents, and matching contacts.
///
/// Per account and with a late-answer guard, like every other controller here:
/// a phone link belongs to an account, and an answer that arrives after a
/// switch is dropped rather than applied. A number attached on one account
/// must never appear on the next.
///
/// **What this never does**, because the brief is explicit and the code should
/// be too: it does not read the address book. That is the screen's job, after
/// the operating system has said yes, and only when [PhoneLink.contactSync] is
/// on. This object takes numbers it is handed, blinds them, and asks.
class PhoneController extends ChangeNotifier {
  PhoneController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  PhoneLink _link = const PhoneLink();
  PhoneStage _stage = PhoneStage.idle;
  String? _pendingHint;
  DateTime? _codeExpiresAt;
  bool _busy = false;
  bool _loaded = false;
  Failure? _failure;

  /// The development stub's code, when the server is running one.
  ///
  /// Present only when the server answered `developmentStub: true`, and the
  /// screen shows it with a label saying exactly that. It exists so the flow
  /// can be worked on without a paid SMS account; it is never a delivered
  /// message and nothing here pretends otherwise.
  String? _stubCode;

  String? get accountId => _accountId;
  PhoneLink get link => _link;
  PhoneStage get stage => _stage;
  String? get pendingHint => _pendingHint;
  DateTime? get codeExpiresAt => _codeExpiresAt;
  bool get busy => _busy;
  bool get loaded => _loaded;
  Failure? get failure => _failure;
  String? get stubCode => _stubCode;

  /// Reads the link for an account.
  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _link = const PhoneLink();
      _stage = PhoneStage.idle;
      _pendingHint = null;
      _stubCode = null;
      _loaded = false;
      _failure = null;
      notifyListeners();
    }

    try {
      final json = await _api.phoneLink();
      if (!_stillOn(accountId)) return;
      _link = PhoneLink.fromJson(json);
      _loaded = true;
      _failure = null;
    } on StaleSessionException {
      return;
    } on Object catch (error) {
      if (!_stillOn(accountId)) return;
      _failure = Failure.of(error, FailureKind.unreachable);
    }
    notifyListeners();
  }

  /// Asks for a code. The number is normalised here first, so an obviously
  /// wrong one is refused before an SMS is paid for.
  Future<bool> requestCode(String typed) async {
    final normalised = PhoneNumbers.normalise(typed);
    if (normalised == null) {
      _failure = const Failure(FailureKind.phoneInvalid);
      notifyListeners();
      return false;
    }

    final done = await _write(() async {
      final json = await _api.requestPhoneCode(normalised.e164);
      _pendingHint = json['hint'] as String? ?? normalised.hint;
      _codeExpiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal();
      _stubCode = json['developmentStub'] == true ? json['code'] as String? : null;
      _stage = PhoneStage.awaitingCode;
      return true;
    });
    return done ?? false;
  }

  /// Confirms the code, which links the number.
  /// Where a security event goes, or null when nothing is listening.
  ///
  /// Linking or removing a number is a change to how findable this account is,
  /// so it belongs in the local security log — the same callback shape the
  /// other producers use, so this class never holds a reference to the screen
  /// that displays them. Set by [AppState].
  void Function(SecurityEventKind kind, {String? subject})? onSecurityEvent;

  Future<bool> confirmCode(String code) async {
    final done = await _write(() async {
      _link = PhoneLink.fromJson({
        ...await _api.confirmPhoneCode(code),
        // The server's answer is about the link; these two are properties of
        // the deployment and do not change, so they are carried across rather
        // than lost.
        'smsAvailable': _link.smsAvailable,
        'discoveryAvailable': _link.discoveryAvailable,
        'contactSync': _link.contactSync,
      });
      _stage = PhoneStage.idle;
      _pendingHint = null;
      _stubCode = null;
      // Only once the server has confirmed it. An event filed on the attempt
      // would say a number was linked when the code was wrong.
      onSecurityEvent?.call(SecurityEventKind.phoneLinked);
      return true;
    });
    return done ?? false;
  }

  /// Abandons a verification in flight. Nothing is linked and nothing is sent.
  void cancelVerification() {
    if (_stage == PhoneStage.idle) return;
    _stage = PhoneStage.idle;
    _pendingHint = null;
    _stubCode = null;
    _failure = null;
    notifyListeners();
  }

  Future<bool> setDiscoverable(bool discoverable) async {
    final done = await _write(() async {
      final json = await _api.setPhoneDiscoverable(discoverable);
      _link = PhoneLink.fromJson({
        ...json,
        'smsAvailable': _link.smsAvailable,
        'discoveryAvailable': _link.discoveryAvailable,
        'contactSync': _link.contactSync,
      });
      return true;
    });
    return done ?? false;
  }

  Future<bool> setContactSync(bool enabled) async {
    final done = await _write(() async {
      await _api.setContactSync(enabled);
      _link = PhoneLink(
        linked: _link.linked,
        hint: _link.hint,
        discoverable: _link.discoverable,
        contactSync: enabled,
        verifiedAt: _link.verifiedAt,
        smsAvailable: _link.smsAvailable,
        discoveryAvailable: _link.discoveryAvailable,
      );
      return true;
    });
    return done ?? false;
  }

  /// Removes the number, and with it the server-side link used for finding.
  Future<bool> removeNumber() async {
    final done = await _write(() async {
      await _api.removePhone();
      _link = PhoneLink(
        smsAvailable: _link.smsAvailable,
        discoveryAvailable: _link.discoveryAvailable,
        contactSync: _link.contactSync,
      );
      _stage = PhoneStage.idle;
      _pendingHint = null;
      onSecurityEvent?.call(SecurityEventKind.phoneRemoved);
      return true;
    });
    return done ?? false;
  }

  /// Matches a list of numbers, blinding them here first.
  ///
  /// Takes E.164 strings rather than reading anything: the caller has already
  /// been given permission by the operating system and has already normalised
  /// what it read. Numbers that do not normalise are dropped rather than sent,
  /// which is why an address book full of "Pizza (Mobile)" costs nothing.
  Future<List<DiscoveredContact>?> discover(List<String> numbers) async {
    final blinded = <String>{};
    for (final number in numbers) {
      final normalised = PhoneNumbers.normalise(number);
      if (normalised != null) blinded.add(PhoneNumbers.blind(normalised.e164));
    }
    if (blinded.isEmpty) return const [];

    return _write(() async {
      final json = await _api.discoverContacts(blinded.toList(growable: false));
      return ((json['matches'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DiscoveredContact.fromJson)
          .toList(growable: false);
    });
  }

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  /// Forgets everything, on the way out of an account.
  void signedOut({bool notify = true}) {
    _accountId = null;
    _link = const PhoneLink();
    _stage = PhoneStage.idle;
    _pendingHint = null;
    _stubCode = null;
    _busy = false;
    _loaded = false;
    _failure = null;
    if (notify) notifyListeners();
  }

  /// The busy flag, the account guard and the error mapping, in one place.
  Future<T?> _write<T>(Future<T> Function() body) async {
    if (_busy) return null;
    final account = _accountId;
    if (account == null) {
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return null;
    }

    _busy = true;
    _failure = null;
    notifyListeners();

    try {
      final result = await body();
      if (!_stillOn(account)) return null;
      _failure = null;
      return result;
    } on StaleSessionException {
      return null;
    } on ApiException catch (error) {
      if (!_stillOn(account)) return null;
      _failure = _refusalOf(error) ?? Failure.server(error.message);
      return null;
    } on Object {
      if (!_stillOn(account)) return null;
      _failure = const Failure(FailureKind.unreachable);
      return null;
    } finally {
      if (_stillOn(account)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// The server's codes, as cases this app has words for in five languages.
  static Failure? _refusalOf(ApiException error) => switch (error.code) {
        'invalid_phone' => const Failure(FailureKind.phoneInvalid),
        'sms_not_configured' => const Failure(FailureKind.phoneSmsUnavailable),
        'discovery_not_configured' => const Failure(FailureKind.phoneDiscoveryUnavailable),
        'wrong_code' => const Failure(FailureKind.phoneWrongCode),
        'code_expired' => const Failure(FailureKind.phoneCodeExpired),
        'too_many_attempts' => const Failure(FailureKind.phoneTooManyAttempts),
        'too_many_sends' => const Failure(FailureKind.phoneTooManySends),
        'resend_too_soon' => const Failure(FailureKind.phoneResendTooSoon),
        'no_verification' => const Failure(FailureKind.phoneNoVerification),
        'phone_unchanged' => const Failure(FailureKind.phoneUnchanged),
        'no_phone' => const Failure(FailureKind.phoneNotLinked),
        'lookup_budget_spent' => const Failure(FailureKind.phoneLookupBudgetSpent),
        _ => null,
      };

  bool _stillOn(String account) => _accountId == account;
}
