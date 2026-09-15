import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_icon.dart';
import 'package:privio/disguise/launcher_disguise.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.privio/launcher');
  const launcher = PlatformLauncherDisguise();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform reaches native capability, changes and reads icons', () async {
      debugDefaultTargetPlatformOverride = platform;
      var current = 'green';
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'capability':
            return {'icon': true, 'name': platform == TargetPlatform.android};
          case 'show':
            current = (call.arguments as Map)['entry'] as String;
            return null;
          case 'current':
            return current;
        }
        throw MissingPluginException();
      });

      final capability = await launcher.capability();
      expect(capability.icon, isTrue);
      expect(capability.name, platform == TargetPlatform.android);
      for (final colour in AppIconColour.values) {
        await launcher.show(LauncherEntry.icon(colour));
        expect(await launcher.current(), LauncherEntry.icon(colour));
      }
      await launcher.show(const LauncherEntry.icon(AppIconColour.green));
      expect(await launcher.current(),
          const LauncherEntry.icon(AppIconColour.green));
      expect(calls.first, 'capability');
      expect(calls.where((method) => method == 'show'), hasLength(9));
    });
  }

  test('iOS preserves a native refusal', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capability') return {'icon': false, 'name': false};
      if (call.method == 'current') return null;
      throw PlatformException(code: 'launcher_failed', message: 'Native refusal');
    });
    expect(await launcher.capability(), LauncherCapability.none);
    expect(await launcher.current(), isNull);
    await expectLater(
      launcher.show(const LauncherEntry.icon(AppIconColour.blue)),
      throwsA(isA<LauncherDisguiseException>()
          .having((error) => error.message, 'message', 'Native refusal')),
    );
  });

  test('an iOS host without the channel remains unavailable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await launcher.capability(), LauncherCapability.none);
    expect(await launcher.current(), isNull);
    await expectLater(
      launcher.show(const LauncherEntry.icon(AppIconColour.blue)),
      throwsA(isA<LauncherDisguiseException>()),
    );
  });
}
