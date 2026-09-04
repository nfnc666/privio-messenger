import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

/// Records what the client asked of the server, and answers as the server does.
class FakeGroupServer {
  final List<String> calls = [];
  final List<Map<String, dynamic>> patches = [];
  bool amAdmin = true;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');

        if (request.method == 'GET' && path == '/v1/messages') {
          return _json({'envelopes': [], 'more': false});
        }
        if (request.method == 'POST' && path.endsWith('/key-requests')) {
          return _json({'requested': true});
        }
        if (request.method == 'GET' && path.endsWith('/key-requests')) {
          return _json({'requests': []});
        }
        if (request.method == 'GET' && path == '/v1/groups/g1') {
          return _json({
            'id': 'g1',
            'role': amAdmin ? 'admin' : 'member',
            'members': [
              {'id': 'me', 'username': 'anna', 'role': amAdmin ? 'admin' : 'member'},
              {'id': 'them', 'username': 'bob', 'role': 'member'},
            ],
          });
        }
        if (request.method == 'PATCH' && path == '/v1/groups/g1') {
          patches.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _json({'ok': true});
        }
        if (request.method == 'DELETE' && path.startsWith('/v1/groups/g1/members/')) {
          if (!amAdmin && !path.endsWith('/me')) {
            return _json({'error': 'forbidden', 'message': 'Admins only'}, 403);
          }
          return _json({'ok': true});
        }
        if (request.method == 'DELETE' && path == '/v1/groups/g1') {
          if (!amAdmin) return _json({'error': 'forbidden', 'message': 'Admins only'}, 403);
          return _json({'deleted': true});
        }
        return _json({'error': 'not_found', 'message': path}, 404);
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Future<(PrivioServices, FakeGroupServer, InMemoryMessageStore)> build() async {
  final server = FakeGroupServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secureStore = InMemorySecureStore();

  store.upsertGroup(
    const GroupInfo(
      groupId: 'g1',
      role: 'admin',
      name: 'Wanderung',
      // Base64 of 32 zero bytes: a real key, so sealing the name works.
      groupKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      memberIds: ['me', 'them'],
    ),
  );
  store.append(
    'g1',
    Message(id: 'm1', clientId: 'c1', body: 'hallo', sentAt: DateTime(2026), isMine: false),
  );

  return (
    PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      recorder: FakeVoiceRecorder(),
      player: FakeVoicePlayer(),
      store: store,
      secureStore: secureStore,
      backup: BackupService(api: api, store: secureStore, messages: store),
      archive: EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      ),
    ),
    server,
    store,
  );
}

void main() {
  test('the member list comes from the server, not from memory', () async {
    final (services, server, _) = await build();
    final controller = ConversationController(services)..accountId = 'me';

    final members = await controller.groupMembers('g1');
    expect(members.map((m) => m.username), ['anna', 'bob']);
    expect(members.first.isAdmin, isTrue);
    expect(server.calls, contains('GET /v1/groups/g1'));
  });

  test('leaving takes the conversation with it', () async {
    final (services, server, store) = await build();
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.leaveGroup('g1'), isTrue);
    expect(server.calls, contains('DELETE /v1/groups/g1/members/me'));
    expect(
      store.conversationWith('g1'),
      isNull,
      reason: 'a room nobody in it can write to is not a chat',
    );
  });

  test('a refused leave changes nothing here', () async {
    final (services, server, store) = await build();
    final controller = ConversationController(services)..accountId = 'nobody';
    server.amAdmin = false;

    expect(await controller.leaveGroup('g1'), isFalse);
    expect(store.conversationWith('g1'), isNotNull);
    expect(controller.error, isNotNull);
  });

  test('removing somebody else is the same call, aimed elsewhere', () async {
    final (services, server, store) = await build();
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.removeFromGroup('g1', 'them'), isTrue);
    expect(server.calls, contains('DELETE /v1/groups/g1/members/them'));
    expect(
      store.conversationWith('g1'),
      isNotNull,
      reason: 'removing someone else does not remove the group from here',
    );
  });

  test('a member who tries to remove someone is refused by the server', () async {
    // The screen hides the control from a member; the rule itself is the
    // server's, which is the only place it counts.
    final (services, server, store) = await build();
    server.amAdmin = false;
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.removeFromGroup('g1', 'them'), isFalse);
    expect(controller.error, contains('Admins only'));
    expect(store.conversationWith('g1'), isNotNull);
  });

  test('renaming seals the new name and keeps it here', () async {
    final (services, server, store) = await build();
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.renameGroup('g1', 'Gipfeltour'), isTrue);
    expect(store.conversationWith('g1')!.group!.name, 'Gipfeltour');
    expect(server.patches, hasLength(1));

    final sealed = server.patches.single['encryptedMetadata'] as String;
    expect(
      utf8.decode(base64Decode(sealed), allowMalformed: true),
      isNot(contains('Gipfeltour')),
      reason: 'the server stores a name it cannot read',
    );
  });

  test('a device without the group key cannot rename what it cannot name', () async {
    // What joining by a link looks like before anyone has sent the key.
    final (services, server, store) = await build();
    store.upsertGroup(
      const GroupInfo(groupId: 'g2', role: 'admin', name: 'Ohne Schluessel'),
    );
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.renameGroup('g2', 'Gipfeltour'), isFalse);
    expect(server.patches, isEmpty);
    expect(controller.error, contains('group key'));
  });

  group('the group key', () {
    test('is asked for where this device is a member without one', () async {
      // What a second phone looks like: the membership is there, the key is
      // not, and nothing recorded a request because it never joined.
      final (services, server, store) = await build();
      store.upsertGroup(const GroupInfo(groupId: 'g2', role: 'member'));
      final controller = ConversationController(services)..accountId = 'me';
      store.append(
        'g2',
        Message(id: 'x', clientId: 'x', body: '', sentAt: DateTime(2026), isMine: false),
      );

      await controller.drain();
      // The maintenance is fired off rather than awaited by drain, so that a
      // slow key exchange never holds up delivering messages.
      await pumpEventQueue();
      expect(
        server.calls,
        contains('POST /v1/groups/g2/key-requests'),
        reason: 'otherwise it waits at "waiting for the group key" forever',
      );
    });

    test('is offered where this device has one', () async {
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';

      await controller.drain();
      await pumpEventQueue();
      expect(server.calls, contains('GET /v1/groups/g1/key-requests'));
      expect(
        server.calls.where((c) => c == 'POST /v1/groups/g1/key-requests'),
        isEmpty,
        reason: 'a device that has the key has nothing to ask for',
      );
    });
  });

  test('deleting the group removes it here as well', () async {
    final (services, server, store) = await build();
    final controller = ConversationController(services)..accountId = 'me';

    expect(await controller.deleteGroup('g1'), isTrue);
    expect(server.calls, contains('DELETE /v1/groups/g1'));
    expect(store.conversationWith('g1'), isNull);
  });
}
