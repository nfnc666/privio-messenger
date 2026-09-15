import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a platform can actually do about somebody photographing the screen.
///
/// Two capabilities rather than one switch, because Android and iOS do
/// genuinely different things and the difference is the whole honesty of this
/// feature. Collapsing them into "protected: yes" is how an app ends up telling
/// an iPhone user that screenshots are blocked when they are not.
@immutable
class ScreenShieldCapability {
  const ScreenShieldCapability({required this.blocksCapture, required this.detectsCapture});

  /// Nothing at all. The web build, a desktop build, or a platform half that is
  /// not there — and a phone that answers this is not lied about, it is told.
  static const ScreenShieldCapability none =
      ScreenShieldCapability(blocksCapture: false, detectsCapture: false);

  /// Android: the window manager refuses the screenshot and blanks the recorder.
  static const ScreenShieldCapability blocking =
      ScreenShieldCapability(blocksCapture: true, detectsCapture: false);

  /// iOS: nothing can stop a screenshot, but a recording or a mirrored display
  /// is observable while it is happening.
  static const ScreenShieldCapability detecting =
      ScreenShieldCapability(blocksCapture: false, detectsCapture: true);

  /// Whether the operating system will refuse a screenshot and a recording
  /// outright. Android only, and only through `FLAG_SECURE`.
  final bool blocksCapture;

  /// Whether the app is told that a recording or a mirrored display is running,
  /// so it can cover what is on screen for as long as it lasts. iOS only.
  final bool detectsCapture;

  /// Whether offering the switch means anything on this device.
  bool get isSupported => blocksCapture || detectsCapture;

  static ScreenShieldCapability fromJson(Map<Object?, Object?>? json) {
    if (json == null) return none;
    return ScreenShieldCapability(
      blocksCapture: json['blocksCapture'] as bool? ?? false,
      detectsCapture: json['detectsCapture'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenShieldCapability &&
      other.blocksCapture == blocksCapture &&
      other.detectsCapture == detectsCapture;

  @override
  int get hashCode => Object.hash(blocksCapture, detectsCapture);
}

/// The platform's side of screen protection, behind an interface.
///
/// The same reason the keystore, the microphone and the launcher are ones: none
/// of this can be exercised without a phone otherwise, and "does turning the
/// switch off actually clear the flag" is exactly the kind of thing that is
/// never checked until somebody notices their screenshots still fail.
abstract interface class ScreenShield {
  /// What this device can do. Asked once when the settings screen opens and
  /// once at sign-in; never assumed from the build's edition.
  Future<ScreenShieldCapability> capability();

  /// Turns the protection on or off.
  ///
  /// On Android this adds or clears `FLAG_SECURE`. On iOS it starts or stops
  /// observing the capture state — there is nothing to set.
  Future<void> setProtected(bool on);

  /// Whether a recording or a mirrored display is running **right now**.
  ///
  /// Always false where [ScreenShieldCapability.detectsCapture] is false; there
  /// is nothing to report on a platform that blocks capture outright, because
  /// there is never a capture to report.
  Future<bool> isCaptured();

  /// Called when the capture state changes. iOS only.
  void listen(void Function(bool captured) onChanged);

  void stopListening();
}

/// What a build with no platform half reports: a device that cannot do this.
///
/// Not a stub standing in for something finished elsewhere. A web build really
/// cannot stop a screenshot, and the honest answer is the same one.
class NoScreenShield implements ScreenShield {
  const NoScreenShield();

  @override
  Future<ScreenShieldCapability> capability() async => ScreenShieldCapability.none;

  @override
  Future<void> setProtected(bool on) async {}

  @override
  Future<bool> isCaptured() async => false;

  @override
  void listen(void Function(bool captured) onChanged) {}

  @override
  void stopListening() {}
}

/// Talks to Kotlin on Android and Swift on iOS.
///
/// A missing channel reads as "this device cannot do this" rather than as a
/// crash, the same way the launcher and the notification permission do: a build
/// whose native half is absent is in the same position as a platform that has
/// no such feature, and the app says so either way instead of falling over.
class PlatformScreenShield implements ScreenShield {
  PlatformScreenShield([
    this._channel = const MethodChannel('app.privio/screen-shield'),
  ]);

  final MethodChannel _channel;
  void Function(bool captured)? _onChanged;

  @override
  Future<ScreenShieldCapability> capability() async {
    if (kIsWeb) return ScreenShieldCapability.none;
    try {
      final answer = await _channel.invokeMapMethod<String, dynamic>('capability');
      return ScreenShieldCapability.fromJson(answer);
    } on Object {
      // Deliberately every error, not only the two channel ones.
      //
      // This is asked during start-up, and "I could not ask the platform" and
      // "the platform said no" mean the same thing to everything above: this
      // device cannot protect the screen. A throw here would take down the
      // launch of an app that works perfectly well without this setting —
      // which is what happened when `initialise` first awaited it and every
      // test without a Flutter binding stopped booting.
      return ScreenShieldCapability.none;
    }
  }

  @override
  Future<void> setProtected(bool on) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setProtected', {'on': on});
    } on Object {
      // Nothing on the other end, a window manager that refused the flag, or no
      // binding to reach it through. The switch already knows this device may
      // not be able to — `capability` said so — and none of these is a reason
      // to crash. The device limitations are in `docs/screen-protection.md`.
    }
  }

  @override
  Future<bool> isCaptured() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('isCaptured') ?? false;
    } on Object {
      // Same reasoning: unable to ask is not "yes".
      return false;
    }
  }

  @override
  void listen(void Function(bool captured) onChanged) {
    _onChanged = onChanged;
    _subscribe(_handle);
  }

  @override
  void stopListening() {
    _onChanged = null;
    _subscribe(null);
  }

  /// Attaches or detaches the incoming handler, tolerating a channel that
  /// cannot be reached.
  ///
  /// `setMethodCallHandler` **asserts** when there is no binary messenger — it
  /// does not throw a `MissingPluginException` — so it fails on a platform
  /// half that is absent for a quite different reason than the calls above,
  /// and has to be guarded separately. Swallowing it is right for the same
  /// reason: if there is nothing to listen to, there is nothing to hear, and
  /// that is not a crash.
  void _subscribe(Future<void> Function(MethodCall)? handler) {
    if (kIsWeb) return;
    try {
      _channel.setMethodCallHandler(handler);
    } on Object {
      // Nothing to subscribe to.
    }
  }

  /// Exposed so the incoming direction can be driven without a device.
  Future<void> _handle(MethodCall call) async {
    if (call.method != 'capturedChanged') return;
    final captured = call.arguments;
    if (captured is bool) _onChanged?.call(captured);
  }
}
