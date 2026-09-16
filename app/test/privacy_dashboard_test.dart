import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/privacy_dashboard_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// A server whose security answers can be set per test, because the whole point
/// of the dashboard is that it repeats what the server says rather than what
/// somebody typed into a widget.
class _Server {
  bool twoFactor = false;
  bool phoneLinked = false;
  bool discoverable = false;
  bool contactSync = false;
  List<Map<String, dynamic>> devices = [];
  Map<String, dynamic>? backup;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;

        if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
          return _json({
            'token': 'token',
            'accountId': 'acc-alice',
            'username': 'alice',
            'deviceId': 'device-1',
          }, path == '/v1/accounts' ? 201 : 200);
        }
        if (path == '/v1/accounts/me') {
          return _json({
            'accountId': 'acc-alice',
            'username': 'alice',
            'avatarMediaId': null,
            'twoFactorEnabled': twoFactor,
            'duressCodeSet': false,
            'privacy': const <String, dynamic>{},
          });
        }
        if (path == '/v1/accounts/me/blocks' || path == '/v1/blocks') {
          return _json(const {'blocked': []});
        }
        if (path == '/v1/devices') return _json({'devices': devices});
        if (path == '/v1/phone') {
          return _json({
            'linked': phoneLinked,
            'hint': phoneLinked ? '+41 … 87' : null,
            'discoverable': discoverable,
            'contactSync': contactSync,
            'smsAvailable': true,
            'discoveryAvailable': true,
          });
        }
        if (path == '/v1/backup') {
          return backup == null
              ? _json(const {'error': 'no_backup', 'message': 'none'}, 404)
              : _json(backup!);
        }
        if (path == '/v1/keys/count') return _json(const {'remaining': 50});
        return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []});
      });

  static http.Response _json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
}

Future<PrivioServices> _services(_Server server) async {
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: server.client());
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

Widget _dashboardOver(AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const PrivacyDashboardScreen(),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<AppState> _signedIn(WidgetTester tester, _Server server) async {
  final state =
      await tester.runAsync(() async => AppState(services: await _services(server), store: InMemorySecureStore()))
          as AppState;
  await tester.runAsync(state.initialise);
  await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
  addTearDown(state.conversations.stop);
  return state;
}

void main() {
  testWidgets('two-factor off reads Off, not a guess', (tester) async {
    final server = _Server()..twoFactor = false;
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('Off'), findsWidgets);
    expect(find.text('On'), findsNothing);
  });

  testWidgets('two-factor on reads On — the value comes from the server',
      (tester) async {
    final server = _Server()..twoFactor = true;
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('On'), findsWidgets);
  });

  testWidgets('the device count is the real list, not a number in the widget',
      (tester) async {
    final server = _Server()
      ..devices = [
        {'id': 'd1', 'name': 'This phone', 'current': true},
        {'id': 'd2', 'name': 'Laptop'},
        {'id': 'd3', 'name': 'Tablet'},
      ];
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('an account with no phone number says so rather than nothing',
      (tester) async {
    final server = _Server()..phoneLinked = false;
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('Not linked'), findsOneWidget);
  });

  testWidgets('a linked number shows the hint the server returned', (tester) async {
    final server = _Server()
      ..phoneLinked = true
      ..discoverable = true;
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('+41 … 87'), findsOneWidget);
    expect(find.text('Not linked'), findsNothing);
  });

  testWidgets('no backup on the server is not drawn as a protected one',
      (tester) async {
    final server = _Server()..backup = null;
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('None on the server'), findsOneWidget);
    expect(find.text('Sealed'), findsNothing);
  });

  testWidgets('a value that has not arrived is a dash, never an invented one',
      (tester) async {
    // Nothing is signed in, so nothing can have answered. Every row that would
    // have come from the server has to read as unknown — this is the failure
    // the screen exists to avoid: telling somebody their protection is on when
    // nobody has been asked.
    final server = _Server();
    final state =
        await tester.runAsync(() async => AppState(services: await _services(server), store: InMemorySecureStore()))
            as AppState;
    await tester.runAsync(state.initialise);

    await tester.pumpWidget(_dashboardOver(state));
    await tester.pump();

    expect(find.text('—'), findsWidgets);
    expect(find.text('On'), findsNothing);
  });

  testWidgets('with nothing verified the count is zero, not blank', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(find.text('0'), findsWidgets);
  });

  testWidgets('routing says Direct when no proxy is configured', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);
    // The routing row is the last one; the list has to be scrolled to it.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('Direct'), findsOneWidget);
  });

  testWidgets('the bot exception is on the screen, not in a footnote', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);

    await tester.pumpWidget(_dashboardOver(state));
    await _settle(tester);

    expect(
      find.textContaining('not end-to-end encrypted'),
      findsOneWidget,
      reason: 'the one place Privio can read a body must not be hidden here',
    );
  });
}
