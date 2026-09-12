import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/app.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/locale_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/language_screen.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/settings_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/message_bubble.dart';
import 'package:privio/widgets/privio_back_button.dart';

import 'support/fake_voice.dart';

/// A server that signs anybody in and answers everything else emptily.
///
/// The account id it hands back is derived from the username, because the whole
/// point of these tests is which account a stored preference belongs to.
http.Client _server() => MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final username = body['username'] as String;
        return http.Response(
          jsonEncode({
            'token': 'token-$username',
            'accountId': 'acc-$username',
            'username': username,
            'deviceId': 'device-1',
          }),
          path == '/v1/accounts' ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Everything a sign-in kicks off in the background gets a plausible
      // answer. Left to 404 they throw out of detached futures, and the test
      // fails on a prekey count rather than on anything about language.
      if (path == '/v1/keys/count') {
        return http.Response(
          jsonEncode(const {'remaining': 50}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/v1/accounts/me') {
        return http.Response(
          jsonEncode(const {'accountId': 'acc', 'username': 'x', 'avatarMediaId': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

Future<PrivioServices> _services() async {
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: _server());
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  return PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    backup: BackupService(
      api: api,
      store: InMemorySecureStore(),
      messages: InMemoryMessageStore(),
    ),
    store: InMemoryMessageStore(),
    secureStore: InMemorySecureStore(),
  );
}

/// A fresh app over a store the test keeps a handle on.
///
/// The store is the point: a "restart" here is a second [AppState] over the
/// *same* store, which is what a relaunch actually is. A helper that made a new
/// store each time would prove persistence by never testing it.
Future<AppState> _appOver(SecureStore store) async {
  final state = AppState(services: await _services(), store: store);
  await state.initialise();
  return state;
}

Widget _wrap(Widget child, AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, state.locale]),
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          locale: state.locale.locale,
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: child,
        ),
      ),
    );

/// Lets the work a sign-in starts in the background actually run.
///
/// A widget test's clock does not, so a detached future that outlives the state
/// it belongs to comes back to a disposed controller and fails the test on
/// something it was not about.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every language has a name only its own speakers need to read', () {
    expect(
      AppLanguage.values.map((language) => language.endonym),
      ['English', 'Deutsch', 'Español', 'Français', 'Italiano'],
    );
    // The generated class has to support exactly what the enum offers.
    // A language in the picker with no ARB behind it falls back to English
    // silently, which is the one failure nobody would notice.
    final supported = AppText.supportedLocales.map((locale) => locale.languageCode).toSet();
    for (final language in AppLanguage.values) {
      expect(supported, contains(language.code), reason: '${language.endonym} has no translations');
    }
  });

  testWidgets('all five languages render their own words', (tester) async {
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    addTearDown(state.dispose);

    // What each one must be showing, in its own language. The title is on the
    // screen and the note underneath it, so a language that silently fell back
    // to English fails here rather than passing on a shared word.
    const expected = {
      AppLanguage.english: 'Language',
      AppLanguage.german: 'Sprache',
      AppLanguage.spanish: 'Idioma',
      AppLanguage.french: 'Langue',
      AppLanguage.italian: 'Lingua',
    };

    await tester.pumpWidget(_wrap(const LanguageScreen(), state));
    for (final entry in expected.entries) {
      state.locale.choose(entry.key);
      await tester.pumpAndSettle();
      expect(
        find.text(entry.value),
        findsWidgets,
        reason: '${entry.key.endonym} did not reach the screen',
      );
      // And the endonyms are never translated: the list is the same five words
      // whatever the app is set to.
      for (final language in AppLanguage.values) {
        expect(find.text(language.endonym), findsOneWidget);
      }
    }
  });

  testWidgets('picking a language changes the screen already open', (tester) async {
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(const LanguageScreen(), state));

    expect(find.text('Language'), findsWidgets);
    expect(find.text('Sprache'), findsNothing);

    // The gesture, not the controller: this is the thing that was meant to
    // work, and pressing it is the only way to know the row is wired.
    await tester.tap(find.byKey(const ValueKey('language-de')));
    await tester.pumpAndSettle();

    // No restart, no sign-in, no second pumpWidget — the same screen, now in
    // German.
    expect(find.text('Sprache'), findsWidgets);
    expect(state.locale.language, AppLanguage.german);
  });

  testWidgets('the settings row opens the picker and names the current language',
      (tester) async {
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(const SettingsScreen(), state));

    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language-it')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrivioBackButton));
    await tester.pumpAndSettle();

    // The row underneath came back in Italian, and says so in Italian.
    expect(find.text('Lingua'), findsOneWidget);
    expect(find.text('Italiano'), findsOneWidget);
  });

  testWidgets('a choice survives a restart', (tester) async {
    final store = InMemorySecureStore();
    final first = await tester.runAsync(() => _appOver(store)) as AppState;
    await tester.runAsync(() => first.register(username: 'anna', password: 'pw-anna-1'));
    await tester.runAsync(() => first.locale.choose(AppLanguage.french));
    expect(first.locale.language, AppLanguage.french);
    await _settle(tester);
    first.dispose();

    // The relaunch: a new AppState over the same store, signing back in.
    final second = await tester.runAsync(() => _appOver(store)) as AppState;
    addTearDown(second.dispose);
    await tester.runAsync(() => second.signIn(username: 'anna', password: 'pw-anna-1'));
    await _settle(tester);
    expect(second.locale.language, AppLanguage.french);
  });

  testWidgets('a second account does not inherit the first one\'s language',
      (tester) async {
    final store = InMemorySecureStore();
    final state = await tester.runAsync(() => _appOver(store)) as AppState;
    addTearDown(state.dispose);

    await tester.runAsync(() => state.register(username: 'anna', password: 'pw-anna-1'));
    await _settle(tester);
    await tester.runAsync(() => state.locale.choose(AppLanguage.spanish));
    expect(state.locale.language, AppLanguage.spanish);

    // Signing out takes the whole store with it, so there is nothing for the
    // next account to pick up — and the sign-in screen is English again.
    await tester.runAsync(state.signOut);
    expect(state.locale.language, AppLanguage.english);

    await tester.runAsync(() => state.register(username: 'bruno', password: 'pw-bruno-1'));
    await _settle(tester);
    expect(
      state.locale.language,
      AppLanguage.english,
      reason: 'a new account started in the previous one\'s language',
    );
  });

  testWidgets('a system notice is drawn in the reader\'s language, not the writer\'s',
      (tester) async {
    // What the writer's app put in `body` — English, because that is what it
    // was set to. Nothing here may end up on screen for a German reader.
    final message = Message(
      id: 'notice-1',
      body: 'Anna set disappearing messages to 1 hour.',
      sentAt: DateTime(2026, 3, 4, 9),
      isMine: false,
      kind: MessageKind.notice,
      notice: const SystemNotice(
        NoticeKind.timerSet,
        who: 'Anna',
        duration: Duration(hours: 1),
      ),
    );

    Future<void> show(Locale locale) => tester.pumpWidget(
          MaterialApp(
            theme: PrivioTheme.dark(),
            locale: locale,
            localizationsDelegates: AppText.localizationsDelegates,
            supportedLocales: AppText.supportedLocales,
            home: Scaffold(body: MessageBubble(message: message)),
          ),
        );

    await show(const Locale('en'));
    expect(find.text('Anna set disappearing messages to 1 hour'), findsOneWidget);

    await show(const Locale('de'));
    expect(
      find.text('Anna hat selbstlöschende Nachrichten auf 1 Stunde gesetzt'),
      findsOneWidget,
    );
    expect(
      find.text('Anna set disappearing messages to 1 hour.'),
      findsNothing,
      reason: 'the sentence the writer stored reached a reader who cannot read it',
    );

    await show(const Locale('fr'));
    expect(
      find.text('Anna a réglé les messages éphémères sur 1 heure'),
      findsOneWidget,
    );
  });

  testWidgets('a notice with no event behind it still shows its stored sentence',
      (tester) async {
    // Filed before notices recorded what they were about. There is nothing to
    // build a sentence from, so the one it was written with is what it gets —
    // in the language it was written in, which is the honest best available.
    final old = Message(
      id: 'notice-old',
      body: 'You turned disappearing messages off.',
      sentAt: DateTime(2026),
      isMine: true,
      kind: MessageKind.notice,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        locale: const Locale('it'),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(body: MessageBubble(message: old)),
      ),
    );
    expect(find.text('You turned disappearing messages off.'), findsOneWidget);
  });

  test('the event behind a notice survives being archived', () {
    const notice = SystemNotice(
      NoticeKind.unreadable,
      who: 'Bruno',
      count: 3,
    );
    final back = SystemNotice.fromJson(notice.toJson());
    expect(back, isNotNull);
    expect(back!.kind, NoticeKind.unreadable);
    expect(back.who, 'Bruno');
    expect(back.count, 3);

    // A kind this build has never heard of is not a crash and not a blank
    // line: the stored sentence is still there to fall back on.
    expect(SystemNotice.fromJson(const {'kind': 'somethingNewer'}), isNull);
  });

  testWidgets('the app itself is built in the account\'s language', (tester) async {
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().locale, const Locale('en'));

    state.locale.choose(AppLanguage.german);
    await tester.pumpAndSettle();
    expect(app().locale, const Locale('de'));
  });
}
