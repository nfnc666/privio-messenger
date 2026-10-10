import 'dart:async';
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
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/contacts_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// Adding a contact, the first thing anybody does with a new account.
///
/// Found by using the app rather than by reading it: the empty chat list's
/// "Add a contact" opened the contact list, the search there found nobody,
/// and when the add sheet was finally reached its refusal never showed —
/// its state lived inside the builder and every rebuild reset it.
class _Server {
  final List<Map<String, dynamic>> contacts = [];
  final Map<String, Map<String, dynamic>> people = {
    'bob': {'id': 'acc-bob', 'username': 'bob', 'displayName': 'Bob'},
  };
  final List<String> added = [];

  /// Holds the next add until completed, so a test can look at the sheet
  /// while the request is out.
  Completer<void>? holdAdd;

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
            'privacy': const <String, dynamic>{},
          });
        }
        if (request.method == 'POST' && path == '/v1/contacts') {
          final username = (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
          added.add(username);
          await holdAdd?.future;
          final person = people[username];
          if (person == null) {
            return _json({'error': 'not_found', 'message': 'No user with that name'}, 404);
          }
          contacts.add(person);
          return _json(person, 201);
        }
        if (request.method == 'GET' && path == '/v1/contacts') {
          return _json({'contacts': contacts});
        }
        if (path.startsWith('/v1/users/')) {
          final person = people[path.substring('/v1/users/'.length)];
          return person == null
              ? _json({'error': 'not_found', 'message': 'No user with that name'}, 404)
              : _json(person);
        }
        if (path == '/v1/keys/count') return _json(const {'remaining': 50});
        return _json(const {'envelopes': [], 'more': false, 'channels': [], 'groups': []});
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

Widget _over(AppState state, Widget home) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: home,
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
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

Future<void> _typeAndAdd(WidgetTester tester, String username) async {
  await tester.enterText(find.byType(TextField).last, username);
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await _settle(tester);
}

void main() {
  test('a typed username means the name, not the @ in front of it', () {
    expect(normaliseUsername('  @Bob '), 'bob');
    expect(normaliseUsername('@@ bob'), 'bob');
    expect(normaliseUsername('bob.e2e'), 'bob.e2e');
    expect(usernamePattern.hasMatch('bo'), isFalse);
    expect(usernamePattern.hasMatch('bob smith'), isFalse);
  });

  testWidgets('a refused username is said in the sheet, and the sheet stays', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);
    await tester.pumpWidget(_over(state, const ContactsScreen()));
    await _settle(tester);

    await tester.tap(find.byTooltip('Add contact'));
    await _settle(tester);
    await _typeAndAdd(tester, 'nobody');

    expect(server.added, ['nobody']);
    expect(find.text('No user with that name'), findsOneWidget);
    expect(find.text('Add contact'), findsWidgets, reason: 'the sheet must still be open');

    // Typing again clears the refusal rather than leaving it under a new name.
    await tester.enterText(find.byType(TextField).last, 'bob');
    await tester.pump();
    expect(find.text('No user with that name'), findsNothing);
  });

  testWidgets('one press sends one request, and the button waits for it', (tester) async {
    final server = _Server()..holdAdd = Completer<void>();
    final state = await _signedIn(tester, server);
    await tester.pumpWidget(_over(state, const ContactsScreen()));
    await _settle(tester);

    await tester.tap(find.byTooltip('Add contact'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'bob');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNull, reason: 'pressable while the request is out');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    server.holdAdd!.complete();
    await _settle(tester);
    expect(server.added, ['bob']);
    expect(find.text('Bob'), findsOneWidget, reason: 'the new contact is listed');
  });

  testWidgets('a search that finds nobody offers to add that name', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);
    await tester.pumpWidget(_over(state, const ContactsScreen()));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, '@Bob');
    await tester.pump();
    expect(find.text('No contacts yet'), findsNothing);
    expect(find.text('Nothing matched'), findsOneWidget);

    await tester.tap(find.text('Add @bob'));
    await _settle(tester);
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('bob')),
      findsOneWidget,
      reason: 'the sheet opens with the name already in it',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await _settle(tester);
    expect(server.added, ['bob']);

    // Something that cannot be a username is not offered.
    await tester.enterText(find.byType(TextField).first, 'b b');
    await tester.pump();
    expect(find.textContaining('Add @'), findsNothing);
  });

  testWidgets('the empty chat list adds a contact and opens the conversation', (tester) async {
    final server = _Server();
    final state = await _signedIn(tester, server);
    await tester.pumpWidget(_over(state, const ChatsScreen()));
    await _settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add a contact'));
    await _settle(tester);
    expect(find.byType(ContactsScreen), findsNothing, reason: 'it asks for a name, not for a list');
    await _typeAndAdd(tester, '@bob');
    await _settle(tester);

    expect(server.added, ['bob']);
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
