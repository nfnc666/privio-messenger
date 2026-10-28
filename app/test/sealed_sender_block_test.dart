import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/sealed_sender.dart';
import 'package:privio/data/message_store.dart';

import 'deletion_test.dart' show buildServices, storeWith;
import 'widget_test.dart' show quietServices;

/// What blocking means once messages can arrive sealed, and the server can no
/// longer drop them: a new profile key, so the blocked account's copy stops
/// opening the door, and the picture moved over to it first.

/// The account's own profile on a server: its picture and its access key.
class ProfileServer {
  String? avatarId;
  final Map<String, List<int>> media = {};
  String? accessKey;
  bool mediaDown = false;
  final Set<String> blocked = {};
  int blocksAsked = 0;
  int _next = 1;

  http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/v1/accounts/me') {
          return _json(200, {'avatarMediaId': avatarId});
        }
        if (request.method == 'POST' && path == '/v1/media') {
          final id = 'm${_next++}';
          media[id] = request.bodyBytes;
          return _json(200, {'id': id});
        }
        if (request.method == 'GET' && path.startsWith('/v1/media/')) {
          if (mediaDown) return _json(503, {'error': 'unavailable', 'message': 'down'});
          return http.Response.bytes(media[path.substring('/v1/media/'.length)]!, 200);
        }
        if (request.method == 'PUT' && path == '/v1/accounts/me/avatar') {
          avatarId = (jsonDecode(request.body) as Map)['mediaId'] as String;
          return _json(200, {});
        }
        if (request.method == 'PUT' && path == '/v1/accounts/me/unidentified-access') {
          accessKey = (jsonDecode(request.body) as Map)['accessKey'] as String;
          return _json(200, {'enabled': true});
        }
        if (request.method == 'POST' && path == '/v1/blocks') {
          blocked.add((jsonDecode(request.body) as Map)['accountId'] as String);
          return _json(200, {});
        }
        if (request.method == 'GET' && path == '/v1/blocks') {
          blocksAsked += 1;
          return _json(200, {
            'blocked': [for (final id in blocked) {'accountId': id}],
          });
        }
        if (request.method == 'GET' && path == '/v1/certificate/trust-root') {
          return _json(503, {'error': 'sealed_sender_unavailable', 'message': 'off'});
        }
        return _json(404, {'error': 'not_found', 'message': path});
      });
}

void main() {
  setUpAll(() async => expect(await SealedSender.load(), isTrue));

  Future<(ConversationController, ProfileServer, PrivioServices)> setUpController() async {
    final server = ProfileServer();
    final (services, _) = await buildServices(storeWith([]), client: server.client());
    final controller = ConversationController(services)..accountId = 'account-alice';
    addTearDown(controller.stop);
    return (controller, server, services);
  }

  group('a new profile key', () {
    test('replaces the old one, and the server gets the access key that goes with it', () async {
      final (controller, server, services) = await setUpController();
      final before = await services.crypto.profileKey();

      expect(await controller.rotateProfileKey(), isTrue);

      final after = await services.crypto.profileKey();
      expect(after, isNot(before));
      expect(server.accessKey, base64Encode(await SealedSender.accessKey(after)));
    });

    test('takes the picture with it, sealed under the new key', () async {
      final (controller, server, services) = await setUpController();
      final picture = Uint8List.fromList(List.generate(200, (i) => i % 256));
      await services.messaging.uploadAvatar(picture);
      final oldId = server.avatarId;

      expect(await controller.rotateProfileKey(), isTrue);

      expect(server.avatarId, isNot(oldId));
      final reopened = await services.messaging.openAvatar(
        server.avatarId!,
        await services.crypto.profileKey(),
      );
      expect(reopened, picture);
    });

    test('is not made when the picture cannot be moved over', () async {
      final (controller, server, services) = await setUpController();
      await services.messaging.uploadAvatar(Uint8List.fromList([1, 2, 3, 4]));
      final before = await services.crypto.profileKey();
      server.mediaDown = true;

      expect(await controller.rotateProfileKey(), isFalse);

      expect(await services.crypto.profileKey(), before);
      expect(server.accessKey, isNull, reason: 'a key nobody can use was published');
    });
  });

  group('blocking', () {
    test('reads the blocked list again, so this device drops what they seal', () async {
      final (controller, server, _) = await setUpController();
      expect(await controller.block('account-bob'), isTrue);
      await pumpEventQueue();
      expect(server.blocked, {'account-bob'});
      expect(server.blocksAsked, greaterThan(0));
    });

    test('changes the profile key where sealed sender is in use, and only there', () async {
      final (controller, server, services) = await setUpController();
      final before = await services.crypto.profileKey();

      // This server does not offer sealed sender, so there is no door to shut.
      await services.sealedSender.start('account-alice');
      await controller.block('account-bob');
      await pumpEventQueue();
      expect(await services.crypto.profileKey(), before);
    });
  });

  testWidgets('a signed-in start knows whose profile key opens whose door, and sets up',
      (tester) async {
    var trustRootAsked = 0;
    final services = await quietServices(
      client: MockClient((request) async {
        if (request.url.path == '/v1/certificate/trust-root') trustRootAsked += 1;
        return http.Response(
          jsonEncode({'contacts': <Object>[], 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final secure = InMemorySecureStore();
    await secure.writeSession(token: 'session', username: 'alice', accountId: 'acc-alice');
    final state = AppState(services: services, store: secure);
    await state.initialise();
    // The native library was loaded outside this test's fake clock, so the
    // start continues on the real event loop: give it a moment of real time.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 1));

    final key = List.generate(32, (i) => i);
    services.store.upsertUser(KnownUser(accountId: 'acc-bob', username: 'bob', profileKey: base64Encode(key)));
    expect(services.messaging.profileKeyOf!('acc-bob'), key);
    expect(services.messaging.profileKeyOf!('acc-nobody'), isNull);
    expect(trustRootAsked, greaterThan(0), reason: 'sealed sender was never started');

    state.conversations.stop();
    await tester.pump(const Duration(seconds: 1));
  });
}
