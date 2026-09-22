import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'phone_number.dart';

/// Owned by one account screen/session, never shared with PhoneController.
class AccountPhoneController extends ChangeNotifier {
  AccountPhoneController(this.api) : generation = api.sessionGeneration;
  final PrivioApiClient api;
  final int generation;
  bool _disposed = false;
  String? _number;
  bool _hasVerifiedNumber = false;
  bool loaded = false;
  bool busy = false;
  bool failed = false;

  bool get active => !_disposed && generation == api.sessionGeneration;
  String? get number => active ? _number : null;
  bool get hasVerifiedNumber => active && _hasVerifiedNumber;

  Future<bool> _request(Future<Map<String, dynamic>> Function() request) async {
    if (!active || busy) return false;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      final response = await request();
      if (!active) return false;
      // Fail closed if this route ever changes its semantics unexpectedly.
      if (response['verified'] != false || response['usedForDiscovery'] != false) {
        throw const FormatException('Unverified annotation response required');
      }
      _number = response['phoneNumber'] as String?;
      _hasVerifiedNumber = response['hasVerifiedNumber'] == true;
      loaded = true;
      return true;
    } on Object {
      if (active) failed = true;
      return false;
    } finally {
      if (active) { busy = false; notifyListeners(); }
    }
  }

  Future<bool> load() => _request(api.accountPhoneNote);

  Future<bool> save(String? value) {
    if (value == null || value.trim().isEmpty) return remove();
    final parsed = PhoneNumbers.normalise(value);
    if (parsed == null) return Future<bool>.value(false);
    return _request(() => api.saveAccountPhoneNote(parsed.e164));
  }

  Future<bool> remove() => _request(api.removeAccountPhoneNote);

  @override
  void dispose() { _disposed = true; _number = null; super.dispose(); }
}
