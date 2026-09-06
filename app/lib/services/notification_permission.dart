import 'package:flutter/services.dart';

/// What the operating system currently says about showing notifications.
///
/// Four answers rather than a bool, because "not asked yet" and "asked and
/// refused" call for different things from the app: the first is a prompt, the
/// second is an explanation and a way into the system settings, and offering
/// the prompt again to someone who already said no does nothing on either
/// platform.
enum NotificationPermission {
  /// Never asked. Both platforms allow exactly one prompt.
  notRequested,

  granted,

  /// Refused, or turned off later in the system settings. Asking again is a
  /// no-op; only the settings app can change it back.
  denied,

  /// This build cannot show notifications at all — the web build, or a
  /// platform with no notification service. Not a failure, and not something
  /// to offer a button for.
  unsupported,
}

/// The platform's notification permission, behind an interface.
///
/// Same reason as the keystore and the microphone: the registration logic has
/// to be testable without a phone, and every state below — including the
/// refusal — has to be reachable in a test.
abstract interface class NotificationPermissions {
  Future<NotificationPermission> status();

  /// Shows the system prompt if it has never been shown, and returns what the
  /// system says afterwards. Returns the existing answer otherwise.
  Future<NotificationPermission> request();
}

/// What a build with no notification integration reports.
class NoNotificationPermissions implements NotificationPermissions {
  const NoNotificationPermissions();

  @override
  Future<NotificationPermission> status() async => NotificationPermission.unsupported;

  @override
  Future<NotificationPermission> request() async => NotificationPermission.unsupported;
}

/// Asks the platform over a method channel.
///
/// A missing channel reads as [NotificationPermission.unsupported] rather than
/// as a crash: a build whose native half is not there is in the same position
/// as a platform that cannot do this, and the app says so either way.
class ChannelNotificationPermissions implements NotificationPermissions {
  const ChannelNotificationPermissions([
    this._channel = const MethodChannel('app.privio/notifications'),
  ]);

  final MethodChannel _channel;

  @override
  Future<NotificationPermission> status() => _ask('status');

  @override
  Future<NotificationPermission> request() => _ask('request');

  Future<NotificationPermission> _ask(String method) async {
    try {
      return _parse(await _channel.invokeMethod<String>(method));
    } on MissingPluginException {
      return NotificationPermission.unsupported;
    } on PlatformException {
      return NotificationPermission.unsupported;
    }
  }

  static NotificationPermission _parse(String? raw) => switch (raw) {
        'granted' => NotificationPermission.granted,
        'denied' => NotificationPermission.denied,
        'notRequested' => NotificationPermission.notRequested,
        _ => NotificationPermission.unsupported,
      };
}
