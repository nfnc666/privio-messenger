import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/profile_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/contact_profile_screen.dart';
import 'package:privio/screens/group_info_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// A server that holds profiles, contacts and blocks per account.
///
/// Per account throughout, because half of what these tests are about is which
/// account is asking: the same profile answers differently to two viewers, and
/// a cache that mixed them up would be a leak rather than a glitch.
class _Server {
  _Server();

  /// Profiles by account id, as `GET /v1/users/id/:id` returns them.
  final Map<String, Map<String, dynamic>> profiles = {};

  /// Account ids each signed-in account has in its address book, and blocked.
  final Map<String, Set<String>> contactsOf = {};
  final Map<String, Set<String>> blockedBy = {};

  /// Reports filed, as (reporter, target, reason).
  final List<(String, String, String)> reports = [];

  final Map<String, String> accountForToken = {};

  /// Ids this server was asked about, in order. The tests assert on *which*
  /// account was looked up, which is the whole "opens the right person" claim.
  final List<String> lookedUp = [];

  void give(
    String accountId, {
    required String username,
    String? displayName,
    String? statusText,
    String? lastSeenAt,
  }) {
    profiles[accountId] = {
      'id': accountId,
      'username': username,
      'displayName': displayName,
      'avatarMediaId': null,
      'lastSeenAt': lastSeenAt,
      'status': {
        'text': statusText,
        'emoji': null,
        'expiresAt': null,
        'updatedAt': null,
      },
    };
  }

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
          final username =
              (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
          accountForToken['token-$username'] = 'acc-$username';
          return _json({
            'token': 'token-$username',
            'accountId': 'acc-$username',
            'username': username,
            'deviceId': 'device-1',
          }, path == '/v1/accounts' ? 201 : 200);
        }

        final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
        final viewer = accountForToken[token] ?? '';

        if (method == 'GET' && path.startsWith('/v1/users/id/')) {
          final id = path.split('/').last;
          lookedUp.add(id);
          final profile = profiles[id];
          if (profile == null) {
            return _json(const {'error': 'user_not_found', 'message': 'No such user'}, 404);
          }
          return _json({
            ...profile,
            // Decided by the server, exactly as the real one does.
            'isSelf': id == viewer,
            'isContact': contactsOf[viewer]?.contains(id) ?? false,
            'isBlocked': blockedBy[viewer]?.contains(id) ?? false,
          });
        }
        if (method == 'GET' && path.startsWith('/v1/users/')) {
          final username = path.split('/').last;
          final match = profiles.values.where((p) => p['username'] == username);
          if (match.isEmpty) {
            return _json(const {'error': 'user_not_found', 'message': 'No such user'}, 404);
          }
          return _json(match.first);
        }
        if (method == 'POST' && path == '/v1/contacts') {
          final username =
              (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
          final match = profiles.values.where((p) => p['username'] == username);
          if (match.isEmpty) {
            return _json(const {'error': 'user_not_found', 'message': 'No such user'}, 404);
          }
          contactsOf.putIfAbsent(viewer, () => {}).add(match.first['id'] as String);
          return _json(match.first, 201);
        }
        if (method == 'DELETE' && path.startsWith('/v1/contacts/')) {
          contactsOf[viewer]?.remove(path.split('/').last);
          return _json(const {'removed': true});
        }
        if (method == 'POST' && path == '/v1/blocks') {
          final id = (jsonDecode(request.body) as Map<String, dynamic>)['accountId'] as String;
          blockedBy.putIfAbsent(viewer, () => {}).add(id);
          return _json(const {'blocked': true}, 201);
        }
        if (method == 'DELETE' && path.startsWith('/v1/blocks/')) {
          blockedBy[viewer]?.remove(path.split('/').last);
          return _json(const {'blocked': false});
        }
        if (method == 'POST' && path.endsWith('/report')) {
          final id = path.split('/')[3];
          final reason =
              (jsonDecode(request.body) as Map<String, dynamic>)['reason'] as String;
          final already = reports.any((r) => r.$1 == viewer && r.$2 == id);
          if (!already) reports.add((viewer, id, reason));
          return _json({'reported': true, 'alreadyReported': already}, already ? 200 : 201);
        }
        if (path == '/v1/keys/count') return _json(const {'remaining': 50});
        if (path == '/v1/blocks') return _json(const {'blocked': []});
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

Future<AppState> _signedIn(_Server server, {String as = 'alice'}) async {
  final state = AppState(services: await _services(server), store: InMemorySecureStore());
  await state.initialise();
  await state.signIn(username: as, password: 'correct-horse');
  return state;
}

Widget _wrap(Widget child, AppState state) => PrivioScope(
      notifier: state,
      // Outside the MaterialApp, as in `app.dart`: a pushed route has to find
      // the scope, and these tests are almost entirely about pushed routes.
      child: MaterialApp(
        theme: PrivioTheme.dark(),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: child,
      ),
    );

/// Lets the detached work a screen starts actually run.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pumpAndSettle();
}

void main() {
  group('opening a profile from a one-to-one chat', () {
    testWidgets('the header opens the person you are talking to', (tester) async {
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob Baker');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);
      state.services.store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob', displayName: 'Bob Baker'),
      );

      await tester.pumpWidget(
        _wrap(const ChatScreen(accountId: 'acc-bob', title: 'Bob Baker'), state),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Bob Baker').first);
      await _settle(tester);

      expect(find.byType(ContactProfileScreen), findsOneWidget);
      // By id, and by *that* id. A profile fetched by name could be anybody's.
      expect(server.lookedUp, contains('acc-bob'));
      expect(find.text('@bob'), findsOneWidget);
    });

    testWidgets('going back leaves the half-written message where it was',
        (tester) async {
      // The requirement this test exists for. Nothing saves or restores the
      // draft: the profile is *pushed*, so the chat's State is never torn down.
      // Replace that push with anything that rebuilds the chat and this fails.
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);
      state.services.store
          .upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));

      await tester.pumpWidget(
        _wrap(const ChatScreen(accountId: 'acc-bob', title: 'Bob'), state),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField).first, 'half a sentence');
      await tester.pump();

      await tester.tap(find.text('Bob').first);
      await _settle(tester);
      expect(find.byType(ContactProfileScreen), findsOneWidget);

      // The app's own back arrow: `pageBack` looks for the framework's, and
      // `PrivioBackButton` exists precisely because that one is not used.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
      await _settle(tester);

      expect(find.text('half a sentence'), findsOneWidget);
    });

    testWidgets('“Message” goes back to that chat rather than stacking a second one',
        (tester) async {
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);
      state.services.store
          .upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));

      await tester.pumpWidget(
        _wrap(const ChatScreen(accountId: 'acc-bob', title: 'Bob'), state),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField).first, 'still here');
      await tester.pump();

      await tester.tap(find.text('Bob').first);
      await _settle(tester);
      await tester.tap(find.text('Message'));
      await _settle(tester);

      expect(find.byType(ContactProfileScreen), findsNothing);
      // One chat, and the same one: a second ChatScreen would be a new State
      // with an empty field.
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('still here'), findsOneWidget);
    });
  });

  group('in a group', () {
    Future<AppState> groupWith(_Server server) async {
      final state = await _signedIn(server);
      state.services.store.upsertGroup(
        const GroupInfo(groupId: 'group-1', role: 'member', name: 'Hiking'),
      );
      state.services.store.append(
        'group-1',
        Message(
          id: 'm1',
          body: 'anybody free on Saturday?',
          sentAt: DateTime(2026, 9, 16, 10),
          isMine: false,
          senderName: 'Cara',
          senderAccountId: 'acc-cara',
        ),
      );
      return state;
    }

    testWidgets('tapping a sender opens that sender, not the group', (tester) async {
      final server = _Server()..give('acc-cara', username: 'cara', displayName: 'Cara');
      final state = await tester.runAsync(() => groupWith(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(
          const ChatScreen(accountId: 'group-1', title: 'Hiking', isGroup: true),
          state,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Cara'));
      await _settle(tester);

      expect(find.byType(ContactProfileScreen), findsOneWidget);
      expect(server.lookedUp, contains('acc-cara'));
      expect(
        server.lookedUp,
        isNot(contains('group-1')),
        reason: 'a group id is not an account and must never be looked up as one',
      );
    });

    testWidgets('the group header still opens the group', (tester) async {
      final server = _Server()..give('acc-cara', username: 'cara', displayName: 'Cara');
      final state = await tester.runAsync(() => groupWith(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(
          const ChatScreen(accountId: 'group-1', title: 'Hiking', isGroup: true),
          state,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Hiking'));
      await _settle(tester);

      expect(find.byType(GroupInfoScreen), findsOneWidget);
      expect(find.byType(ContactProfileScreen), findsNothing);
    });
  });

  group('what the profile shows', () {
    testWidgets('a status and a last-seen time when the server sent them',
        (tester) async {
      final server = _Server()
        ..give(
          'acc-bob',
          username: 'bob',
          displayName: 'Bob',
          statusText: 'On a hike',
          lastSeenAt: DateTime.now().toUtc().toIso8601String(),
        );
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-bob'), state),
      );
      await _settle(tester);

      expect(find.text('On a hike'), findsOneWidget);
      expect(find.textContaining('Last seen'), findsOneWidget);
    });

    testWidgets('and nothing at all where they were withheld', (tester) async {
      // Both come back null when the owner's privacy setting does not include
      // this viewer. The screen draws neither — and, deliberately, no row
      // saying something is hidden: that would publish the one thing the owner
      // decided not to.
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-bob'), state),
      );
      await _settle(tester);

      expect(find.textContaining('Last seen'), findsNothing);
      expect(find.textContaining('hidden', skipOffstage: false), findsNothing);
      expect(find.textContaining('Hidden', skipOffstage: false), findsNothing);
      // The identity is still there: a withheld status is not a broken screen.
      expect(find.text('@bob'), findsOneWidget);
    });

    testWidgets('a deleted account says so instead of spinning', (tester) async {
      final server = _Server();
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-ghost'), state),
      );
      await _settle(tester);

      expect(find.text('This account no longer exists'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('your own profile offers nothing you would do to somebody else',
        (tester) async {
      final server = _Server()..give('acc-alice', username: 'alice', displayName: 'Alice');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-alice'), state),
      );
      await _settle(tester);

      expect(find.text('This is your own profile'), findsOneWidget);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Add to contacts'), findsNothing);
      expect(find.text('Report this account'), findsNothing);
      expect(find.text('Message'), findsNothing);
    });
  });

  group('acting on somebody', () {
    testWidgets('adding and removing a contact, from the server’s answer',
        (tester) async {
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-bob'), state),
      );
      await _settle(tester);

      expect(find.text('Add to contacts'), findsOneWidget);
      await tester.tap(find.text('Add to contacts'));
      await _settle(tester);

      expect(server.contactsOf['acc-alice'], contains('acc-bob'));
      // The row states what the server said, not what the tap hoped.
      expect(find.text('Remove from contacts'), findsOneWidget);
      expect(find.text('Add to contacts'), findsNothing);
    });

    testWidgets('a blocked account says so and offers the way out', (tester) async {
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      server.blockedBy['acc-alice'] = {'acc-bob'};
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-bob'), state),
      );
      await _settle(tester);

      expect(find.text('You blocked this account'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
      // Blocking again is not offered while they are blocked.
      expect(find.text('Block'), findsNothing);

      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unblock').last);
      await _settle(tester);

      expect(server.blockedBy['acc-alice'], isNot(contains('acc-bob')));
      expect(find.text('You blocked this account'), findsNothing);
    });

    testWidgets('blocking from a profile opened in that chat leaves both screens',
        (tester) async {
      // Blocking drops the conversation from this device, as it always has.
      // What is underneath the profile is then a chat that no longer exists, so
      // the profile and the chat both go — one pop would leave somebody looking
      // at it.
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);
      state.services.store
          .upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));

      await tester.pumpWidget(
        _wrap(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const ChatScreen(accountId: 'acc-bob', title: 'Bob'),
            ),
          ),
          state,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Bob').first);
      await _settle(tester);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await _settle(tester);

      expect(server.blockedBy['acc-alice'], contains('acc-bob'));
      expect(find.byType(ContactProfileScreen), findsNothing);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('reporting files a reason and does not block anybody', (tester) async {
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await tester.runAsync(() => _signedIn(server)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        _wrap(const ContactProfileScreen(accountId: 'acc-bob'), state),
      );
      await _settle(tester);

      await tester.tap(find.text('Report this account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await _settle(tester);

      expect(server.reports, [('acc-alice', 'acc-bob', 'spam')]);
      // The two sit next to each other and neither may quietly do the other.
      expect(server.blockedBy['acc-alice'] ?? const <String>{}, isEmpty);
    });
  });

  group('account separation', () {
    test('a second account inherits none of the first one’s profiles', () async {
      final server = _Server()
        ..give('acc-bob', username: 'bob', displayName: 'Bob')
        ..give('acc-alice', username: 'alice');
      final state = await _signedIn(server);
      addTearDown(state.conversations.stop);

      await state.profiles.load('acc-bob');
      expect(state.profiles.viewOf('acc-bob'), isA<ProfileReady>());

      await state.signOut();
      await state.signIn(username: 'carol', password: 'correct-horse');

      expect(
        state.profiles.viewOf('acc-bob'),
        isA<ProfileLoading>(),
        reason: "Carol must not be handed Alice's view of Bob",
      );
      expect(state.profiles.viewerId, 'acc-carol');
    });

    test('binding to another account empties the cache on the spot', () async {
      // Not the same claim as the test above: signing out disposes the
      // controller, so that one holds even if `bindTo` kept everything. This is
      // the path where the controller survives — it is rebound rather than
      // rebuilt — and it is the one where a stale profile would be somebody
      // else's view of a third person.
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await _signedIn(server);
      addTearDown(state.conversations.stop);

      await state.profiles.load('acc-bob');
      expect(state.profiles.viewOf('acc-bob'), isA<ProfileReady>());

      state.profiles.bindTo('acc-carol');
      expect(state.profiles.viewOf('acc-bob'), isA<ProfileLoading>());
    });

    test('an answer that arrives after a switch is dropped, not applied', () async {
      // The case a `mounted` check does not cover: the controller is alive and
      // is simply somebody else's now.
      final server = _Server()..give('acc-bob', username: 'bob', displayName: 'Bob');
      final state = await _signedIn(server);
      addTearDown(state.conversations.stop);

      final inFlight = state.profiles.load('acc-bob');
      state.profiles.bindTo('acc-someone-else');
      await inFlight;

      expect(state.profiles.viewOf('acc-bob'), isA<ProfileLoading>());
    });
  });
}
