import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_icon.dart';

/// What the platform underneath can actually change about the launcher entry.
///
/// Not a boolean, because a platform can manage one and not the other. Android
/// changes both through launcher aliases. iOS supports alternate icons but
/// cannot change the name. The native capability keeps icon colours available
/// while the separate disguise policy keeps calculator disguise Android-only.
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

  /// Shows [entry] — the calculator, or the icon in a given colour.
  ///
  /// One method for both, because the home screen has one slot and two
  /// features that want it. The caller resolves which wins (see
  /// [LauncherEntry]); the platform is handed the answer rather than the
  /// question.
  ///
  /// Throws [LauncherDisguiseException] when the platform refuses. Worth
  /// surfacing rather than swallowing: somebody who changed this has been told
  /// their icon will change, and an icon that did not change is a promise
  /// broken quietly.
  Future<void> show(LauncherEntry entry);

  /// What the launcher is *actually* showing, read from the platform.
  ///
  /// Null when it cannot be read. The settings screen reconciles against this
  /// on open rather than trusting what was stored: a stored value is what this
  /// app last asked for, and the two can part company — a failed change, a
  /// restored backup, a manufacturer build that took the call and did nothing.
  Future<LauncherEntry?> current();
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
  Future<void> show(LauncherEntry entry) async {
    if (kIsWeb) {
      throw const LauncherDisguiseException('This platform cannot change the app icon.');
    }
    try {
      await _channel.invokeMethod<void>('show', {'entry': entry.wireName});
    } on PlatformException catch (failure) {
      throw LauncherDisguiseException(failure.message ?? 'The launcher refused the change.');
    } on MissingPluginException {
      throw const LauncherDisguiseException('This device cannot change the app icon.');
    }
  }

  @override
  Future<LauncherEntry?> current() async {
    if (kIsWeb) return null;
    try {
      return LauncherEntry.forWireName(await _channel.invokeMethod<String>('current'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Does nothing, and says so. The web build and the tests.
class NoLauncherDisguise implements LauncherDisguise {
  const NoLauncherDisguise();

  @override
  Future<LauncherCapability> capability() async => LauncherCapability.none;

  @override
  Future<void> show(LauncherEntry entry) async =>
      throw const LauncherDisguiseException('This platform cannot change the app icon.');

  @override
  Future<LauncherEntry?> current() async => null;
}
