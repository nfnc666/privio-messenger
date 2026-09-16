import 'package:flutter/services.dart';

/// Opens this app's page in the system settings.
///
/// Both platforms take every refused permission to the same place — one page
/// per app, with the notification switch, the camera switch and the photo
/// access on it — so this is one call rather than one per permission.
///
/// The channel is the one the notification screen has always used. The name is
/// historical and the alternative was worse: a second channel would mean a
/// second native handler doing exactly the same thing on both platforms, and
/// two places to forget to implement it. Android forgot once already — the
/// button existed there for months with nothing behind it.
class SystemSettings {
  const SystemSettings([this._channel = const MethodChannel('app.privio/notifications')]);

  final MethodChannel _channel;

  /// Whether the settings page actually opened.
  ///
  /// False rather than a throw when the native half is missing, so the screen
  /// can fall back to telling the user where to go instead of crashing in the
  /// middle of a refusal they are already unhappy about.
  Future<bool> open() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
