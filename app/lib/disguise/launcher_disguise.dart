import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'skin.dart';

/// What the platform underneath can actually change about the launcher entry.
///
/// Not a boolean, because the two platforms differ in a way people need told:
/// Android can change both the icon and the name; iOS can change the icon and
/// **cannot** change the name — an app's display name is fixed at build time
/// and there is no public API for it. Saying "the app becomes a calculator" on
/// a phone where the name stays "Privio" would be the app lying about its own
/// disguise.
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

  @override
  Future<LauncherCapability> capability() async {
    if (kIsWeb) return LauncherCapability.none;
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
    if (kIsWeb) return;
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
