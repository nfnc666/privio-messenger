import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/screens/bot_chat_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// The bot chat, on screen.
///
/// The two things worth a widget test rather than a controller test: **there is
/// no text field before the bot is started**, and a pressed button is drawn as
/// pressed rather than offered again.
class _Server {
  _Server({this.startedAlready = false});

  bool startedAlready;
  final List<String> posted = [];
  final List<Map<String, dynamic>> messages = [];
  final Set<String> pressed = {};

  /// Bytes the server will hand back, by media id.
  final Map<String, Uint8List> media = {};

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST') posted.add(path);

        if (path == '/v1/bots/bot-1/start') {
          startedAlready = true;
          return _json({'started': true, 'messageId': 1});
        }
        if (path.endsWith('/press')) {
          pressed.add((jsonDecode(request.body) as Map<String, dynamic>)['buttonId'] as String);
          return _json({'pressed': true, 'already': false});
        }
        if (path == '/v1/bots/bot-1/profile' || path.startsWith('/v1/bots/by-username/')) {
          return _json({
            'id': 'bot-1',
            'username': 'helper',
            'displayName': 'Helper',
            'description': 'Answers questions',
            'commands': [
              {'command': 'help', 'description': 'what I can do'},
            ],
            'isBot': true,
            'started': startedAlready,
            'stopped': false,
          });
        }
        if (path == '/v1/bots/bot-1/messages' && request.method == 'GET') {
          return _json({
            'messages': [
              for (final message in messages)
                {...message, 'pressed': pressed.toList()},
            ],
          });
        }
        // Everything else answers the way `quietServices` does. A signed-in
        // AppState drains envelopes and refreshes contacts on its own, and a 404
        // there is a failure in the harness rather than anything about this
        // screen.
        if (path.startsWith('/v1/media/')) {
          final id = path.split('/').last;
          final bytes = media[id];
          if (bytes == null) return http.Response('{}', 404);
          return http.Response.bytes(bytes, 200,
              headers: {'content-type': 'application/octet-stream'});
        }
        if (path == '/v1/keys/count') return _json(const {'remaining': 100});
        return _json(const {'contacts': [], 'envelopes': [], 'more': false});
      });

  /// A bot message with a file attached.
  void botSentFile({
    required String id,
    required String kind,
    required String name,
    required int size,
    Uint8List? bytes,
  }) {
    if (bytes != null) media[id] = bytes;
    messages.add({
      'id': 11,
      'author': 'bot',
      'text': 'here it is',
      'sentAt': '2026-03-04T10:00:00.000Z',
      'buttons': <Map<String, dynamic>>[],
      'mediaId': bytes == null ? null : id,
      'mediaKind': kind,
      'fileName': name,
      'byteSize': size,
    });
  }

  void botSaid(String text, List<String> buttons) => messages.add({
        'id': 9,
        'author': 'bot',
        'text': text,
        'sentAt': '2026-03-04T10:00:00.000Z',
        'buttons': [
          for (final id in buttons) {'id': id, 'label': id.toUpperCase()},
        ],
      });

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

Future<AppState> _state(_Server server) async {
  final quiet = await quietServices(client: server.client());
  // Seeded through the store's own door, so `initialise` restores a session the
  // way a launch after a sign-in does. The screen needs an account: its
  // controller is per account, and that is the point of it.
  final secure = InMemorySecureStore();
  await secure.writeSession(token: 'session', username: 'ada', accountId: 'me');
  final services = PrivioServices(
    api: PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: server.client())
      ..useToken('session'),
    crypto: quiet.crypto,
    messaging: quiet.messaging,
    channels: quiet.channels,
    recorder: quiet.recorder,
    player: quiet.player,
    backup: quiet.backup,
    store: quiet.store,
    secureStore: secure,
  );
  final state = AppState(services: services, store: secure);
  await state.initialise();
  return state;
}

/// Lets the archive's 400ms sealed-write debounce fire before the tree goes.
///
/// `pumpAndSettle` waits for frames, and that timer schedules no frame, so it
/// would still be pending when the framework checks — which it is right to
/// complain about.
Future<void> _letTimersRun(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 600));

void main() {
  testWidgets('before it is started there is no text field, only Start',
      (tester) async {
    final server = _Server();
    final state = await _state(server);
    // A restored session starts the fallback poll, the expiry sweep and the
    // typing sweep. They are started asynchronously after `initialise`, so they
    // are stopped in a teardown rather than straight after it — none of them is
    // what these tests are about, and a periodic timer outliving the tree is
    // something the framework is right to call out.
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    // Now that the restored session has finished starting its pollers, stop
    // them: they are periodic, they outlive the tree, and none of them is what
    // this test is about.
    state.conversations.stop();

    // The description is what somebody decides on, so it is on the screen.
    expect(find.text('Answers questions'), findsOneWidget);
    expect(find.text('@helper'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'a bot that has not been started must not look ready to write to',
    );
    await _letTimersRun(tester);
  });

  testWidgets('starting says what a bot is first, then opens the field',
      (tester) async {
    final server = _Server();
    final state = await _state(server);
    // A restored session starts the fallback poll, the expiry sweep and the
    // typing sweep. They are started asynchronously after `initialise`, so they
    // are stopped in a teardown rather than straight after it — none of them is
    // what these tests are about, and a periodic timer outliving the tree is
    // something the framework is right to call out.
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    // Now that the restored session has finished starting its pollers, stop
    // them: they are periodic, they outlive the tree, and none of them is what
    // this test is about.
    state.conversations.stop();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // Said before anything is sent, not in a settings screen somewhere.
    expect(
      find.textContaining('not end-to-end encrypted'),
      findsOneWidget,
      reason: 'the one thing somebody has to know was not said',
    );
    expect(server.posted.contains('/v1/bots/bot-1/start'), isFalse);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(server.posted.contains('/v1/bots/bot-1/start'), isTrue);
    expect(find.byType(TextField), findsOneWidget);
    await _letTimersRun(tester);
  });

  testWidgets('a button is drawn from the message and pressed once',
      (tester) async {
    final server = _Server(startedAlready: true)..botSaid('Pick one:', ['yes', 'no']);
    final state = await _state(server);
    // A restored session starts the fallback poll, the expiry sweep and the
    // typing sweep. They are started asynchronously after `initialise`, so they
    // are stopped in a teardown rather than straight after it — none of them is
    // what these tests are about, and a periodic timer outliving the tree is
    // something the framework is right to call out.
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    // Now that the restored session has finished starting its pollers, stop
    // them: they are periodic, they outlive the tree, and none of them is what
    // this test is about.
    state.conversations.stop();

    expect(find.widgetWithText(OutlinedButton, 'YES'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'NO'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'YES'));
    await tester.pumpAndSettle();
    expect(server.pressed, {'yes'});

    // Drawn as pressed, and no longer offered: the server refuses a second
    // press, so a button that still looked live would be a lie.
    expect(find.widgetWithText(OutlinedButton, 'YES · Pressed'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'YES · Pressed'),
    );
    expect(button.onPressed, isNull);
    expect(find.widgetWithText(OutlinedButton, 'NO'), findsOneWidget);
    await _letTimersRun(tester);
  });

  testWidgets('a file is a row with its name and size', (tester) async {
    final server = _Server(startedAlready: true)
      ..botSentFile(
        id: 'media-1',
        kind: 'file',
        name: 'notes.txt',
        size: 2048,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
    final state = await _state(server);
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    state.conversations.stop();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    await _letTimersRun(tester);
  });

  testWidgets('a file the server no longer has says so, and the message stays',
      (tester) async {
    // What an expired blob looks like: the kind and the name survive, the id
    // does not. Drawing nothing would hide a message the bot did send.
    final server = _Server(startedAlready: true)
      ..botSentFile(id: 'media-2', kind: 'file', name: 'gone.txt', size: 10);
    final state = await _state(server);
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    state.conversations.stop();

    expect(find.text('gone.txt'), findsOneWidget);
    expect(find.text('This file is no longer on the server.'), findsOneWidget);
    expect(find.text('here it is'), findsOneWidget);
    await _letTimersRun(tester);
  });

  testWidgets('bytes that are not an image fall back to a file row', (tester) async {
    // The kind came from the bot, and the bot can be wrong. A broken frame
    // would be worse than a row.
    final server = _Server(startedAlready: true)
      ..botSentFile(
        id: 'media-3',
        kind: 'image',
        name: 'cat.png',
        size: 4,
        bytes: Uint8List.fromList([9, 9, 9, 9]),
      );
    final state = await _state(server);
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    state.conversations.stop();

    expect(find.text('This picture could not be shown. Open it as a file.'), findsOneWidget);
    expect(find.text('cat.png'), findsOneWidget);
    await _letTimersRun(tester);
  });

  testWidgets('the command menu offers what the bot published', (tester) async {
    final server = _Server(startedAlready: true);
    final state = await _state(server);
    // A restored session starts the fallback poll, the expiry sweep and the
    // typing sweep. They are started asynchronously after `initialise`, so they
    // are stopped in a teardown rather than straight after it — none of them is
    // what these tests are about, and a periodic timer outliving the tree is
    // something the framework is right to call out.
    addTearDown(state.conversations.stop);
    addTearDown(state.dispose);

    await tester.pumpWidget(wrap(const BotChatScreen(botId: 'bot-1'), state));
    await tester.pumpAndSettle();
    // Now that the restored session has finished starting its pollers, stop
    // them: they are periodic, they outlive the tree, and none of them is what
    // this test is about.
    state.conversations.stop();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('/help'), findsOneWidget);
    expect(find.text('what I can do'), findsOneWidget);
    await _letTimersRun(tester);
  });
}
