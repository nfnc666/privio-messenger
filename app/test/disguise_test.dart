import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/disguise/calculator.dart';
import 'package:privio/disguise/skin.dart';
import 'package:privio/screens/calculator_screen.dart';
import 'package:privio/screens/pin_screen.dart';

import 'duress_test.dart' show Device, armedDevice;

/// Presses a key on the rendered pad by its label.
Future<void> tapKey(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(InkWell, label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> typeCode(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await tapKey(tester, digit);
  }
}

void main() {
  group('the disguise', () {
    test('cannot be switched on without a numeric lock', () async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      expect(device.state.disguiseAvailable, isTrue, reason: 'a 4-digit lock is set');

      await device.state.setDisguise(CalculatorSkin.iphone);
      expect(device.state.disguise, CalculatorSkin.iphone);

      // A passphrase cannot be typed on a keypad with no letters.
      await device.state.setScreenLock('correct horse', PasscodeKind.phrase);
      expect(device.state.disguiseAvailable, isFalse);
      await device.state.setDisguise(CalculatorSkin.samsung);
      expect(
        device.state.disguise,
        CalculatorSkin.iphone,
        reason: 'the setting refuses rather than storing something unusable',
      );
    });

    test('turning the lock off takes the disguise with it', () async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.iphone);

      await device.state.clearScreenLock();
      expect(device.state.disguise, isNull, reason: 'a calculator nobody can pass is a lockout');
      expect(device.state.disguiseAvailable, isFalse);
    });

    test('a wipe does not leave the disguise behind', () async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.samsung);

      expect(await device.state.unlockWithPasscode('9119'), isFalse, reason: 'the duress code');
      expect(device.state.disguise, isNull);
    });

    test('it survives a relaunch, because the lock screen has to', () async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.samsung);

      final again = Device(server: device.server, store: device.store, archive: device.archive);
      await again.boot();
      addTearDown(again.state.conversations.stop);
      expect(again.state.stage, AppStage.locked);
      expect(again.state.disguise, CalculatorSkin.samsung);
    });
  });

  group('the disguise on screen', () {
    testWidgets('a locked device shows the calculator instead of the PIN pad', (tester) async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.iphone);

      await tester.pumpWidget(PrivioApp(state: device.state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.byType(PinScreen), findsNothing);
      expect(
        find.textContaining('Privio'),
        findsNothing,
        reason: 'nothing on this screen is worth asking about',
      );
    });

    testWidgets('the passcode and equals opens Privio', (tester) async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.iphone);

      await tester.pumpWidget(PrivioApp(state: device.state));
      await tester.pump(const Duration(seconds: 1));

      await typeCode(tester, '1234');
      expect(find.text('1,234'), findsOneWidget, reason: 'it looks like arithmetic');

      await tapKey(tester, '=');
      await tester.pump(const Duration(milliseconds: 400));
      expect(device.state.stage, AppStage.ready);
    });

    testWidgets('a wrong code just does arithmetic', (tester) async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.iphone);

      await tester.pumpWidget(PrivioApp(state: device.state));
      await tester.pump(const Duration(seconds: 1));

      await typeCode(tester, '12');
      await tapKey(tester, '+');
      await typeCode(tester, '30');
      await tapKey(tester, '=');
      await tester.pump(const Duration(milliseconds: 400));

      expect(device.state.stage, AppStage.locked);
      expect(find.text('42'), findsOneWidget, reason: 'no shake, no counter, no tell');
      expect(find.byType(CalculatorScreen), findsOneWidget);
    });

    testWidgets('the duress code typed into the calculator still wipes', (tester) async {
      final device = await armedDevice();
      addTearDown(device.state.conversations.stop);
      await device.state.setDisguise(CalculatorSkin.iphone);
      expect(device.archive.conversations(), isNotEmpty);

      await tester.pumpWidget(PrivioApp(state: device.state));
      await tester.pump(const Duration(seconds: 1));

      await typeCode(tester, '9119');
      await tapKey(tester, '=');
      await tester.pump(const Duration(milliseconds: 400));

      expect(device.archive.conversations(), isEmpty, reason: 'the history is gone');
      expect(device.server.wipeAttempts, contains('9119'));
      expect(
        device.state.stage,
        isNot(AppStage.ready),
        reason: 'the duress code never opens anything',
      );
    });

    testWidgets('both skins draw a full pad', (tester) async {
      for (final skin in CalculatorSkin.values) {
        await tester.pumpWidget(MaterialApp(home: CalculatorScreen(skin: skin)));
        await tester.pump();
        for (final key in CalculatorKey.values) {
          expect(
            find.text(key.label),
            findsWidgets,
            reason: '${skin.label} is missing ${key.label}',
          );
        }
      }
    });
  });
}
