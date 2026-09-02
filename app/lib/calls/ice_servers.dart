import 'dart:async';

import '../core/api_client.dart';

/// Where the two devices should look for each other, as the server offers it.
///
/// Configured on the server rather than compiled into each build, so that
/// someone running their own Privio sets it once and every client picks it up.
class IceServers {
  const IceServers(this.servers, {this.expiresAt});

  /// Nothing configured. The two devices then try only the addresses they can
  /// see for themselves: fine on one network and behind simple NATs, and not
  /// enough behind strict ones.
  static const IceServers none = IceServers(<Map<String, dynamic>>[]);

  factory IceServers.fromJson(Map<String, dynamic> json) {
    final raw = json['iceServers'] as List<dynamic>? ?? const [];
    final expiry = json['expiresAt'] as int?;
    return IceServers(
      [
        for (final entry in raw)
          if (entry is Map<String, dynamic>) {
            'urls': entry['urls'],
            if (entry['username'] != null) 'username': entry['username'],
            if (entry['credential'] != null) 'credential': entry['credential'],
          },
      ],
      expiresAt: expiry == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true),
    );
  }

  /// Ready to hand to a peer connection.
  final List<Map<String, dynamic>> servers;

  /// When the TURN credential stops working, if there is one.
  final DateTime? expiresAt;

  bool get isEmpty => servers.isEmpty;

  bool isStaleAt(DateTime now) =>
      expiresAt != null && now.isAfter(expiresAt!.subtract(const Duration(minutes: 5)));
}

/// Holds the ICE configuration between calls.
///
/// Fetched when the app connects and kept until the credential is close to
/// expiring — deliberately not fetched when a call starts. Asking at that
/// moment would tell the server a call is about to happen, which is a piece of
/// metadata it otherwise never gets: the signalling itself is sealed, so
/// routing a call looks to the server exactly like routing a message.
class IceServerCache {
  IceServerCache({required PrivioApiClient api, DateTime Function() now = DateTime.now})
      : _api = api,
        _now = now;

  final PrivioApiClient _api;
  final DateTime Function() _now;

  IceServers _cached = IceServers.none;
  Future<void>? _loading;

  IceServers get current => _cached;

  /// Fetches if there is nothing usable held. Failures are not an error worth
  /// surfacing: a call without STUN still connects on most networks, and one
  /// that cannot connect reports that on its own.
  Future<IceServers> ensure() async {
    if (_cached.servers.isNotEmpty && !_cached.isStaleAt(_now())) return _cached;
    await (_loading ??= _load().whenComplete(() => _loading = null));
    return _cached;
  }

  Future<void> _load() async {
    try {
      _cached = IceServers.fromJson(await _api.iceServers());
    } on ApiException {
      _cached = IceServers.none;
    }
  }

  /// Drops what is held, for a sign-out: a TURN credential belongs to the
  /// session it was issued to.
  void clear() => _cached = IceServers.none;
}
