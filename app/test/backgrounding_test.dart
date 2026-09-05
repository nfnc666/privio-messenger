import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/disguise/launcher_disguise.dart';
import 'package:privio/disguise/skin.dart';
import 'package:privio/screens/calculator_screen.dart';
import 'package:privio/widgets/privio_logo.dart';
import 'package:privio/screens/nav_shell.dart';
import 'package:privio/screens/pin_screen.dart';

import 'call_overlay_test.dart' show signedInApp;

/// A launcher that accepts every change, so a test can turn a disguise on
/// without the platform channel the real one waits on.
class _StubLauncher implements LauncherDisguise {
  @override
  Future<LauncherCapability> capability() async =>
      const LauncherCapability(icon: true, name: true);

  @override
  Future<void> apply(CalculatorSkin? skin) async {}
}

/// Sends the app to the background and brings it back, in the order the OS
/// actually reports — Flutter asserts on any other path through these states.
Future<void> backgroundAndReturn(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a device with no screen lock is not locked out by switching apps',
      (tester) async {
    // The lock screen has one way past it and it is the passcode. Arming it on
    // a device that never set one is not a stricter lock, it is a device
    // nobody — including its owner — can get back into.
    final (state, _) = await signedInApp();
    addTearDown(state.conversations.stop);
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    expect(state.stage, AppStage.ready);

    await backgroundAndReturn(tester);

    expect(state.stage, AppStage.ready);
    expect(find.byType(PinScreen), findsNothing);
  });

  testWidgets('a device with a screen lock is locked by switching apps', (tester) async {
    final (state, _) = await signedInApp();
    addTearDown(state.conversations.stop);
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    // Set after launch: the app reads the passcode on the way up, so setting it
    // before would start the app already locked and prove nothing.
    await state.setScreenLock('1234', PasscodeKind.digits4);
    await tester.pump();
    expect(state.stage, AppStage.ready);

    await backgroundAndReturn(tester);

    expect(state.stage, AppStage.locked);
    expect(find.byType(PinScreen), findsOneWidget);
  });

  testWidgets('the open chat is covered before the OS can photograph it', (tester) async {
    // `inactive` is the moment the app switcher takes its thumbnail, and it is
    // the moment a chat has to stop being on screen. Locking here instead would
    // ask for the passcode every time a notification shade is pulled down.
    final (state, _) = await signedInApp();
    addTearDown(state.conversations.stop);
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    await state.setScreenLock('1234', PasscodeKind.digits4);
    await tester.pump();
    expect(find.byType(NavShell), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byKey(PrivacyCover.coverKey), findsOneWidget);
    expect(state.stage, AppStage.ready, reason: 'covered, not locked');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(PrivacyCover.coverKey), findsNothing);
  });

  testWidgets('a disguised device is disguised in the app switcher too', (tester) async {
    // A phone set to open as a calculator, whose switcher thumbnail is a Privio
    // splash, has announced exactly what the disguise was hiding.
    final (state, _) = await signedInApp(launcher: _StubLauncher());
    addTearDown(state.conversations.stop);
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    await state.setScreenLock('1234', PasscodeKind.digits4);
    await state.setDisguise(CalculatorSkin.iphone);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byType(CalculatorScreen), findsOneWidget);
    expect(find.byType(PrivioMark), findsNothing);
  });
}
