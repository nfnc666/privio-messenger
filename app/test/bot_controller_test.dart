import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/bot_controller.dart';
import 'package:privio/core/failure.dart';

/// The owner's side of bots, and the one rule that decides the whole design:
/// **a token is never held anywhere it could be read again.** Not on the
/// controller, not in the conversation, not in a message.
class _Server {
  _Server();

  final List<http.Request> seen = <http.Request>[];
  final List<Map<String, dynamic>> bots = [];
  final List<String> refusals = [];

  /// What the assistant answers next, as the server would.
  Map<String, dynamic> nextReply = {'text': 'ok'};

  String token = 'tok-secret-value';
  int tokensIssued = 0;
  Completer<void>? gate;
  int _next = 0;

  PrivioApiClient client() => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          seen.add(request);
          final pending = gate;
          if (pending != null) await pending.future;

          final path = request.url.path;
          if (refusals.isNotEmpty && request.method != 'GET') {
            return _json({'error': refusals.removeAt(0), 'message': 'refused'}, status: 409);
          }

          if (request.method == 'GET' && path == '/v1/bots') return _json({'bots': bots});

          if (request.method == 'POST' && path == '/v1/bots') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final bot = {
              'id': 'bot-${_next++}',
              'username': body['username'],
              'displayName': body['name'],
              'description': null,
              'commands': <Map<String, dynamic>>[],
              'disabled': false,
            };
            bots.add(bot);
            return _json(bot, status: 201);
          }

          if (request.method == 'PATCH' && path.startsWith('/v1/bots/')) {
            final id = path.split('/')[3];
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final index = bots.indexWhere((bot) => bot['id'] == id);
            bots[index] = {...bots[index], ...body};
            if (body['name'] != null) bots[index]['displayName'] = body['name'];
            return _json(bots[index]);
          }

          if (request.method == 'POST' && path.endsWith('/token')) {
            tokensIssued += 1;
            return _json({'token': token});
          }
          if (request.method == 'DELETE' && path.endsWith('/token')) {
            return _json({'revoked': 1});
          }
          if (request.method == 'DELETE' && path.startsWith('/v1/bots/')) {
            final id = path.split('/')[3];
            bots.removeWhere((bot) => bot['id'] == id);
            return _json({'deleted': true});
          }

          if (request.method == 'POST' && path == '/v1/botcreator/say') {
            return _json(nextReply);
          }
          return _json({'error': 'not_found'}, status: 404);
        }),
      )..useToken('session');

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

void main() {
  group('owning bots', () {
    test('creating one puts it in the list', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');

      final bot = await controller.create(name: 'Helper', username: 'helper_bot');

      expect(bot, isNotNull);
      expect(controller.bots.single.username, 'helper_bot');
      expect(controller.bots.single.name, 'Helper');
      expect(controller.bots.single.disabled, isFalse);
    });

    test('a taken username says so in this app s words', () async {
      final server = _Server()..refusals.add('username_taken');
      final controller = BotController(server.client());
      await controller.load('account-a');

      expect(await controller.create(name: 'Helper', username: 'taken'), isNull);
      expect(controller.failure?.kind, FailureKind.usernameTaken);
    });

    test('switching one off keeps it, and says so', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');
      final bot = await controller.create(name: 'Helper', username: 'helper_bot');

      expect(await controller.update(bot!.id, disabled: true), isTrue);
      expect(controller.byId(bot.id)!.disabled, isTrue);
      expect(controller.bots, hasLength(1), reason: 'off is not gone');
    });

    test('deleting one takes it out of the list', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');
      final bot = await controller.create(name: 'Helper', username: 'helper_bot');

      expect(await controller.delete(bot!.id), isTrue);
      expect(controller.bots, isEmpty);
    });
  });

  group('tokens', () {
    test('are handed to the caller and kept nowhere else', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');
      final bot = await controller.create(name: 'Helper', username: 'helper_bot');

      final token = await controller.issueToken(bot!.id);
      expect(token, 'tok-secret-value');

      // The controller holds no field that could hand it out again. Asserted
      // against the object's own string form, which would show a field if one
      // existed, and against the conversation the screen renders.
      expect(controller.toString().contains('tok-secret-value'), isFalse);
      expect(
        controller.conversation.any((line) => line.text.contains('tok-secret-value')),
        isFalse,
      );
    });

    test('asking again issues a new one rather than repeating the old', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');
      final bot = await controller.create(name: 'Helper', username: 'helper_bot');

      await controller.issueToken(bot!.id);
      server.token = 'tok-second-value';
      final second = await controller.issueToken(bot.id);

      expect(second, 'tok-second-value');
      expect(server.tokensIssued, 2);
    });
  });

  group('the assistant', () {
    test('records both halves of the exchange', () async {
      final server = _Server()..nextReply = {'text': 'What should it be called?'};
      final controller = BotController(server.client());
      await controller.load('account-a');

      await controller.say('/newbot');

      expect(controller.conversation, hasLength(2));
      expect(controller.conversation.first.mine, isTrue);
      expect(controller.conversation.first.text, '/newbot');
      expect(controller.conversation.last.mine, isFalse);
      expect(controller.conversation.last.text, 'What should it be called?');
    });

    test('a token arrives as an instruction, never as text', () async {
      // The assistant answers with an action asking the app to open its
      // protected sheet. Nothing rendered as chat history holds a credential.
      final server = _Server()
        ..nextReply = {
          'text': 'Here is your token.',
          'action': {'kind': 'showToken', 'botId': 'bot-0'},
        };
      final controller = BotController(server.client());
      await controller.load('account-a');

      final reply = await controller.say('/token');

      expect(reply?.showTokenForBotId, 'bot-0');
      expect(controller.conversation.last.text.contains('tok-'), isFalse);
      expect(controller.conversation.last.showTokenForBotId, 'bot-0');
    });

    test('an ordinary reply carries no action', () async {
      final server = _Server()..nextReply = {'text': 'ok'};
      final controller = BotController(server.client());
      await controller.load('account-a');

      final reply = await controller.say('/help');
      expect(reply?.showTokenForBotId, isNull);
      expect(reply?.openBots, isFalse);
    });
  });

  group('bots belong to an account', () {
    test('a switch empties the list and the conversation', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');
      await controller.create(name: 'Helper', username: 'helper_bot');
      await controller.say('/help');
      expect(controller.bots, isNotEmpty);
      expect(controller.conversation, isNotEmpty);

      server.bots.clear();
      await controller.load('account-b');

      expect(controller.bots, isEmpty);
      expect(controller.conversation, isEmpty);
    });

    test('an answer arriving after a switch is dropped, not applied', () async {
      final server = _Server();
      final controller = BotController(server.client());
      await controller.load('account-a');

      server.gate = Completer<void>();
      final inFlight = controller.load('account-a');

      controller.signedOut();
      server.bots.add({
        'id': 'ghost',
        'username': 'ghost_bot',
        'displayName': 'Ghost',
        'commands': <Map<String, dynamic>>[],
        'disabled': false,
      });
      server.gate!.complete();
      await inFlight;

      expect(
        controller.bots,
        isEmpty,
        reason: 'one account s bots must never appear on another',
      );
    });
  });
}
