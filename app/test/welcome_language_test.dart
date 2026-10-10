import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/locale_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/welcome_screen.dart';
import 'package:privio/theme/privio_theme.dart';

/// The language somebody picks before they have an account.
///
/// The first screen was English with no way to change it, and an account
/// started in English whatever its owner had wanted. Now the welcome screen
/// offers the five languages, and the one picked there becomes the language
/// of the account created next — and of no account that already has one.
void main() {
  test('a language picked before sign-up becomes the new account\'s', () async {
    final store = InMemorySecureStore();
    final locale = LocaleController(store);

    await locale.choose(AppLanguage.german);
    expect(locale.language, AppLanguage.german, reason: 'the welcome screen changes at once');

    await locale.load('new-account');
    expect(locale.language, AppLanguage.german);
    expect(await store.readLanguage('new-account'), 'de', reason: 'kept with the account');
  });

  test('an account that already has a language keeps it', () async {
    final store = InMemorySecureStore();
    await store.writeLanguage('old-account', 'fr');
    final locale = LocaleController(store);

    await locale.choose(AppLanguage.german);
    await locale.load('old-account');
    expect(locale.language, AppLanguage.french);
    expect(await store.readLanguage('old-account'), 'fr');
  });

  test('signing out forgets a choice the next person did not make', () async {
    final store = InMemorySecureStore();
    final locale = LocaleController(store);

    await locale.choose(AppLanguage.italian);
    locale.signedOut();
    await locale.load('somebody-else');
    expect(locale.language, AppLanguage.fallback);
    expect(await store.readLanguage('somebody-else'), isNull);
  });

  testWidgets('the welcome screen offers every language by its own name, and says which is on',
      (tester) async {
    AppLanguage? chosen;
    var locale = const Locale('en');
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          theme: PrivioTheme.dark(),
          locale: locale,
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: WelcomeScreen(
            onGetStarted: () {},
            onSignIn: () {},
            onImportBackup: () {},
            onLanguageChosen: (language) => setState(() {
              chosen = language;
              locale = language.locale;
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'English'));
    await tester.pumpAndSettle();
    for (final language in AppLanguage.values) {
      expect(find.text(language.endonym), findsWidgets);
    }
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();
    expect(chosen, AppLanguage.german);
    expect(find.text('Willkommen bei'), findsOneWidget, reason: 'the screen changed at once');
    expect(
      find.widgetWithText(TextButton, 'Deutsch'),
      findsOneWidget,
      reason: 'and the button names the language now on screen, not the one before',
    );
  });

  testWidgets('a small phone with large text still reaches every button', (tester) async {
    // An iPhone SE's screen at a large text size: the column of promises and
    // buttons is taller than the screen, so it scrolls instead of cutting off
    // the last buttons.
    tester.view.physicalSize = const Size(320 * 2, 568 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: WelcomeScreen(
            onGetStarted: () {},
            onSignIn: () {},
            onImportBackup: () {},
              onLanguageChosen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'it overflowed');
    await tester.scrollUntilVisible(find.text('Import from backup'), 100);
    expect(find.text('Import from backup').hitTestable(), findsOneWidget);
  });
}
