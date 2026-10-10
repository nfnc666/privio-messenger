import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'status_controller.dart';

/// A server-filtered profile. Deliberately no phone number or arbitrary fields.
class ContactProfile {
  ContactProfile(Map<String, dynamic> json)
      : id = json['id'] as String,
        username = json['username'] as String,
        displayName = (json['displayName'] ?? json['username']) as String,
        avatarMediaId = json['avatarMediaId'] as String?,
        status = ProfileStatus.fromJson(json['status'] as Map<String, dynamic>?),
        lastSeenAt = DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
        isContact = json['isContact'] == true,
        isBlocked = json['isBlocked'] == true;

  final String id;
  final String username;
  final String displayName;
  final String? avatarMediaId;
  final ProfileStatus status;
  final DateTime? lastSeenAt;
  final bool isContact;
  final bool isBlocked;
}

/// Route-owned; no global cache. Even re-login to the same account invalidates it.
class ContactProfileController extends ChangeNotifier {
  ContactProfileController(this.api, this.accountId)
      : generation = api.sessionGeneration;

  final PrivioApiClient api;
  final String accountId;
  final int generation;
  bool _disposed = false;
  int _request = 0;
  ContactProfile? _profile;
  bool loading = true;
  bool missing = false;
  bool failed = false;
  bool busy = false;

  bool get active => !_disposed && api.sessionGeneration == generation;
  ContactProfile? get profile => active ? _profile : null;

  Future<void> load() async {
    if (!active) return;
    final request = ++_request;
    loading = true;
    failed = false;
    missing = false;
    _profile = null;
    notifyListeners();
    try {
      final json = await api.lookupById(accountId);
      if (!active || request != _request) return;
      final profile = ContactProfile(json);
      if (profile.id != accountId) throw const FormatException('Profile ID mismatch');
      _profile = profile;
    } on StaleSessionException {
      return;
    } on ApiException catch (error) {
      if (!active || request != _request) return;
      missing = error.statusCode == 404;
      failed = !missing;
    } on Object {
      if (!active || request != _request) return;
      failed = true;
    }
    if (!active || request != _request) return;
    loading = false;
    notifyListeners();
  }

  Future<bool> change(Future<void> Function() operation) async {
    if (!active || busy) return false;
    busy = true;
    notifyListeners();
    try {
      await operation();
      if (!active) return false;
      await load();
      return active && !failed && !missing;
    } on Object {
      return false;
    } finally {
      if (active) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _profile = null;
    super.dispose();
  }
}
