import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/screen_shield_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/security/screen_shield.dart';

/// A platform that can be either kind of phone, without one.
class FakeShield implements ScreenShield {
  FakeShield(this.reports);

  final ScreenShieldCapability reports;

  /// Every value `setProtected` was handed, in order. The list rather than a
  /// bool, because "turned off" has to be distinguishable from "never told".
  final List<bool> applied = <bool>[];

  bool watching = false;
  bool capturing = false;
  int capabilityCalls = 0;

  void Function(bool captured)? _onChanged;

  /// The platform raising a capture, as iOS does when a recording starts.
  void reportCapture(bool on) {
    capturing = on;
    _onChanged?.call(on);
  }

  @override
  Future<ScreenShieldCapability> capability() async {
    capabilityCalls += 1;
    return reports;
  }

  @override
  Future<void> setProtected(bool on) async => applied.add(on);

  @override
  Future<bool> isCaptured() async => capturing;

  @override
  void listen(void Function(bool captured) onChanged) {
    watching = true;
    _onChanged = onChanged;
  }

  @override
  void stopListening() {
    watching = false;
    _onChanged = null;
  }
}

void main() {
  group('what a platform says it can do', () {
    test('Android blocks and does not detect', () {
      expect(ScreenShieldCapability.blocking.blocksCapture, isTrue);
      expect(ScreenShieldCapability.blocking.detectsCapture, isFalse);
      expect(ScreenShieldCapability.blocking.isSupported, isTrue);
    });

    test('iOS detects and does not block', () {
      // The distinction this whole feature rests on. Collapsing these two into
      // one flag is how an app tells an iPhone user their screenshots are
      // blocked when nothing is blocking them.
      expect(ScreenShieldCapability.detecting.blocksCapture, isFalse);
      expect(ScreenShieldCapability.detecting.detectsCapture, isTrue);
      expect(ScreenShieldCapability.detecting.isSupported, isTrue);
    });

    test('a platform with neither is not supported', () {
      expect(ScreenShieldCapability.none.isSupported, isFalse);
    });

    test('an answer the platform did not give reads as nothing', () {
      expect(ScreenShieldCapability.fromJson(null), ScreenShieldCapability.none);
      expect(ScreenShieldCapability.fromJson(const {}), ScreenShieldCapability.none);
    });
  });

  group('turning it on and off', () {
    test('a new account starts off and nothing is protected', () async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, InMemorySecureStore());

      await controller.load('account-a');

      expect(controller.enabled, isFalse);
      expect(shield.applied, [false]);
    });

    test('turning it on tells the platform and stores the answer', () async {
      final store = InMemorySecureStore();
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, store);
      await controller.load('account-a');

      await controller.setEnabled(true);

      expect(controller.enabled, isTrue);
      expect(shield.applied.last, isTrue);
      expect(await store.readScreenShield('account-a'), isTrue);
    });

    test('turning it off clears it rather than merely stopping', () async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);

      await controller.setEnabled(false);

      // The failure this asserts against: a flag left set after the switch goes
      // off, so the system keeps refusing screenshots while the app says it is
      // not protecting anything.
      expect(shield.applied.last, isFalse);
      expect(controller.enabled, isFalse);
    });

    test('setting it to what it already is does nothing', () async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      final before = shield.applied.length;

      await controller.setEnabled(false);

      expect(shield.applied.length, before);
    });
  });

  group('a restart', () {
    test('brings the protection back and applies it', () async {
      final store = InMemorySecureStore();
      final first = ScreenShieldController(FakeShield(ScreenShieldCapability.blocking), store);
      await first.load('account-a');
      await first.setEnabled(true);

      // A new process over the same store, which is what a relaunch is.
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final afterRestart = ScreenShieldController(shield, store);
      await afterRestart.load('account-a');

      expect(afterRestart.enabled, isTrue);
      expect(shield.applied, [true], reason: 'the flag must be set, not just remembered');
    });

    test('a choice is kept even where the device cannot honour it', () async {
      // Stored on a phone that can, read on a phone that cannot. The value is
      // the account's decision, not a record of what one device managed — so it
      // survives, and comes back the next time they are on a device that can.
      final store = InMemorySecureStore();
      final onCapable = ScreenShieldController(
        FakeShield(ScreenShieldCapability.blocking),
        store,
      );
      await onCapable.load('account-a');
      await onCapable.setEnabled(true);

      final onIncapable = ScreenShieldController(FakeShield(ScreenShieldCapability.none), store);
      await onIncapable.load('account-a');

      expect(onIncapable.enabled, isTrue);
      expect(onIncapable.capability.isSupported, isFalse);
      // And it covers nothing, because there is nothing it can do.
      expect(onIncapable.shouldCover, isFalse);
    });
  });

  group('one account does not inherit another', () {
    test('a second account starts from its own answer', () async {
      final store = InMemorySecureStore();
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, store);

      await controller.load('account-a');
      await controller.setEnabled(true);
      expect(controller.enabled, isTrue);

      await controller.load('account-b');

      expect(controller.accountId, 'account-b');
      expect(controller.enabled, isFalse, reason: 'B never asked for this');
      expect(shield.applied.last, isFalse, reason: 'and the flag must be cleared for B');
    });

    test("and going back to the first finds it as they left it", () async {
      final store = InMemorySecureStore();
      final controller = ScreenShieldController(
        FakeShield(ScreenShieldCapability.blocking),
        store,
      );
      await controller.load('account-a');
      await controller.setEnabled(true);
      await controller.load('account-b');
      await controller.load('account-a');

      expect(controller.enabled, isTrue);
    });

    test('signing out clears the protection and forgets the account', () async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);

      await controller.signedOut();

      expect(controller.accountId, isNull);
      expect(controller.enabled, isFalse);
      // A signed-out phone on the welcome screen has nothing to protect, and a
      // flag left set would be a setting the next account never chose.
      expect(shield.applied.last, isFalse);
      expect(shield.watching, isFalse);
    });

    test('a load in flight does not overwrite a choice just made', () async {
      // Signing in starts a read. Somebody who reaches this switch before it
      // finishes would otherwise watch their own answer revert a moment later,
      // because the read returns the value from before they touched it.
      final store = InMemorySecureStore();
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, store);

      final loading = controller.load('account-a');
      await controller.setEnabled(true);
      await loading;

      expect(controller.enabled, isTrue, reason: 'the newer answer must win');
      expect(shield.applied.last, isTrue);
      expect(await store.readScreenShield('account-a'), isTrue);
    });

    test('a load that finishes after a switch does not apply to the new account',
        () async {
      final store = InMemorySecureStore();
      await store.writeScreenShield('account-a', true);
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, store);

      // A starts loading; B arrives before it finishes.
      final loading = controller.load('account-a');
      controller.signedOut(notify: false);
      await loading;

      expect(controller.accountId, isNull);
      expect(controller.enabled, isFalse, reason: "A's setting must not land after they left");
    });
  });

  group('capture detection, on the platform that has it', () {
    test('nothing is watched while the setting is off', () async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');

      expect(shield.watching, isFalse);
      expect(controller.shouldCover, isFalse);
    });

    test('a recording that starts puts the cover up', () async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);
      expect(shield.watching, isTrue);
      expect(controller.shouldCover, isFalse);

      shield.reportCapture(true);

      expect(controller.captured, isTrue);
      expect(controller.shouldCover, isTrue);
    });

    test('and taking it down again when the recording stops', () async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);
      shield.reportCapture(true);

      shield.reportCapture(false);

      expect(controller.shouldCover, isFalse);
    });

    test('a recording already running when the setting goes on is caught', () async {
      // Not hypothetical: somebody who notices a recording is running is
      // exactly the person who then turns this on, and waiting for the *next*
      // change would leave them uncovered for the whole recording.
      final shield = FakeShield(ScreenShieldCapability.detecting)..capturing = true;
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');

      await controller.setEnabled(true);

      expect(controller.shouldCover, isTrue);
    });

    test('turning the setting off during a recording uncovers and stops watching',
        () async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);
      shield.reportCapture(true);
      expect(controller.shouldCover, isTrue);

      await controller.setEnabled(false);

      expect(controller.shouldCover, isFalse);
      expect(shield.watching, isFalse);
    });

    test('a restart with the setting on starts watching again', () async {
      final store = InMemorySecureStore();
      await store.writeScreenShield('account-a', true);
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final controller = ScreenShieldController(shield, store);

      await controller.load('account-a');

      expect(controller.enabled, isTrue);
      expect(shield.watching, isTrue);
    });
  });

  group('Android never covers', () {
    test('a blocking platform reports no capture and puts up no cover', () async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final controller = ScreenShieldController(shield, InMemorySecureStore());
      await controller.load('account-a');
      await controller.setEnabled(true);

      // The mechanism, stated as what it is: nothing is ever watched on a
      // platform that blocks capture, so no capture is ever reported and the
      // cover never goes up. The window manager has already handed the recorder
      // black frames; covering as well would blank the screen for somebody
      // simply using their phone, which is a bug rather than extra safety.
      expect(shield.watching, isFalse);
      expect(controller.shouldCover, isFalse);

      // And a platform that raised one anyway is ignored, because nothing is
      // subscribed to hear it. (`shouldCover` also tests the capability, but
      // that is a second guard — this assertion passes on the listen gate.)
      shield.reportCapture(true);
      expect(controller.captured, isFalse);
      expect(controller.shouldCover, isFalse);
    });
  });

  group('the channel answers honestly when nothing is on the other end', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('a missing platform half is "cannot", not a crash', () async {
      const channel = MethodChannel('app.privio/screen-shield-absent');
      final shield = PlatformScreenShield(channel);

      expect(await shield.capability(), ScreenShieldCapability.none);
      expect(await shield.isCaptured(), isFalse);
      // And asking it to protect anything does not throw.
      await shield.setProtected(true);
    });

    test('a platform that throws is also "cannot"', () async {
      const channel = MethodChannel('app.privio/screen-shield-broken');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final shield = PlatformScreenShield(channel);

      expect(await shield.capability(), ScreenShieldCapability.none);
      expect(await shield.isCaptured(), isFalse);
      await shield.setProtected(true);
    });

    test('the real channel carries what each platform reports', () async {
      const channel = MethodChannel('app.privio/screen-shield-fake');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'capability' => {'blocksCapture': true, 'detectsCapture': false},
          'isCaptured' => false,
          _ => null,
        };
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final shield = PlatformScreenShield(channel);

      expect(await shield.capability(), ScreenShieldCapability.blocking);
      await shield.setProtected(true);

      final set = calls.firstWhere((c) => c.method == 'setProtected');
      expect((set.arguments as Map)['on'], isTrue);
    });
  });
}
