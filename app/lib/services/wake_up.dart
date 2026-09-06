import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/edition.dart';
import 'notification_permission.dart';

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

  /// Firebase Cloud Messaging. The Play build only — it is the one edition
  /// allowed to contain Google's library at all.
  fcm,

  /// Apple Push Notification service. The App Store build. Nothing extra is
  /// linked for it; the capability is the operating system's.
  apns,
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

/// FCM or APNs, over a method channel.
///
/// Deliberately the same interface as a UnifiedPush distributor, because from
/// above they are the same thing: something that yields an opaque handle the
/// server can post a wake-up to. What differs is who has to be trusted to stay
/// up, and that difference belongs in the documentation and on the settings
/// screen, not in the registration logic.
///
/// Firebase is never linked into the Libre or direct builds. The channel is
/// answered by the Play flavour's own source set, so the Dart side asking for
/// a token in a build that has no Firebase gets [MissingPluginException] and
/// reads it as "not available here", which is exactly true.
class ChannelVendorPush implements PushDistributor {
  const ChannelVendorPush([this._channel = const MethodChannel('app.privio/push')]);

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
      return await _channel.invokeMethod<String>('token');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A device with no Play services, or an APNs registration the system
      // refused. Both are "no token", and both are already explained on the
      // screen that offers this.
      return null;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod<void>('delete');
    } on MissingPluginException {
      // Nothing was ever issued.
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
///
/// The four editions reach that rule differently, and the difference is not
/// cosmetic: `libre` and `direct` may contain nothing proprietary, so their
/// only path off the socket is a distributor the user installed and chose.
/// `play` and `appstore` have a vendor service the operating system already
/// runs, so there is nothing for the user to pick and registration happens on
/// sign-in without asking.
class WakeUpController extends ChangeNotifier {
  WakeUpController(
    this._api, {
    PushDistributor? distributor,
    NotificationPermissions? permissions,
    PrivioEdition? edition,
  })  : _edition = edition ?? PrivioEdition.current,
        _distributor = distributor ??
            ((edition ?? PrivioEdition.current).pushProvider == 'unifiedpush'
                ? const ChannelPushDistributor()
                : const ChannelVendorPush()),
        _permissions = permissions ?? const ChannelNotificationPermissions();

  final PrivioApiClient _api;
  final PushDistributor _distributor;
  final NotificationPermissions _permissions;
  final PrivioEdition _edition;

  WakeUpMethod _method = WakeUpMethod.socket;
  bool _distributorAvailable = false;
  bool _busy = false;
  String? _error;
  NotificationPermission _permission = NotificationPermission.notRequested;

  WakeUpMethod get method => _method;

  /// Whether offering the UnifiedPush option would mean anything on this phone.
  bool get distributorAvailable => _distributorAvailable;

  bool get busy => _busy;

  String? get error => _error;

  /// What the operating system last said about showing notifications.
  NotificationPermission get permission => _permission;

  /// True for the builds that may use a push service at all.
  bool get isOffered => _edition.pushProvider != null;

  /// Which service this build would register with, if any.
  String? get provider => _edition.pushProvider;

  /// True where the operating system runs the push service itself, so there is
  /// no choice to put in front of the user and nothing to install.
  bool get isVendorPush => provider == 'fcm' || provider == 'apns';

  /// What to tell someone whose notifications are switched off.
  ///
  /// Worth saying precisely rather than as a warning triangle, because the two
  /// halves of it are genuinely different: Privio can still *receive* while it
  /// is running, and it cannot *tell you* about it at all. The way back is the
  /// system settings — neither platform shows its prompt twice.
  String? get permissionWarning => switch (_permission) {
        NotificationPermission.denied =>
          'Notifications are turned off for Privio in your system settings. '
              'Messages still arrive while Privio is open — you will not be '
              'told about them, and a call will not ring.',
        NotificationPermission.notRequested when isVendorPush =>
          'Privio has not been allowed to notify you yet.',
        _ => null,
      };

  /// Looks at what the system says. Cheap, and safe to call whenever the
  /// screen opens.
  Future<void> refresh() async {
    _distributorAvailable = await _distributor.isAvailable();
    _permission = await _permissions.status();
    notifyListeners();
  }

  /// Shows the system prompt, once, and records the answer.
  Future<NotificationPermission> requestPermission() async {
    _permission = await _permissions.request();
    notifyListeners();
    return _permission;
  }

  /// Registers this device for push if this build can, and should, do so alone.
  ///
  /// Called after sign-in. It does nothing at all on `libre` and `direct`,
  /// deliberately: registering there means picking a distributor, which is a
  /// disclosure to whoever runs it and therefore the user's decision, not
  /// something to do on their behalf while they are looking at a chat list.
  ///
  /// Failure is quiet by design. There is a working fallback — the socket —
  /// and a sign-in that fails because a push service was unreachable would be
  /// a worse app than one that is simply woken less promptly.
  Future<void> ensureRegistered() async {
    if (!isVendorPush) return;

    _permission = await _permissions.status();
    if (_permission == NotificationPermission.notRequested) {
      _permission = await _permissions.request();
    }

    // A refused permission does not stop the token being registered. A push
    // still wakes the process and still fetches the messages; what it may not
    // do is put anything on the screen. Refusing to register would turn "you
    // will not be told" into "it will not arrive", which is worse and is not
    // what the user asked for.
    final token = await _distributor.register();
    if (token == null) {
      _error = _unavailableMessage;
      notifyListeners();
      return;
    }

    try {
      await _api.registerPushToken(provider: provider, token: token);
      _method = provider == 'fcm' ? WakeUpMethod.fcm : WakeUpMethod.apns;
      _error = null;
    } on Object {
      // Left on the socket. The next sign-in tries again, and a token that was
      // never registered is one the server will not post to — which is right,
      // because it does not have it.
    }
    notifyListeners();
  }

  /// Hands the server a token the platform has just replaced.
  ///
  /// Both vendors reissue tokens — on reinstall, on a restore to a new phone,
  /// or on their own schedule — and a server still holding the old one posts
  /// wake-ups nobody receives. The platform tells the app; the app tells the
  /// server, and only then is the new token the registered one.
  Future<bool> handleTokenChanged(String token) async {
    if (!isOffered) return false;
    try {
      await _api.registerPushToken(provider: provider, token: token);
      _method = switch (provider) {
        'fcm' => WakeUpMethod.fcm,
        'apns' => WakeUpMethod.apns,
        _ => WakeUpMethod.unifiedPush,
      };
      _error = null;
      notifyListeners();
      return true;
    } on Object {
      // Deliberately not surfaced: this is a background event with no screen
      // behind it. The device keeps working on the socket, and the next
      // sign-in or the next refresh registers the current token.
      return false;
    }
  }

  /// Stops push for this device, on the way out.
  ///
  /// The server is cleared first and the platform second, in that order: a
  /// device that has told the vendor to forget it but left the token
  /// registered has the relay posting into the void, and on a shared or
  /// resold phone that void may later belong to somebody else.
  ///
  /// Errors are swallowed because this runs during sign-out, which must not be
  /// blocked by a network. The server drops the token with the session anyway.
  Future<void> signOutOfPush() async {
    try {
      await _api.registerPushToken(provider: null, token: null);
    } on Object {
      // The session is going away regardless.
    }
    try {
      await _distributor.unregister();
    } on Object {
      // Same.
    }
    _method = WakeUpMethod.socket;
    _error = null;
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

  String get _unavailableMessage => switch (provider) {
        'fcm' => 'This phone has no Google Play services, so Privio cannot be '
            'woken while it is closed. Messages arrive while Privio is open.',
        'apns' => 'iOS did not issue a push token for Privio, so it cannot be '
            'woken while it is closed. Messages arrive while Privio is open.',
        _ => 'No push service answered. Messages arrive while Privio is open.',
      };
}
