import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/edition.dart';

/// How this device expects to be told that something arrived.
enum WakeUpMethod {
  /// The app's own connection, open only while the app is running. What every
  /// build did before there was anything else, and the fallback when there is
  /// no distributor to register with.
  socket,

  /// A UnifiedPush distributor: an app the user installed, often self-hosted,
  /// that holds one connection for every app on the phone and forwards a
  /// contentless POST from the server.
  unifiedPush,
}

/// A UnifiedPush distributor on the device.
///
/// An interface for the same reason the keystore and the microphone are ones:
/// the logic above must not depend on a platform plugin, and the whole
/// registration flow has to be testable without an Android device or a second
/// app installed.
abstract interface class PushDistributor {
  /// Whether any distributor is installed and willing to register this app.
  Future<bool> isAvailable();

  /// Registers and returns the endpoint URL the server should POST to, or null
  /// if the user declined or no distributor answered.
  Future<String?> register();

  /// Tells the distributor to forget this app.
  Future<void> unregister();
}

/// What a build with no distributor integration compiled in reports.
///
/// Not a stub standing in for something finished elsewhere: a phone with no
/// distributor installed genuinely has none, and the honest answer is the same.
class NoDistributor implements PushDistributor {
  const NoDistributor();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String?> register() async => null;

  @override
  Future<void> unregister() async {}
}

/// Talks to the platform side over a method channel.
///
/// Deliberately not a pub dependency: the UnifiedPush connector is an Android
/// library, and keeping the Dart side on a channel means the Libre and Play
/// flavours can differ in what they link without the Dart tree knowing.
///
/// The Android half of this channel is not written yet. Until it is, the
/// channel is missing and every call answers "no distributor" — which is what
/// [MissingPluginException] means here, and why it is caught rather than
/// allowed to surface as a crash on a phone that simply has nothing installed.
class ChannelPushDistributor implements PushDistributor {
  const ChannelPushDistributor([this._channel = const MethodChannel('app.privio/unifiedpush')]);

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> register() async {
    try {
      return await _channel.invokeMethod<String>('register');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod<void>('unregister');
    } on MissingPluginException {
      // Nothing registered, nothing to forget.
    } on PlatformException {
      // Same.
    }
  }
}

/// Chooses and registers how this device is woken.
///
/// The rule it enforces is the one that makes the choice worth having: what
/// the server sends is a wake-up, never content, whichever path it takes. A
/// distributor — including a public one — learns that a device was pinged and
/// nothing else, and the message itself is fetched over the app's own TLS
/// connection.
class WakeUpController extends ChangeNotifier {
  WakeUpController(this._api, {PushDistributor? distributor})
      : _distributor = distributor ?? const ChannelPushDistributor();

  final PrivioApiClient _api;
  final PushDistributor _distributor;

  WakeUpMethod _method = WakeUpMethod.socket;
  bool _distributorAvailable = false;
  bool _busy = false;
  String? _error;

  WakeUpMethod get method => _method;

  /// Whether offering the UnifiedPush option would mean anything on this phone.
  bool get distributorAvailable => _distributorAvailable;

  bool get busy => _busy;

  String? get error => _error;

  /// True for the builds that may use a push service at all.
  bool get isOffered => PrivioEdition.current.pushProvider != null;

  /// Looks for a distributor. Cheap, and safe to call whenever the screen opens.
  Future<void> refresh() async {
    _distributorAvailable = await _distributor.isAvailable();
    notifyListeners();
  }

  /// Registers with the distributor and hands the endpoint to the server.
  ///
  /// Returns false with [error] set if there was nothing to register with, or
  /// if the server refused the endpoint — it validates that the URL is public
  /// and HTTPS, and a distributor pointed at a private address is refused
  /// there rather than here.
  Future<bool> useUnifiedPush() async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final endpoint = await _distributor.register();
      if (endpoint == null) {
        _error = 'No UnifiedPush distributor answered. Install one — ntfy, for '
            'example — and try again.';
        return false;
      }
      await _api.registerPushToken(provider: 'unifiedpush', token: endpoint);
      _method = WakeUpMethod.unifiedPush;
      return true;
    } on ApiException catch (failure) {
      _error = failure.code == 'invalid_push_config'
          ? 'Privio cannot reach that distributor. It has to be an https address '
              'on the public internet.'
          : failure.message;
      // The server did not take it, so nothing should think it did.
      await _distributor.unregister();
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection and try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Goes back to the app's own connection, and stops the server pushing.
  ///
  /// The server is told first: a device that has forgotten its distributor but
  /// left the endpoint registered would have the relay posting into the void.
  Future<void> useSocketOnly() async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _api.registerPushToken(provider: null, token: null);
      await _distributor.unregister();
      _method = WakeUpMethod.socket;
    } on Object {
      _error = 'Could not reach Privio. The change has not been saved.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
