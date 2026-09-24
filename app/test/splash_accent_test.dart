import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/accent_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/splash_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/privio_logo.dart';

import 'support/fake_voice.dart';

/// The loading screen in the account's colour.
///
/// Two halves, and the second is the one that is easy to get wrong: drawing the
/// splash from the theme is a handful of lines, and having the *right* colour
/// on the very first frame is a question about when the preference is read.

http.Client _server() => MockClient((request) async => http.Response(
      jsonEncode(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []}),
      200,
      headers: {'content-type': 'application/json'},
    ));

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

/// The splash under the same arrangement `app.dart` builds: a theme rebuilt
/// from the accent controller. A test that themed it by hand would be testing
/// its own wiring.
Widget _splashOver(AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, state.accent]),
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(accent: state.accent.accent),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const SplashScreen(),
        ),
      ),
    );

/// What the lock-up's symbol is painted in.
///
/// Read off the filter rather than off a screenshot: `ColorFilter.mode` compares
/// by value, so this is the exact colour without a golden file to re-bless
/// every time the artwork is re-cut.
Color _symbolColour(WidgetTester tester) {
  final filtered = tester.widgetList<ColorFiltered>(
    find.descendant(of: find.byType(PrivioWordmark), matching: find.byType(ColorFiltered)),
  );
  expect(filtered, hasLength(1), reason: 'the word is white; only the symbol is tinted');
  for (final accent in AppAccent.values) {
    if (filtered.single.colorFilter == ColorFilter.mode(accent.seed, BlendMode.srcIn)) {
      return accent.seed;
    }
  }
  fail('the symbol is not painted in any offered accent');
}

void main() {
  group('the loading screen wears the account colour', () {
    for (final accent in AppAccent.values) {
      testWidgets('${accent.code}: symbol and tagline', (tester) async {
        final store = InMemorySecureStore();
        final state = AppState(services: await _services(), store: store);
        addTearDown(state.dispose);
        await state.accent.choose(accent);

        await tester.pumpWidget(_splashOver(state));
        await tester.pump(const Duration(milliseconds: 50));

        expect(_symbolColour(tester), accent.seed);
        final tagline = tester.widget<Text>(
          find.text(await _tagline(tester)),
        );
        expect(tagline.style?.color, accent.seed);
      });
    }

    testWidgets('and the black behind it stays black', (tester) async {
      // The one colour that does not follow the accent. A splash that tinted
      // its background would be a different app per colour rather than the
      // same app in a colour.
      final store = InMemorySecureStore();
      final state = AppState(services: await _services(), store: store);
      addTearDown(state.dispose);
      await state.accent.choose(AppAccent.pink);

      await tester.pumpWidget(_splashOver(state));
      await tester.pump(const Duration(milliseconds: 50));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(
        scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
        const Color(0xFF000000),
      );
    });
  });

  group('which colour the first frame is', () {
    test('preload reads the last signed-in account before anything else runs',
        () async {
      // What `main()` awaits. Nothing has been signed in *in this process* —
      // the store is all there is, exactly as after a cold start.
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'alice', accountId: 'acc-alice');
      await store.writeAccent('acc-alice', AppAccent.purple.code);

      final accent = AccentController(store);
      expect(accent.accent, AppAccent.green, reason: 'before the read there is only the default');

      await accent.preload();

      expect(accent.accent, AppAccent.purple);
      expect(accent.accountId, 'acc-alice');
    });

    test('a signed-out device is green, and waits for nothing', () async {
      final accent = AccentController(InMemorySecureStore());
      await accent.preload();
      expect(accent.accent, AppAccent.green);
      expect(accent.accountId, isNull);
    });

    test('an account that never chose is green', () async {
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'new', accountId: 'acc-new');

      final accent = AccentController(store);
      await accent.preload();

      expect(accent.accent, AppAccent.green);
    });

    test('loading the same account again never passes through green', () async {
      // The flash this whole path exists to remove. `initialise()` loads the
      // accent as well, after `preload` already did — and a reset in between
      // would repaint the splash green for a frame.
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'alice', accountId: 'acc-alice');
      await store.writeAccent('acc-alice', AppAccent.pink.code);

      final accent = AccentController(store);
      await accent.preload();

      final seen = <AppAccent>[];
      accent.addListener(() => seen.add(accent.accent));
      await accent.load('acc-alice');

      expect(seen, isEmpty, reason: 'nothing changed, so nothing should have repainted');
      expect(accent.accent, AppAccent.pink);
    });

    test('but switching account does pass through green, never through theirs',
        () async {
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'alice', accountId: 'acc-alice');
      await store.writeAccent('acc-alice', AppAccent.pink.code);
      await store.writeAccent('acc-bob', AppAccent.blue.code);

      final accent = AccentController(store);
      await accent.preload();

      final seen = <AppAccent>[];
      accent.addListener(() => seen.add(accent.accent));
      await accent.load('acc-bob');

      expect(seen, [AppAccent.green, AppAccent.blue]);
      expect(
        seen.contains(AppAccent.pink),
        isFalse,
        reason: "one account's colour must never be drawn under another's name",
      );
    });

    test('and an account with nothing stored lands on green, not on the last one',
        () async {
      final store = InMemorySecureStore();
      await store.writeAccent('acc-alice', AppAccent.orange.code);

      final accent = AccentController(store);
      await accent.load('acc-alice');
      await accent.load('acc-nothing-stored');

      expect(accent.accent, AppAccent.green);
    });

    test('a restart reads back what was chosen', () async {
      // A relaunch is a second controller over the same store, which is what a
      // relaunch actually is.
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'alice', accountId: 'acc-alice');

      final first = AccentController(store);
      await first.load('acc-alice');
      await first.choose(AppAccent.teal);

      final second = AccentController(store);
      await second.preload();

      expect(second.accent, AppAccent.teal);
    });

    test('and a reset is remembered as the default, not as nothing', () async {
      final store = InMemorySecureStore();
      await store.writeSession(token: 't', username: 'alice', accountId: 'acc-alice');

      final first = AccentController(store);
      await first.load('acc-alice');
      await first.choose(AppAccent.yellow);
      await first.reset();

      final second = AccentController(store);
      await second.preload();

      expect(second.accent, AppAccent.green);
    });
  });
}

/// The tagline in whatever language the test host picked.
Future<String> _tagline(WidgetTester tester) async {
  final context = tester.element(find.byType(SplashScreen));
  return AppText.of(context).splashTagline;
}
