import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/phone_number.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/phone_field.dart';

/// The field itself.
///
/// The rule under test everywhere here: **an empty field is a complete answer.**
/// Nothing in this widget can refuse, block or fill itself in, because an
/// account without a phone number is an account.

Widget _host(Widget child) => MaterialApp(
      theme: PrivioTheme.dark(),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('is labelled optional, and says so in the explanation too',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(PhoneField(controller: controller)));

    expect(find.text('Phone number (optional)'), findsWidgets);
  });

  testWidgets('starts empty — the device s own number is never filled in',
      (tester) async {
    // Filling from the SIM would attach somebody to a number they were not
    // asked about, and on a dual-SIM phone it would often be the wrong one.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final key = GlobalKey<PhoneFieldState>();
    await tester.pumpWidget(_host(PhoneField(key: key, controller: controller)));

    expect(controller.text, isEmpty);
    expect(key.currentState!.isEmpty, isTrue);
    expect(key.currentState!.value, isNull);
  });

  testWidgets('an empty field yields nothing to send, and is not an error',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final key = GlobalKey<PhoneFieldState>();
    await tester.pumpWidget(_host(PhoneField(key: key, controller: controller)));

    expect(key.currentState!.value, isNull);
    // No error text anywhere: there is nothing wrong with leaving it blank.
    expect(find.textContaining('not a phone number'), findsNothing);
  });

  testWidgets('a typed number becomes E.164 with the chosen country',
      (tester) async {
    final controller = TextEditingController(text: '151 23456789');
    addTearDown(controller.dispose);
    final key = GlobalKey<PhoneFieldState>();
    await tester.pumpWidget(_host(PhoneField(key: key, controller: controller)));

    // The default country is the first offered, +49.
    expect(key.currentState!.value?.e164, '+4915123456789');
  });

  testWidgets('the country can be changed, and the number follows it',
      (tester) async {
    final controller = TextEditingController(text: '2021234567');
    addTearDown(controller.dispose);
    final key = GlobalKey<PhoneFieldState>();
    await tester.pumpWidget(_host(PhoneField(key: key, controller: controller)));

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USA / Canada'));
    await tester.pumpAndSettle();

    expect(key.currentState!.value?.e164, '+12021234567');
  });

  testWidgets('nonsense yields nothing rather than an exception', (tester) async {
    final controller = TextEditingController(text: '12');
    addTearDown(controller.dispose);
    final key = GlobalKey<PhoneFieldState>();
    await tester.pumpWidget(_host(PhoneField(key: key, controller: controller)));

    expect(key.currentState!.value, isNull);
    expect(key.currentState!.isEmpty, isFalse, reason: 'something was typed');
    expect(tester.takeException(), isNull);
  });

  test('the field and the controller agree on what a number is', () {
    // The field builds "+<code><local>" and hands it to the same normaliser the
    // controller uses before blinding, so there is one definition of a number.
    expect(PhoneNumbers.normalise('+49151 23456789')?.e164, '+4915123456789');
  });
}
