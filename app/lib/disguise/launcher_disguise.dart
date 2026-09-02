import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'skin.dart';

/// What the platform underneath can actually change about the launcher entry.
///
/// Not a boolean, because a platform can manage one and not the other. Android
/// changes both, through its launcher aliases. iOS is not asked at all: it can
/// swap an icon and cannot change a name — an app's display name is fixed at
/// build time with no public API — and a calculator icon still labelled Privio
/// is a disguise that says its own name, so the whole feature is withheld
/// there rather than shipped half-working.
@immutable
class LauncherCapability {
  const LauncherCapability({required this.icon, required this.name});

  /// Nothing can be changed — the web build, or a platform with no channel.
  static const LauncherCapability none = LauncherCapability(icon: false, name: false);

  final bool icon;
  final bool name;

  bool get any => icon || name;

  @override
  bool operator ==(Object other) =>
      other is LauncherCapability && other.icon == icon && other.name == name;

  @override
  int get hashCode => Object.hash(icon, name);
}

/// The app's entry in the launcher: its icon and, where the platform allows it,
/// its name.
///
/// An interface for the same reason the microphone and the keystore are: the
/// only implementation that can do anything talks to Android and iOS, and the
/// logic around it — when it is applied, what happens when it fails, what the
/// settings screen promises — should be testable without either.
abstract interface class LauncherDisguise {
  /// What this device can change.
  Future<LauncherCapability> capability();

  /// Shows the calculator entry, or puts Privio's own back when [skin] is null.
  ///
  /// Throws [LauncherDisguiseException] when the platform refuses. It is worth
  /// surfacing rather than swallowing: someone who turned the disguise on has
  /// been told their icon will change, and an icon that did not change is a
  /// promise broken quietly.
  Future<void> apply(CalculatorSkin? skin);
}

class LauncherDisguiseException implements Exception {
  const LauncherDisguiseException(this.message);

  final String message;

  @override
  String toString() => 'LauncherDisguiseException: $message';
}

/// The real one: a method channel to Kotlin on Android and Swift on iOS.
class PlatformLauncherDisguise implements LauncherDisguise {
  const PlatformLauncherDisguise();

  static const MethodChannel _channel = MethodChannel('app.privio/launcher');

  /// iOS has no handler on the other end of this channel, on purpose. Asking
  /// anyway would work — it would answer nothing — but not asking is the
  /// clearer statement that the feature is not offered there.
  static bool get _supported => defaultTargetPlatform != TargetPlatform.iOS;

  @override
  Future<LauncherCapability> capability() async {
    if (kIsWeb || !_supported) return LauncherCapability.none;
    try {
      final answer = await _channel.invokeMapMethod<String, dynamic>('capability');
      if (answer == null) return LauncherCapability.none;
      return LauncherCapability(
        icon: answer['icon'] as bool? ?? false,
        name: answer['name'] as bool? ?? false,
      );
    } on PlatformException {
      return LauncherCapability.none;
    } on MissingPluginException {
      // A platform with no handler — the desktop builds, or a hot reload
      // against an older host. Nothing is changeable, which is the truth.
      return LauncherCapability.none;
    }
  }

  @override
  Future<void> apply(CalculatorSkin? skin) async {
    if (kIsWeb || !_supported) return;
    try {
      await _channel.invokeMethod<void>('apply', {'skin': skin?.name});
    } on PlatformException catch (failure) {
      throw LauncherDisguiseException(failure.message ?? 'The launcher refused the change.');
    } on MissingPluginException {
      throw const LauncherDisguiseException('This device cannot change the app icon.');
    }
  }
}

/// Does nothing, and says so. The web build and the tests.
class NoLauncherDisguise implements LauncherDisguise {
  const NoLauncherDisguise();

  @override
  Future<LauncherCapability> capability() async => LauncherCapability.none;

  @override
  Future<void> apply(CalculatorSkin? skin) async {}
}
