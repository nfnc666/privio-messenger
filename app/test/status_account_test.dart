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
import 'package:privio/screens/account_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// A server that holds one status per account.
///
/// Per account is the whole point: the tests below are about which account a
/// status belongs to, so a server that kept one global value could not tell a
/// leak from correct behaviour.
class _Server {
  final Map<String, Map<String, dynamic>> statusByAccount = {};

  /// Which account each token belongs to. Set at sign-in, read on every call —
  /// so a request made with the old token cannot read the new account.
  final Map<String, String> accountForToken = {};

  http.Client client() => MockClient((request) async {
        final path = request.url.path;

        if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
          final username = (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
          accountForToken['token-$username'] = 'acc-$username';
          return _json({
            'token': 'token-$username',
            'accountId': 'acc-$username',
            'username': username,
            'deviceId': 'device-1',
          }, path == '/v1/accounts' ? 201 : 200);
        }

        final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
        final account = accountForToken[token] ?? '';

        if (path == '/v1/accounts/me') {
          return _json({
            'accountId': account,
            'username': account,
            'avatarMediaId': null,
            'status': statusByAccount[account] ?? _none,
            'privacy': const <String, dynamic>{},
          });
        }
        if (request.method == 'PUT' && path == '/v1/accounts/me/status') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final text = (body['text'] as String?)?.trim();
          if (text == null || text.isEmpty) {
            statusByAccount.remove(account);
          } else {
            statusByAccount[account] = {
              'text': text,
              'emoji': body['emoji'],
              'expiresAt': body['expiresAt'],
              'updatedAt': null,
            };
          }
          return _json({'status': statusByAccount[account] ?? _none});
        }
        if (request.method == 'DELETE' && path == '/v1/accounts/me/status') {
          statusByAccount.remove(account);
          return _json({'status': _none});
        }
        if (path == '/v1/keys/count') return _json(const {'remaining': 50});
        return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []});
      });

  static const Map<String, dynamic> _none = {
    'text': null,
    'emoji': null,
    'expiresAt': null,
    'updatedAt': null,
  };

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

Future<AppState> _appOver(_Server server, SecureStore store) async {
  final state = AppState(services: await _services(server), store: store);
  await state.initialise();
  return state;
}

Widget _accountOver(AppState state) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const AccountScreen(),
        ),
      ),
    );

/// Lets the work sign-in starts in the background actually run.
///
/// The status is read by a detached future — the app must not block the chat
/// list on it — and a detached future needs real time, not `pump`'s fake clock.
/// Waiting for it here rather than awaiting `load` in the test is deliberate:
/// what is under test includes that signing in fetches the status *by itself*.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the row opens the sheet — it used to do nothing at all', (tester) async {
    final server = _Server();
    final state = await tester.runAsync(() => _appOver(server, InMemorySecureStore())) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_accountOver(state));
    await _settle(tester);

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();

    // A text field means the sheet is up. Before this change the row had no
    // onTap and a tap did nothing whatsoever.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('what is saved appears on the row straight away', (tester) async {
    final server = _Server();
    final state = await tester.runAsync(() => _appOver(server, InMemorySecureStore())) as AppState;
    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_accountOver(state));
    await _settle(tester);
    expect(find.text('Not set'), findsOneWidget);

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'On a break');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The sheet is gone and the row carries the new line, with no reload and
    // no second trip to the screen.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('On a break'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);
  });

  testWidgets('it is still there after a restart', (tester) async {
    final server = _Server();
    final store = InMemorySecureStore();

    final first = await tester.runAsync(() => _appOver(server, store)) as AppState;
    await tester.runAsync(() => first.signIn(username: 'alice', password: 'correct-horse'));
    await tester.runAsync(() => first.profileStatus.save(text: 'Set before the restart'));
    first.conversations.stop();

    // A relaunch: a second AppState over the same store, which is what a cold
    // start actually is.
    final second = await tester.runAsync(() => _appOver(server, store)) as AppState;
    addTearDown(second.conversations.stop);

    await tester.pumpWidget(_accountOver(second));
    await _settle(tester);

    expect(find.text('Set before the restart'), findsOneWidget);
  });

  testWidgets('a second account does not inherit the first one’s status', (tester) async {
    final server = _Server();
    final state = await tester.runAsync(() => _appOver(server, InMemorySecureStore())) as AppState;

    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    await tester.runAsync(() => state.profileStatus.save(text: "Alice's line"));

    await tester.pumpWidget(_accountOver(state));
    await _settle(tester);
    expect(find.text("Alice's line"), findsOneWidget);

    // Out, and in as somebody else.
    await tester.runAsync(state.signOut);
    await tester.runAsync(() => state.signIn(username: 'bob', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_accountOver(state));
    await _settle(tester);

    expect(find.text("Alice's line"), findsNothing, reason: 'Bob must not wear Alice’s status');
    expect(find.text('Not set'), findsOneWidget);
    expect(state.profileStatus.accountId, 'acc-bob');

    // And Alice's is still hers on the server — signing out did not delete it.
    expect(server.statusByAccount['acc-alice']!['text'], "Alice's line");
  });

  testWidgets('signing back in brings it back', (tester) async {
    final server = _Server();
    final state = await tester.runAsync(() => _appOver(server, InMemorySecureStore())) as AppState;

    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    await tester.runAsync(() => state.profileStatus.save(text: 'Mine', emoji: '📚'));
    await tester.runAsync(state.signOut);

    await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(_accountOver(state));
    await _settle(tester);

    expect(find.textContaining('Mine'), findsOneWidget);
  });
}
