import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/app.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_icon.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/disguise/launcher_disguise.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/appearance_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_colors.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// A server that signs anybody in and answers everything else emptily.
///
/// The account id is derived from the username, because the whole point of
/// these tests is which account a stored preference belongs to: a id that
/// changed between signing up and signing back in would make "it survived a
/// restart" unprovable either way.
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
      // Everything a sign-in kicks off in the background gets a plausible
      // answer. Left to 404 they throw out of detached futures and the test
      // fails on a prekey count rather than on anything about colour.
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

/// A fresh app over a store the test keeps a handle on. A "restart" is a second
/// [AppState] over the *same* store, which is what a relaunch actually is.
Future<AppState> _appOver(SecureStore store, {LauncherDisguise? launcher}) async {
  final state = AppState(
    services: await _services(),
    store: store,
    launcher: launcher,
  );
  await state.initialise();
  return state;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The appearance screen under a theme that follows the account's accent —
/// the same arrangement `app.dart` builds, so a tap here repaints the same way
/// it does in the app.
Widget _appearanceOver(AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, state.accent]),
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(accent: state.accent.accent),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const AppearanceScreen(),
        ),
      ),
    );

void main() {
  group('the screen offers eight colours and says which is which', () {
    testWidgets('every accent is on it, named, with the default marked',
        (tester) async {
      final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
      addTearDown(state.dispose);
      await tester.pumpWidget(_appearanceOver(state));
      await tester.pumpAndSettle();

      for (final accent in AppAccent.values) {
        expect(
          find.byKey(ValueKey('accent-name-${accent.code}')),
          findsOneWidget,
          reason: '${accent.code} is missing from the picker',
        );
      }
      expect(find.text('Green'), findsOneWidget);
      expect(find.text('Turquoise'), findsOneWidget);
      expect(find.text('Privio default'), findsOneWidget);
    });

    testWidgets('the chosen one carries the tick, and only it', (tester) async {
      final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
      addTearDown(state.dispose);
      await tester.pumpWidget(_appearanceOver(state));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('accent-check-green')), findsOneWidget);
      expect(find.byKey(const ValueKey('accent-check-purple')), findsNothing);
    });
  });

  group('a tap repaints the app, without a restart', () {
    testWidgets('the theme under the screen is the one that was picked',
        (tester) async {
      final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
      // `PrivioApp` disposes the state when it unmounts, so a teardown that
      // disposed it again would be the second call.
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(PrivioApp(state: state));
      await tester.pump(const Duration(seconds: 1));

      ThemeData themeNow() =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

      expect(themeNow().colorScheme.primary, PrivioColors.accent);

      await tester.runAsync(() => state.accent.choose(AppAccent.purple));
      await tester.pumpAndSettle();

      // Not a repaint of one screen: the whole app is built from this.
      expect(themeNow().colorScheme.primary, AppAccent.purple.seed);
      expect(
        themeNow().extension<PrivioAccents>()!.choice,
        AppAccent.purple,
        reason: 'the derived shades came with it',
      );
    });

    testWidgets('tapping a swatch moves the tick there', (tester) async {
      final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
      addTearDown(state.dispose);
      await tester.pumpWidget(_appearanceOver(state));
      await tester.pumpAndSettle();

      // The picker sits below the fold on the test surface, as it does on a
      // small phone — so it is scrolled to rather than tapped blind.
      await tester.ensureVisible(find.byKey(const ValueKey('accent-name-pink')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-name-pink')));
      await tester.pumpAndSettle();

      expect(state.accent.accent, AppAccent.pink);
      expect(find.byKey(const ValueKey('accent-check-pink')), findsOneWidget);
      expect(find.byKey(const ValueKey('accent-check-green')), findsNothing);
    });

    testWidgets('reset appears once something is chosen, and puts green back',
        (tester) async {
      final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
      addTearDown(state.dispose);
      await tester.pumpWidget(_appearanceOver(state));
      await tester.pumpAndSettle();

      // Nothing to reset while the default is the choice.
      expect(find.byKey(const ValueKey('accent-reset')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('accent-name-orange')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-name-orange')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('accent-reset')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('accent-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-reset')));
      await tester.pumpAndSettle();

      expect(state.accent.accent, AppAccent.green);
      expect(find.byKey(const ValueKey('accent-reset')), findsNothing);
    });
  });

  group('whose colour it is', () {
    testWidgets('a choice survives a restart, and green is never shown first',
        (tester) async {
      final store = InMemorySecureStore();
      final first = await tester.runAsync(() => _appOver(store)) as AppState;
      await tester.runAsync(() => first.register(username: 'anna', password: 'pw-anna-1'));
      await tester.runAsync(() => first.accent.choose(AppAccent.teal));
      await _settle(tester);
      // Stopped, not disposed. Signing in starts a poller and a contact
      // refresh; one of those landing on a disposed controller afterwards
      // fails the test on this test's own housekeeping rather than on anything
      // about colour. Stopping ends the polling, and what is already in flight
      // is left to finish against an object nobody is looking at.
      first.conversations.stop();

    // The relaunch. `initialise` is what the splash awaits, so the colour has
      // to be in place *by the time it returns* — not a microtask later. The
      // reading is taken with nothing awaited in between, which is what makes
      // this a test about the flash rather than about the value eventually
      // being right: a load left unawaited would still be in flight here and
      // would read green.
      late AppState second;
      final atBoot = await tester.runAsync(() async {
        second = AppState(services: await _services(), store: store);
        await second.initialise();
        return second.accent.accent;
      });
      addTearDown(second.conversations.stop);
      expect(
        atBoot,
        AppAccent.teal,
        reason: 'green for one frame on every launch is the thing this must not do',
      );
    });

    testWidgets('a second account does not inherit the first one\'s colour',
        (tester) async {
      final store = InMemorySecureStore();
      final state = await tester.runAsync(() => _appOver(store)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.runAsync(() => state.register(username: 'anna', password: 'pw-anna-1'));
      await tester.runAsync(() => state.accent.choose(AppAccent.yellow));
      await _settle(tester);
      expect(state.accent.accent, AppAccent.yellow);

      state.conversations.stop();
      await tester.runAsync(state.signOut);
      await _settle(tester);
      expect(state.accent.accent, AppAccent.green, reason: 'signed out is brand green');

      await tester.runAsync(() => state.register(username: 'bruno', password: 'pw-bruno-1'));
      await _settle(tester);
      expect(
        state.accent.accent,
        AppAccent.green,
        reason: 'a new account starts at the default, not at the last one',
      );
    });
  });

  group('small screens, large text, and screen readers', layout);

  group('the home-screen icon belongs to the phone', appIcon);

  group('the app icon section', appIconScreen);

  group('what the accent does not touch', () {
    test('destructive red is the same in all eight', () {
      // The distinction the whole thing rests on: an accent is decoration, and
      // red means something. An account that chose red still has to be able to
      // tell "send" from "delete".
      for (final accent in AppAccent.values) {
        final theme = PrivioTheme.dark(accent: accent);
        expect(theme.colorScheme.error, PrivioColors.danger, reason: accent.code);
      }
      // And the accent red is not the danger red, so the two do not collapse.
      expect(AppAccent.red.seed, isNot(PrivioColors.danger));
    });

    test('the black background and the grey cards do not move', () {
      for (final accent in AppAccent.values) {
        final theme = PrivioTheme.dark(accent: accent);
        expect(theme.scaffoldBackgroundColor, PrivioColors.background, reason: accent.code);
        expect(theme.colorScheme.surface, PrivioColors.surface, reason: accent.code);
        expect(theme.cardTheme.color, PrivioColors.surface, reason: accent.code);
      }
    });

    test('a channel keeps the colour it chose for itself', () {
      // Somebody else's channel is somebody else's, and a reader repainting it
      // would be the reader's setting changing what a channel looks like.
      expect(ChannelPalette.accentFor('blue'), const Color(0xFF3B82F6));
      expect(ChannelPalette.accentFor('green'), PrivioColors.accent);
    });
  });
}

/// The picker has to survive the two things that break a grid of labelled dots:
/// a small screen and somebody who has turned the text up.
void layout() {
  Future<void> pumpAt(WidgetTester tester, Size size, double textScale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: _appearanceOver(state),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the picker into view and checks every swatch laid out.
  ///
  /// The scroll is not incidental: the list builds lazily, so at a large text
  /// size the picker is genuinely not in the tree until it is reached — which
  /// is the list doing its job, not the picker failing.
  Future<void> expectAllEightLayOut(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accent-name-yellow')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final accent in AppAccent.values) {
      expect(
        find.byKey(ValueKey('accent-name-${accent.code}')),
        findsOneWidget,
        reason: '${accent.code} did not lay out',
      );
    }
    expect(tester.takeException(), isNull, reason: 'nothing overflowed');
  }

  testWidgets('all eight fit on a small phone', (tester) async {
    // 320 x 568 is the smallest screen Privio claims to support.
    await pumpAt(tester, const Size(320, 568), 1);
    await expectAllEightLayOut(tester);
  });

  testWidgets('and at the largest text size', (tester) async {
    // The grid drops to two columns rather than clipping the names.
    await pumpAt(tester, const Size(320, 568), 2);
    await expectAllEightLayOut(tester);
  });

  testWidgets('a screen reader is told the name and the state', (tester) async {
    final handle = tester.ensureSemantics();
    final state = await tester.runAsync(() => _appOver(InMemorySecureStore())) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_appearanceOver(state));
    await tester.pumpAndSettle();

    // A dot is nothing to a screen reader, so every swatch says what it is —
    // and the chosen one says so in words rather than only with a ring.
    expect(find.bySemanticsLabel('Green, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Violet'), findsOneWidget);
    handle.dispose();
  });
}

/// The home-screen icon is the phone's, not the account's — the opposite rule
/// from the accent colour, and worth pinning next to it so the two cannot
/// drift into each other.
void appIcon() {
  testWidgets('signing in as somebody else leaves the home screen alone',
      (tester) async {
    final store = InMemorySecureStore();
    final launcher = _RecordingLauncher();
    final state = await tester.runAsync(
      () => _appOver(store, launcher: launcher),
    ) as AppState;
    addTearDown(state.conversations.stop);

    await tester.runAsync(() => state.register(username: 'anna', password: 'pw-anna-1'));
    await tester.runAsync(state.appIcon.reconcile);
    await tester.runAsync(() => state.appIcon.choose(AppIconColour.pink));
    await _settle(tester);
    expect(state.appIcon.colour, AppIconColour.pink);

    final afterChoosing = launcher.applied.length;
    state.conversations.stop();
    await tester.runAsync(state.signOut);
    await _settle(tester);
    await tester.runAsync(() => state.register(username: 'bruno', password: 'pw-bruno-1'));
    await _settle(tester);

    expect(
      launcher.applied.length,
      afterChoosing,
      reason: 'nothing touched the launcher on the way through two accounts',
    );
    expect(state.appIcon.colour, AppIconColour.pink);
    // And the accent, which *is* per account, did reset — the two rules are
    // different on purpose.
    expect(state.accent.accent, AppAccent.green);
  });

  testWidgets('the icon it was set to survives a restart of the app', (tester) async {
    final store = InMemorySecureStore();
    final launcher = _RecordingLauncher();
    final first = await tester.runAsync(() => _appOver(store, launcher: launcher)) as AppState;
    await tester.runAsync(first.appIcon.reconcile);
    await tester.runAsync(() => first.appIcon.choose(AppIconColour.orange));
    await _settle(tester);
    first.conversations.stop();

    // The relaunch, over the same store and the same phone.
    final second = await tester.runAsync(
      () => _appOver(store, launcher: _RecordingLauncher(showing: launcher.showing)),
    ) as AppState;
    addTearDown(second.conversations.stop);
    await tester.runAsync(second.appIcon.reconcile);

    expect(second.appIcon.colour, AppIconColour.orange);
  });
}

void appIconScreen() {
  testWidgets('the section offers eight icons under the accent, and ticks one',
      (tester) async {
    final launcher = _RecordingLauncher();
    final state = await tester.runAsync(
      () => _appOver(InMemorySecureStore(), launcher: launcher),
    ) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_appearanceOver(state));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('app-icon-name-yellow')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final colour in AppIconColour.values) {
      expect(
        find.byKey(ValueKey('app-icon-name-${colour.code}')),
        findsOneWidget,
        reason: '${colour.code} is missing',
      );
    }
    expect(find.byKey(const ValueKey('app-icon-check-green')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-check-purple')), findsNothing);
    expect(find.byKey(const ValueKey('app-icon-match-accent')), findsOneWidget);
    // Nothing to restore while the original is what is showing.
    expect(find.byKey(const ValueKey('app-icon-reset')), findsNothing);
  });

  testWidgets('tapping one changes the launcher and moves the tick',
      (tester) async {
    final launcher = _RecordingLauncher();
    final state = await tester.runAsync(
      () => _appOver(InMemorySecureStore(), launcher: launcher),
    ) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_appearanceOver(state));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('app-icon-name-blue')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-icon-name-blue')));
    await tester.pumpAndSettle();

    expect(launcher.applied.last, const LauncherEntry.icon(AppIconColour.blue));
    expect(state.appIcon.colour, AppIconColour.blue);
    expect(find.byKey(const ValueKey('app-icon-check-blue')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-reset')), findsOneWidget);
  });

  testWidgets('a platform that cannot change it says so instead of offering',
      (tester) async {
    final state = await tester.runAsync(
      () => _appOver(InMemorySecureStore(), launcher: _RefusingLauncher()),
    ) as AppState;
    addTearDown(state.dispose);
    await tester.pumpWidget(_appearanceOver(state));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('app-icon-unavailable')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // One honest line rather than eight swatches that would do nothing.
    expect(find.byKey(const ValueKey('app-icon-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-name-blue')), findsNothing);
  });
}

/// A launcher on a platform with no alternate icons at all — the web build, a
/// desktop build, an iPhone whose iOS says no.
class _RefusingLauncher implements LauncherDisguise {
  @override
  Future<LauncherCapability> capability() async => LauncherCapability.none;

  @override
  Future<void> show(LauncherEntry entry) async =>
      throw const LauncherDisguiseException('This platform cannot change the app icon.');

  @override
  Future<LauncherEntry?> current() async => null;
}

/// A launcher that accepts everything and remembers what it was shown.
class _RecordingLauncher implements LauncherDisguise {
  _RecordingLauncher({this.showing = const LauncherEntry.icon(AppIconColour.green)});

  LauncherEntry? showing;
  final List<LauncherEntry> applied = [];

  @override
  Future<LauncherCapability> capability() async =>
      const LauncherCapability(icon: true, name: false);

  @override
  Future<void> show(LauncherEntry entry) async {
    applied.add(entry);
    showing = entry;
  }

  @override
  Future<LauncherEntry?> current() async => showing;
}
