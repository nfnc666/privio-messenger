import 'package:flutter/services.dart';

/// The platform telling Dart that a wake-up arrived, or that the push service
/// issued a new address for this device.
///
/// One direction only: nothing here is ever called *from* Dart. A wake-up
/// carries nothing — the server sends a contentless ping and the device fetches
/// its envelopes over its own TLS connection — so the whole payload of `wake`
/// is the fact that it happened.
class PushWakeListener {
  PushWakeListener([MethodChannel channel = const MethodChannel('app.privio/wake')])
      : _channel = channel;

  final MethodChannel _channel;

  Future<void> Function()? _onWake;
  Future<void> Function(String token)? _onTokenChanged;

  /// Starts listening, and says what to do with each of the two events.
  ///
  /// Called on sign-in rather than at construction, because until somebody is
  /// signed in there is no queue to drain and no device row to register a token
  /// against.
  void listen({
    required Future<void> Function() onWake,
    required Future<void> Function(String token) onTokenChanged,
  }) {
    _onWake = onWake;
    _onTokenChanged = onTokenChanged;
    _channel.setMethodCallHandler(handle);
  }

  void stop() {
    _onWake = null;
    _onTokenChanged = null;
    _channel.setMethodCallHandler(null);
  }

  /// Exposed so the two paths can be driven without a phone.
  Future<void> handle(MethodCall call) async {
    switch (call.method) {
      case 'wake':
        // Deliberately not deduplicated here. The fetch below drops an envelope
        // it has already opened — see `MessagingService`'s watermark — so two
        // wake-ups for the same message cost one wasted request and never a
        // duplicated message. Guessing at it twice would be a second, worse
        // copy of a rule that already works.
        await _onWake?.call();
      case 'tokenChanged':
        final token = call.arguments;
        if (token is String && token.isNotEmpty) await _onTokenChanged?.call(token);
      default:
        // A platform half that has learned a new trick this build does not know
        // is not a reason to throw. It is a reason to ignore it.
        break;
    }
  }
}
