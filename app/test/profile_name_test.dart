import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/display_name.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/profile_name_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/profile_edit_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// Two names, and which of them can change.
///
/// The username is an address: chosen once, carried by invite links, and the
/// one thing on a profile that cannot be made to look like somebody else's.
/// The display name is what a person calls themselves — free text, not
/// unique, changeable as often as they like, and nothing is keyed on it.
class NameServer {
  NameServer({String? displayName}) : _displayName = displayName;

  final requests = <http.Request>[];
  String? _displayName;
  bool fail = false;

  /// What the server was last told to store, which is what a reload returns.
  String? get stored => _displayName;

  late final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        if (fail) return http.Response('{"error":"unavailable"}', 503);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('displayName')) {
          _displayName = body['displayName'] as String?;
        }
      }
      return http.Response(
        jsonEncode({'id': 'acc-alice', 'username': 'alice', 'displayName': _displayName}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  )..useToken('alice');
}

void main() {
  group('the rules the field and the server share', () {
    test('a name is measured in what a reader counts, not in code units', () {
      // One family emoji is one character to a person and eleven to
      // `String.length`. A limit measured the second way would refuse a name
      // that looks short — so the limit is measured the first way.
      expect(visibleLength('👨‍👩‍👧'), 1);
      expect(visibleLength('Jörg'), 4);
      expect(displayNameProblem('👨‍👩‍👧' * 50), isNull);
      expect(displayNameProblem('👨‍👩‍👧' * 51), DisplayNameProblem.tooLong);
    });

    test('spaces, umlauts and emoji survive; the invisible does not', () {
      expect(cleanDisplayName('  Jörg 🌲 Müller  '), 'Jörg 🌲 Müller');
      // A right-to-left override reorders the line it is drawn in, including
      // the @username beside it.
      expect(cleanDisplayName('Ada\u202E Lovelace'), 'Ada Lovelace');
      expect(cleanDisplayName('pad\u200B\u200Bding'), 'padding');
      // But the joiners that hold an emoji together stay: removing those
      // would misspell the name rather than clean it.
      expect(cleanDisplayName('👩‍🚀'), '👩‍🚀');
    });

    test('nothing is a real answer, not an error', () {
      expect(cleanDisplayName('   '), isNull);
      expect(cleanDisplayName(''), isNull);
      expect(displayNameProblem(''), isNull);
    });
  });

  group('the controller', () {
    test('reads both names, and offers the username when there is no other',
        () async {
      final server = NameServer();
      final names = ProfileNameController(server.api);
      await names.load('acc-alice');

      expect(names.username, 'alice');
      expect(names.displayName, isNull);
      expect(names.label, 'alice', reason: 'an account with no display name is its @username');

      await names.save('Alice Doe');
      expect(names.displayName, 'Alice Doe');
      expect(names.label, 'Alice Doe');
      expect(names.username, 'alice', reason: 'saving a display name renamed the account');
    });

    test('clearing it sends the key, and the name is gone after a reload',
        () async {
      // Clearing has to be distinguishable from not mentioning the field:
      // before this, `COALESCE` on the server made the two the same request
      // and nobody could remove their name.
      final server = NameServer(displayName: 'Temporary');
      final names = ProfileNameController(server.api);
      await names.load('acc-alice');
      expect(names.displayName, 'Temporary');

      expect(await names.save('   '), isTrue);
      final sent = jsonDecode(server.requests.last.body) as Map<String, dynamic>;
      expect(sent.containsKey('displayName'), isTrue);
      expect(sent['displayName'], isNull);
      expect(server.stored, isNull);

      final reloaded = ProfileNameController(server.api);
      await reloaded.load('acc-alice');
      expect(reloaded.displayName, isNull);
      expect(reloaded.label, 'alice');
    });

    test('a name that did not save is not shown as though it had', () async {
      final server = NameServer(displayName: 'Before');
      final names = ProfileNameController(server.api);
      await names.load('acc-alice');
      server.fail = true;

      expect(await names.save('After'), isFalse);
      expect(names.displayName, 'Before', reason: 'a failed save was written anyway');
      expect(names.failure, isNotNull);
    });

    test('one too long is refused before it is sent', () async {
      final server = NameServer();
      final names = ProfileNameController(server.api);
      await names.load('acc-alice');
      final before = server.requests.length;

      expect(await names.save('x' * 51), isFalse);
      expect(server.requests.length, before, reason: 'it was sent anyway');
      expect(names.failure, isNotNull);
    });

    test('an answer for the previous account is dropped after a switch',
        () async {
      final server = NameServer(displayName: 'Alice');
      final names = ProfileNameController(server.api);
      final loading = names.load('acc-alice');
      // The switch happens while the first read is in flight.
      unawaited(names.load('acc-bob'));
      await loading;

      expect(names.accountId, 'acc-bob');
    });

    test('there is no way to ask for a different username', () {
      // Not an assertion about behaviour but about surface: a method that
      // could rename an account is a method somebody would eventually call.
      // `save` takes one argument and it is the display name; `username` is a
      // getter with no setter. The server refuses a rename besides — that is
      // `server/test/names.test.ts` — but the surface here is the first
      // reason nobody can try.
      final names = ProfileNameController(NameServer().api);
      expect(names.username, isNull);
    });
  });

  group('a display name is not an identity', () {
    test('two people may share one, and remain two people', () {
      final store = InMemoryMessageStore();
      store.upsertUser(const KnownUser(
        accountId: 'acc-one',
        username: 'alex.one',
        displayName: 'Alex Taylor',
      ));
      store.upsertUser(const KnownUser(
        accountId: 'acc-two',
        username: 'alex.two',
        displayName: 'Alex Taylor',
      ));
      store.append('acc-one', Message(id: 'm1', body: 'from one', sentAt: DateTime(2026), isMine: false));
      store.append('acc-two', Message(id: 'm2', body: 'from two', sentAt: DateTime(2026), isMine: false));

      expect(store.conversations(), hasLength(2));
      expect(store.conversationWith('acc-one')!.messages.single.body, 'from one');
      expect(store.conversationWith('acc-two')!.messages.single.body, 'from two');
      expect(store.conversationWith('acc-one')!.user!.username, 'alex.one');
      expect(store.conversationWith('acc-two')!.user!.username, 'alex.two');
      expect(
        store.conversationWith('acc-one')!.title,
        store.conversationWith('acc-two')!.title,
        reason: 'the two names were meant to be identical',
      );
    });

    test('a rename keeps the conversation, its messages and its id', () {
      // Everything is keyed on the account id, so this is really a test that
      // nothing is keyed on the name.
      final store = InMemoryMessageStore();
      store.upsertUser(const KnownUser(
        accountId: 'acc-bob',
        username: 'bob',
        displayName: 'Bob',
      ));
      store.append('acc-bob', Message(id: 'm1', body: 'kept', sentAt: DateTime(2026), isMine: false));

      store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob', displayName: 'Robert'),
        authoritative: true,
      );

      expect(store.conversations(), hasLength(1));
      expect(store.conversationWith('acc-bob')!.messages.single.body, 'kept');
      expect(store.conversationWith('acc-bob')!.title, 'Robert');
      expect(store.conversationWith('acc-bob')!.user!.username, 'bob');
    });

    test('a removed name reaches this device, and falls back to the username',
        () {
      // The half that was missing: `merge` treats a null as "no news", so
      // without the authoritative flag somebody's discarded name would stay
      // on other people's screens forever.
      final store = InMemoryMessageStore();
      store.upsertUser(const KnownUser(
        accountId: 'acc-bob',
        username: 'bob',
        displayName: 'Bob',
      ));
      store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob'),
        authoritative: true,
      );
      expect(store.conversationWith('acc-bob')!.title, 'bob');
    });

    test('a fact from a message never removes a name it did not mention', () {
      final store = InMemoryMessageStore();
      store.upsertUser(const KnownUser(
        accountId: 'acc-bob',
        username: 'bob',
        displayName: 'Bob',
      ));
      // A profile key arriving inside a message knows nothing about names.
      store.upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob', profileKey: 'key'));
      expect(store.conversationWith('acc-bob')!.title, 'Bob');
    });
  });

  group('the edit screen', () {
    Future<AppState> signedIn(NameServer server) async {
      final quiet = await quietServices();
      final state = AppState(
        // Everything quiet except the one endpoint under test.
        services: PrivioServices(
          api: server.api,
          crypto: quiet.crypto,
          messaging: quiet.messaging,
          channels: quiet.channels,
          recorder: quiet.recorder,
          player: quiet.player,
          backup: quiet.backup,
          store: quiet.store,
          secureStore: quiet.secureStore,
        ),
        store: InMemorySecureStore(),
      );
      await state.initialise();
      await state.names.load('acc-alice');
      return state;
    }

    testWidgets('shows the username as something to copy, not to edit',
        (tester) async {
      final server = NameServer(displayName: 'Alice Doe');
      final state = await signedIn(server);
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ProfileEditScreen(), state));
      await tester.pumpAndSettle();

      expect(find.text('Username'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      // One field on the screen, and it is the display name.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Save is offered only once something changed', (tester) async {
      final server = NameServer(displayName: 'Alice Doe');
      final state = await signedIn(server);
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ProfileEditScreen(), state));
      await tester.pumpAndSettle();

      Finder button(String label) => find.widgetWithText(TextButton, label);
      expect(tester.widget<TextButton>(button('Save')).onPressed, isNull);
      expect(tester.widget<TextButton>(button('Cancel')).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Alice Elsewhere');
      await tester.pump();
      expect(tester.widget<TextButton>(button('Save')).onPressed, isNotNull);
      expect(tester.widget<TextButton>(button('Cancel')).onPressed, isNotNull);
    });

    testWidgets('Cancel leaves the stored name alone', (tester) async {
      final server = NameServer(displayName: 'Alice Doe');
      final state = await signedIn(server);
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ProfileEditScreen(), state));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Discarded');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(state.names.displayName, 'Alice Doe');
    });

    testWidgets('one too long is refused on the screen, before any request',
        (tester) async {
      final server = NameServer();
      final state = await signedIn(server);
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ProfileEditScreen(), state));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'x' * 51);
      await tester.pump();

      expect(find.text('That name is longer than 50 characters.'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save')).onPressed,
        isNull,
      );
    });
  });
}
