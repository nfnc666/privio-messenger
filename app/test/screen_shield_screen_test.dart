import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/app.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/privacy_screen.dart';
import 'package:privio/security/screen_shield.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_theme.dart';

import 'screen_shield_test.dart' show FakeShield;
import 'support/fake_voice.dart';

http.Client _server() => MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
        final username = (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
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
      if (path == '/v1/keys/count') {
        return http.Response(
          jsonEncode(const {'remaining': 50}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/v1/accounts/me') {
        return http.Response(
          jsonEncode(const {
            'accountId': 'acc',
            'username': 'x',
            'avatarMediaId': null,
            'privacy': <String, dynamic>{},
            'twoFactorEnabled': false,
            'duressCodeSet': false,
          }),
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

Future<AppState> _appOver(SecureStore store, FakeShield shield) async {
  final state = AppState(services: await _services(), store: store, screenShield: shield);
  await state.initialise();
  return state;
}

Widget _privacyOver(AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, state.screenShield]),
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const PrivacyScreen(),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _scrollToShield(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('screen-shield')),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  testWidgets('Android is told screenshots are blocked', (tester) async {
    final shield = FakeShield(ScreenShieldCapability.blocking);
    final state =
        await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_privacyOver(state));
    await _settle(tester);
    await _scrollToShield(tester);

    expect(find.text('Screen protection'), findsOneWidget);
    expect(
      find.text('Blocks screenshots and screen recordings of the app.'),
      findsOneWidget,
    );
    // And it must not be told the iOS sentence.
    expect(find.textContaining('cannot be reliably prevented'), findsNothing);
  });

  testWidgets('iOS is told screenshots cannot be prevented', (tester) async {
    final shield = FakeShield(ScreenShieldCapability.detecting);
    final state =
        await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_privacyOver(state));
    await _settle(tester);
    await _scrollToShield(tester);

    // The honest sentence, and specifically not a claim to block anything.
    expect(find.textContaining('Screenshots cannot be reliably prevented on iOS'),
        findsOneWidget);
    expect(find.textContaining('Blocks screenshots'), findsNothing);
  });

  testWidgets('a device that can do neither says so and the switch is dead',
      (tester) async {
    final shield = FakeShield(ScreenShieldCapability.none);
    final state =
        await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_privacyOver(state));
    await _settle(tester);
    await _scrollToShield(tester);

    expect(find.text('This device cannot protect the screen.'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byKey(const ValueKey('screen-shield')));
    expect(toggle.onChanged, isNull, reason: 'a switch that cannot do anything must not invite a tap');
  });

  testWidgets('the switch reaches the platform', (tester) async {
    final shield = FakeShield(ScreenShieldCapability.blocking);
    final state =
        await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_privacyOver(state));
    await _settle(tester);
    await _scrollToShield(tester);

    await tester.tap(find.byKey(const ValueKey('screen-shield')));
    await _settle(tester);

    expect(shield.applied.last, isTrue);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('screen-shield'))).value, isTrue);
  });

  testWidgets('the scope note is on the screen where the switch is', (tester) async {
    final shield = FakeShield(ScreenShieldCapability.blocking);
    final state =
        await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_privacyOver(state));
    await _settle(tester);

    // The thing a switch called "Screen protection" invites somebody to believe,
    // said before they believe it.
    await tester.scrollUntilVisible(
      find.textContaining('protects your own device only'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('protects your own device only'), findsOneWidget);
  });

  testWidgets('every language has all six strings', (tester) async {
    for (final locale in AppText.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: Builder(
            builder: (context) {
              final text = AppText.of(context);
              for (final value in [
                text.privacyScreenShield,
                text.privacyScreenShieldAndroid,
                text.privacyScreenShieldIos,
                text.privacyScreenShieldUnavailable,
                text.privacyScreenShieldScope,
                text.privacyScreenShieldCovering,
              ]) {
                expect(value, isNotEmpty, reason: '$locale');
              }
              // The iOS sentence has to carry the caveat in every language, not
              // only in the one it was written in.
              expect(
                text.privacyScreenShieldIos.length,
                greaterThan(60),
                reason: '$locale: the iOS caveat looks truncated',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
    }
  });

  group('the cover', () {
    Widget hostOver(AppState state) => PrivioScope(
          notifier: state,
          child: ListenableBuilder(
            listenable: Listenable.merge([state, state.screenShield]),
            builder: (context, _) => MaterialApp(
              theme: PrivioTheme.dark(accent: AppAccent.purple),
              localizationsDelegates: AppText.localizationsDelegates,
              supportedLocales: AppText.supportedLocales,
              home: Builder(
                builder: (context) => PrivacyCover(
                  hidden: state.screenShield.shouldCover,
                  child: const Scaffold(body: Center(child: Text('a private conversation'))),
                ),
              ),
            ),
          ),
        );

    testWidgets('goes up while a recording runs and comes down after', (tester) async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final state =
          await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
      await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
      addTearDown(state.conversations.stop);
      await tester.runAsync(() => state.screenShield.setEnabled(true));

      await tester.pumpWidget(hostOver(state));
      await _settle(tester);
      expect(find.byKey(PrivacyCover.coverKey), findsNothing);

      shield.reportCapture(true);
      await tester.pump();

      expect(find.byKey(PrivacyCover.coverKey), findsOneWidget);
      // The reason, so a person looking at their own covered phone does not
      // think the app has broken.
      expect(find.textContaining('A screen recording is running'), findsOneWidget);

      shield.reportCapture(false);
      await tester.pump();
      expect(find.byKey(PrivacyCover.coverKey), findsNothing);
      expect(find.text('a private conversation'), findsOneWidget);
    });

    testWidgets('does not go up on Android, which has nothing to hide from',
        (tester) async {
      final shield = FakeShield(ScreenShieldCapability.blocking);
      final state =
          await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
      await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
      addTearDown(state.conversations.stop);
      await tester.runAsync(() => state.screenShield.setEnabled(true));

      await tester.pumpWidget(hostOver(state));
      await _settle(tester);
      shield.reportCapture(true);
      await tester.pump();

      expect(find.byKey(PrivacyCover.coverKey), findsNothing);
      expect(find.text('a private conversation'), findsOneWidget);
    });

    testWidgets('does not go up for an account that never asked', (tester) async {
      final shield = FakeShield(ScreenShieldCapability.detecting);
      final state =
          await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
      await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(hostOver(state));
      await _settle(tester);
      shield.reportCapture(true);
      await tester.pump();

      expect(find.byKey(PrivacyCover.coverKey), findsNothing);
    });

    testWidgets('the app-switcher cover is unrelated and covers regardless',
        (tester) async {
      // The background cover predates this setting and must not start depending
      // on it: every account on every platform gets it, switch or no switch.
      final shield = FakeShield(ScreenShieldCapability.none);
      final state =
          await tester.runAsync(() => _appOver(InMemorySecureStore(), shield)) as AppState;
      await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        PrivioScope(
          notifier: state,
          child: MaterialApp(
            theme: PrivioTheme.dark(),
            localizationsDelegates: AppText.localizationsDelegates,
            supportedLocales: AppText.supportedLocales,
            home: const PrivacyCover(
              hidden: true,
              child: Scaffold(body: Center(child: Text('a private conversation'))),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byKey(PrivacyCover.coverKey), findsOneWidget);
      // And it says nothing about recordings, because none is running — that
      // caption belongs only to the capture case.
      expect(find.textContaining('A screen recording is running'), findsNothing);
    });
  });
}
