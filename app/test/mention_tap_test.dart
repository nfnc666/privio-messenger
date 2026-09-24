import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/app_state.dart';
import 'package:privio/core/mention_resolver.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/contact_profile_screen.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/widgets/linked_text.dart';

import 'widget_test.dart' show quietServices, wrap;

/// Tapping an `@name`.
///
/// The half that matters is the one a unit test cannot reach: what the *tap*
/// does. Everything here goes through a server that answers by username, so
/// each test can say which account was asked for and which profile was opened.

/// Every request the app made, so a test can assert what was **not** asked.
late List<String> asked;

http.Client _server({
  Map<String, Map<String, dynamic>> byUsername = const {},
  int unknownStatus = 404,
  bool offline = false,
}) =>
    MockClient((request) async {
      asked.add('${request.method} ${request.url.path}');
      if (offline) throw const SocketishFailure();
      final path = request.url.path;
      if (path.startsWith('/v1/users/id/')) {
        final id = path.substring('/v1/users/id/'.length);
        final hit = byUsername.values.where((p) => p['id'] == id).firstOrNull;
        if (hit == null) {
          return http.Response(
            jsonEncode(const {'error': 'user_not_found', 'message': 'no'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({...hit, 'isContact': false, 'isBlocked': false}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.startsWith('/v1/users/')) {
        final name = path.substring('/v1/users/'.length);
        final hit = byUsername[name];
        if (hit == null) {
          return http.Response(
            jsonEncode(const {'error': 'user_not_found', 'message': 'no'}),
            unknownStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(hit),
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

class SocketishFailure implements Exception {
  const SocketishFailure();
}

Map<String, dynamic> profile(String username, String id, {String? display}) => {
      'id': id,
      'username': username,
      'displayName': display,
      'avatarMediaId': null,
      'avatarUpdatedAt': null,
    };

Future<AppState> signedIn(http.Client client) async {
  final state = AppState(
    services: await quietServices(client: client),
    store: InMemorySecureStore(),
  );
  await state.initialise();
  state.conversations.accountId = 'acc-me';
  return state;
}

Message said(String body, {String id = 'm1'}) => Message(
      id: id,
      clientId: id,
      body: body,
      sentAt: DateTime(2026, 9, 24, 10),
      isMine: false,
    );

void main() {
  setUp(() => asked = []);

  group('a mention in a one-to-one chat', () {
    testWidgets('is drawn in the accent, and opens the right profile',
        (tester) async {
      final state = await signedIn(
        _server(byUsername: {'max': profile('max', 'acc-max', display: 'Max')}),
      );
      addTearDown(state.conversations.stop);
      state.services.store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob'),
      );
      state.services.store.append('acc-bob', said('Schreib bitte @max'));

      await tester.pumpWidget(
        wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Nothing was looked up merely by reading the chat.
      expect(
        asked.where((r) => r.contains('/v1/users/')),
        isEmpty,
        reason: 'a chat full of names must not become a chat full of lookups',
      );

      final span = _mentionSpan(tester, '@max');
      expect(
        span.style?.color,
        tester.element(find.byType(ChatScreen)).accents.accent,
      );

      _tap(span);
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsOneWidget);
      expect(asked, contains('GET /v1/users/max'));
      final screen = tester.widget<ContactProfileScreen>(
        find.byType(ContactProfileScreen),
      );
      expect(screen.accountId, 'acc-max', reason: 'opened by id, not by name');
    });

    testWidgets('several in one message each open their own', (tester) async {
      final state = await signedIn(
        _server(byUsername: {
          'max': profile('max', 'acc-max'),
          'lena': profile('lena', 'acc-lena'),
        }),
      );
      addTearDown(state.conversations.stop);
      state.services.store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob'),
      );
      state.services.store.append('acc-bob', said('@max und @lena, kommt ihr?'));

      await tester.pumpWidget(
        wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state),
      );
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@lena'));
      await tester.pumpAndSettle();

      final screen = tester.widget<ContactProfileScreen>(
        find.byType(ContactProfileScreen),
      );
      expect(screen.accountId, 'acc-lena');
    });

    testWidgets('a photo caption behaves like any other text', (tester) async {
      final state = await signedIn(
        _server(byUsername: {'max': profile('max', 'acc-max')}),
      );
      addTearDown(state.conversations.stop);
      state.services.store.upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob'),
      );
      state.services.store.append(
        'acc-bob',
        Message(
          id: 'p1',
          clientId: 'p1',
          body: 'Das ist @max',
          kind: MessageKind.photo,
          sentAt: DateTime(2026, 9, 24, 10),
          isMine: false,
        ),
      );

      await tester.pumpWidget(
        wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state),
      );
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@max'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsOneWidget);
    });
  });

  group('a mention in a group', () {
    testWidgets('opens the mentioned person, not the group', (tester) async {
      final state = await signedIn(
        _server(byUsername: {'max': profile('max', 'acc-max')}),
      );
      addTearDown(state.conversations.stop);
      state.services.store.upsertGroup(
        const GroupInfo(
          groupId: 'grp-1',
          role: 'member',
          name: 'Team',
          memberIds: ['acc-me', 'acc-max'],
        ),
      );
      state.services.store.append('grp-1', said('Frag mal @max'));

      await tester.pumpWidget(
        wrap(
          const ChatScreen(accountId: 'grp-1', title: 'Team', isGroup: true),
          state,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@max'));
      await tester.pumpAndSettle();

      final screen = tester.widget<ContactProfileScreen>(
        find.byType(ContactProfileScreen),
      );
      expect(screen.accountId, 'acc-max');
      expect(screen.returnToChat, isFalse, reason: 'this is not max’s own chat');
    });
  });

  group('a mention in a channel post', () {
    testWidgets('is tappable there too', (tester) async {
      final state = await signedIn(
        _server(byUsername: {'max': profile('max', 'acc-max')}),
      );
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        wrap(const _PostBody('Danke an @max für den Hinweis'), state),
      );
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@max'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsOneWidget);
    });

    testWidgets('and an address in the same post is still not one', (tester) async {
      final state = await signedIn(_server());
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(
        wrap(const _PostBody('Schreib an max@example.com'), state),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final spans = _spansOf(tester);
      expect(spans.any((s) => s.recognizer != null), isFalse);
    });
  });

  group('when the name leads nowhere', () {
    testWidgets('an unknown account says so and opens nothing', (tester) async {
      final state = await signedIn(_server());
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(wrap(const _PostBody('Frag @nobody'), state));
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@nobody'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsNothing);
      expect(find.textContaining('no such username'), findsOneWidget);
    });

    testWidgets('a deleted account is the same answer', (tester) async {
      // The server answers 404 for an account it has erased, exactly as for
      // one that never existed — and it must read as "nothing opened" either
      // way rather than as a crash.
      final state = await signedIn(_server(unknownStatus: 404));
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(wrap(const _PostBody('Frag @gone'), state));
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@gone'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsNothing);
    });

    testWidgets('offline says to check the connection, and opens nothing',
        (tester) async {
      final state = await signedIn(_server(offline: true));
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(wrap(const _PostBody('Frag @max'), state));
      await tester.pump(const Duration(milliseconds: 100));

      _tap(_mentionSpan(tester, '@max'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactProfileScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the resolver itself', () {
    test('a reply about a different name opens nothing', () async {
      // Should never happen. If it ever does, the failure has to be "nothing
      // opened" and not "somebody else's profile opened".
      final state = await signedIn(
        _server(byUsername: {'max': profile('someone.else', 'acc-else')}),
      );
      addTearDown(state.conversations.stop);

      final result = await MentionResolver(state.services.api).resolve('max');
      expect(result, isA<MentionUnavailable>());
    });

    test('a name the server will not even look up is unknown, not an error',
        () async {
      final state = await signedIn(_server(unknownStatus: 400));
      addTearDown(state.conversations.stop);

      final result = await MentionResolver(state.services.api).resolve('xx');
      expect(result, isA<MentionUnknown>());
    });

    test('case is not a different account', () async {
      final state = await signedIn(
        _server(byUsername: {'max': profile('max', 'acc-max')}),
      );
      addTearDown(state.conversations.stop);

      final result = await MentionResolver(state.services.api).resolve('MAX');
      expect((result as MentionFound).accountId, 'acc-max');
      expect(asked, contains('GET /v1/users/max'));
    });
  });
}

/// A channel post's body, drawn the way the feed draws it.
class _PostBody extends StatelessWidget {
  const _PostBody(this.body);

  final String body;

  @override
  Widget build(BuildContext context) => Scaffold(body: LinkedText(body));
}

List<TextSpan> _spansOf(WidgetTester tester) {
  final spans = <TextSpan>[];
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    widget.text.visitChildren((span) {
      if (span is TextSpan) spans.add(span);
      return true;
    });
  }
  return spans;
}

TextSpan _mentionSpan(WidgetTester tester, String text) {
  final hit = _spansOf(tester).where((s) => s.text == text && s.recognizer != null);
  expect(hit, hasLength(1), reason: 'expected exactly one tappable $text');
  return hit.single;
}

void _tap(TextSpan span) => (span.recognizer! as dynamic).onTap();
