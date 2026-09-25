import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/bot_chat_controller.dart';
import 'package:privio/core/failure.dart';

/// Talking to a bot somebody else runs.
///
/// What these are about: a bot cannot write before it is started, a button is
/// pressed once and then shown as pressed, and nothing from one bot ever
/// appears under another — or under another account.
class _Server {
  _Server();

  final List<http.Request> seen = <http.Request>[];

  /// Per bot: whether this account has started it, and whether it stopped it.
  final Map<String, bool> started = {};
  final Map<String, bool> stopped = {};

  /// Per bot: the conversation, as the server would answer it.
  final Map<String, List<Map<String, dynamic>>> conversations = {};

  /// A code to refuse the next write with, as the server would.
  String? refuseWith;

  PrivioApiClient client() => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          seen.add(request);
          final path = request.url.path;

          final byName = RegExp(r'^/v1/bots/by-username/(.+)$').firstMatch(path);
          if (request.method == 'GET' && byName != null) {
            final username = byName.group(1)!;
            if (username != 'helper') {
              return _json({'error': 'bot_not_found', 'message': 'no'}, status: 404);
            }
            return _json(_profile('bot-1', 'helper'));
          }

          final profile = RegExp(r'^/v1/bots/([^/]+)/profile$').firstMatch(path);
          if (request.method == 'GET' && profile != null) {
            final id = profile.group(1)!;
            if (id != 'bot-1' && id != 'bot-2') {
              return _json({'error': 'bot_not_found', 'message': 'no'}, status: 404);
            }
            return _json(_profile(id, id == 'bot-1' ? 'helper' : 'other'));
          }

          final messages = RegExp(r'^/v1/bots/([^/]+)/messages$').firstMatch(path);
          if (request.method == 'GET' && messages != null) {
            return _json({'messages': conversations[messages.group(1)] ?? []});
          }

          if (refuseWith != null && request.method == 'POST') {
            final code = refuseWith!;
            refuseWith = null;
            return _json({'error': code, 'message': 'refused'}, status: 403);
          }

          final start = RegExp(r'^/v1/bots/([^/]+)/start$').firstMatch(path);
          if (request.method == 'POST' && start != null) {
            final id = start.group(1)!;
            started[id] = true;
            stopped[id] = false;
            (conversations[id] ??= []).add({
              'id': 1,
              'author': 'user',
              'text': '/start',
              'sentAt': '2026-03-04T10:00:00.000Z',
              'buttons': <Map<String, dynamic>>[],
              'pressed': <String>[],
            });
            return _json({'started': true, 'messageId': 1});
          }

          final stop = RegExp(r'^/v1/bots/([^/]+)/stop$').firstMatch(path);
          if (request.method == 'POST' && stop != null) {
            started[stop.group(1)!] = false;
            stopped[stop.group(1)!] = true;
            return _json({'stopped': true});
          }

          final press = RegExp(r'^/v1/bots/([^/]+)/messages/(\d+)/press$').firstMatch(path);
          if (request.method == 'POST' && press != null) {
            final id = press.group(1)!;
            final messageId = int.parse(press.group(2)!);
            final buttonId = (jsonDecode(request.body) as Map<String, dynamic>)['buttonId'];
            final list = conversations[id] ?? [];
            for (final message in list) {
              if (message['id'] == messageId) {
                final pressed = (message['pressed'] as List).cast<String>().toList();
                final already = pressed.contains(buttonId);
                if (!already) pressed.add(buttonId as String);
                message['pressed'] = pressed;
                return _json({'pressed': true, 'already': already});
              }
            }
            return _json({'error': 'message_not_found', 'message': 'no'}, status: 404);
          }

          final send = RegExp(r'^/v1/bots/([^/]+)/messages$').firstMatch(path);
          if (request.method == 'POST' && send != null) {
            final id = send.group(1)!;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            (conversations[id] ??= []).add({
              'id': (conversations[id]!.length + 1),
              'author': 'user',
              'text': body['text'],
              'sentAt': '2026-03-04T10:01:00.000Z',
              'buttons': <Map<String, dynamic>>[],
              'pressed': <String>[],
            });
            return _json({'messageId': conversations[id]!.length}, status: 201);
          }

          return _json({'error': 'not_found'}, status: 404);
        }),
      )..useToken('session');

  Map<String, dynamic> _profile(String id, String username) => {
        'id': id,
        'username': username,
        'displayName': username == 'helper' ? 'Helper' : 'Other',
        'description': 'Answers questions',
        'commands': [
          {'command': 'help', 'description': 'what I can do'},
        ],
        'isBot': true,
        'started': started[id] ?? false,
        'stopped': stopped[id] ?? false,
      };

  /// Puts a bot message with buttons into a conversation.
  void botSaid(String botId, int id, String text, List<String> buttons) {
    (conversations[botId] ??= []).add({
      'id': id,
      'author': 'bot',
      'text': text,
      'sentAt': '2026-03-04T10:02:00.000Z',
      'buttons': [for (final b in buttons) {'id': b, 'label': b.toUpperCase()}],
      'pressed': <String>[],
    });
  }

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

void main() {
  group('opening a bot', () {
    test('by exact username, with its description and commands', () async {
      final server = _Server();
      final controller = BotChatController(server.client());

      final profile = await controller.openByUsername('me', 'helper');
      expect(profile, isNotNull);
      expect(profile!.description, 'Answers questions');
      expect(profile.commands.single.command, 'help');
      expect(profile.started, isFalse);
      expect(controller.failure, isNull);
    });

    test('a name that is not a bot is its own failure, not a crash', () async {
      final server = _Server();
      final controller = BotChatController(server.client());

      expect(await controller.openByUsername('me', 'nobody'), isNull);
      expect(controller.failure?.kind, FailureKind.botNotFound);
      expect(controller.profile, isNull);
    });

    test('opening a second bot does not carry the first one s messages',
        () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      server.botSaid('bot-1', 7, 'from the first bot', const []);

      await controller.openByUsername('me', 'helper');
      expect(controller.messages.single.text, 'from the first bot');

      await controller.open('me', 'bot-2');
      expect(
        controller.messages.any((m) => m.text == 'from the first bot'),
        isFalse,
        reason: 'one bot s message appeared under another',
      );
    });
  });

  group('starting and stopping', () {
    test('start makes the field appear, and delivers /start', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      await controller.openByUsername('me', 'helper');

      expect(await controller.start(), isTrue);
      expect(controller.profile!.started, isTrue);
      expect(controller.messages.single.text, '/start');
    });

    test('stop is reflected, and a refusal says what to do about it', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      await controller.openByUsername('me', 'helper');
      await controller.start();

      expect(await controller.stop(), isTrue);
      expect(controller.profile!.stopped, isTrue);
      expect(controller.profile!.started, isFalse);

      // What the server answers to a write after a stop, and the words the
      // screen then has for it: press Start, not "something went wrong".
      server.refuseWith = 'not_contacted';
      expect(await controller.send('hello?'), isFalse);
      expect(controller.failure?.kind, FailureKind.botNotStarted);
    });
  });

  group('a button', () {
    test('is read from what the bot sent', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      server.botSaid('bot-1', 9, 'Pick one:', const ['yes', 'no']);

      await controller.openByUsername('me', 'helper');
      final message = controller.messages.single;
      expect(message.buttons.map((b) => b.id), ['yes', 'no']);
      expect(message.buttons.first.label, 'YES');
      expect(message.pressed, isEmpty);
    });

    test('shows as pressed afterwards, so it is not offered twice', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      server.botSaid('bot-1', 9, 'Pick one:', const ['yes', 'no']);
      await controller.openByUsername('me', 'helper');
      await controller.start();

      expect(await controller.press(9, 'yes'), isTrue);
      final message = controller.messages.firstWhere((m) => m.id == 9);
      expect(message.pressed, contains('yes'));
      expect(message.pressed, isNot(contains('no')));
    });

    test('a press on a message that is gone is a failure, not a crash', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      await controller.openByUsername('me', 'helper');

      expect(await controller.press(4242, 'yes'), isFalse);
      expect(controller.failure?.kind, FailureKind.botNotFound);
    });
  });

  group('per account', () {
    test('signing out leaves nothing behind', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      server.botSaid('bot-1', 3, 'hello', const []);
      await controller.openByUsername('me', 'helper');
      expect(controller.messages, isNotEmpty);

      controller.signedOut();
      expect(controller.messages, isEmpty);
      expect(controller.profile, isNull);
      expect(controller.botId, isNull);
      expect(controller.accountId, isNull);
    });

    test('an answer for the previous account is dropped, not drawn', () async {
      final server = _Server();
      final controller = BotChatController(server.client());
      server.botSaid('bot-1', 3, 'for the first account', const []);

      // Opened as one account, then the account changes while that is in
      // flight. The late answer belongs to nobody on screen.
      final pending = controller.openByUsername('first', 'helper');
      await controller.openByUsername('second', 'helper');
      await pending;

      expect(controller.accountId, 'second');
    });
  });
}
