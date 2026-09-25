import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/failure.dart';
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

/// A group's picture and its description, from the app's side.
///
/// The two are handled differently on purpose — the description is sealed with
/// the group key before it leaves, the picture is not — so the tests that
/// matter are the ones about that seam: what actually goes over the wire, and
/// what a member is allowed to do with it.

/// A real key, so sealing and opening work: base64 of 32 zero bytes.
const groupKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

class FakeServer {
  final List<String> calls = [];
  final List<Map<String, dynamic>> patches = [];
  String? avatarMediaId;
  String? encryptedDescription;
  String role = 'admin';

  /// Whatever the last upload was given, so a test can say which kind it went
  /// as without reading the query string itself.
  final List<String> uploadKinds = [];

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');

        if (request.method == 'POST' && path == '/v1/media') {
          uploadKinds.add(request.url.queryParameters['kind'] ?? 'attachment');
          return _json({'id': 'media-new'}, 201);
        }
        if (request.method == 'GET' && path.startsWith('/v1/media/')) {
          return http.Response.bytes(
            Uint8List.fromList([1, 2, 3, 4]),
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        if (request.method == 'PUT' && path == '/v1/groups/g1/avatar') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          avatarMediaId = body['mediaId'] as String?;
          return _json({'avatarMediaId': avatarMediaId});
        }
        if (request.method == 'DELETE' && path == '/v1/groups/g1/avatar') {
          avatarMediaId = null;
          return _json({'avatarMediaId': null});
        }
        if (request.method == 'PATCH' && path == '/v1/groups/g1') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patches.add(body);
          if (body.containsKey('encryptedDescription')) {
            encryptedDescription = body['encryptedDescription'] as String?;
          }
          return _json({'updated': true});
        }
        if (request.method == 'GET' && path == '/v1/groups') {
          return _json({
            'groups': [
              {
                'id': 'g1',
                'role': role,
                'inviteCode': 'code',
                'memberCount': 2,
                'encryptedMetadata': null,
                'encryptedDescription': encryptedDescription,
                'avatarMediaId': avatarMediaId,
                'avatarUpdatedAt': avatarMediaId == null
                    ? null
                    : DateTime(2026, 9, 25).toIso8601String(),
                'createdAt': DateTime(2026).toIso8601String(),
              },
            ],
          });
        }
        if (request.method == 'GET' && path == '/v1/messages') {
          return _json({'envelopes': [], 'more': false});
        }
        return _json({'error': 'not_found', 'message': path}, 404);
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Future<(PrivioServices, FakeServer, InMemoryMessageStore)> build({
  String role = 'admin',
}) async {
  final server = FakeServer()..role = role;
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secureStore = InMemorySecureStore();

  store.upsertGroup(
    GroupInfo(
      groupId: 'g1',
      role: role,
      name: 'Wanderung',
      groupKey: groupKey,
      memberIds: const ['me', 'them'],
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

/// A tiny valid PNG, so the avatar preparation has something real to work on.
Uint8List picture() => Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));

void main() {
  group('the description', () {
    test('goes to the server sealed, never as the words that were typed',
        () async {
      // The one thing this test exists for: what leaves the device must not be
      // readable, and the way to know is to look at the request body.
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';

      final ok = await controller.describeGroup('g1', 'Planung für Samstag');
      expect(ok, isTrue);

      final sent = server.patches.single['encryptedDescription'] as String;
      expect(
        utf8.decode(base64Decode(sent), allowMalformed: true),
        isNot(contains('Samstag')),
        reason: 'the description went over the wire in the clear',
      );
      // And it is held locally as the words, because this device has the key.
      expect(controller.groupInfo('g1')?.description, 'Planung für Samstag');
    });

    test('comes back as words on a device that has the key', () async {
      final (services, server, store) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.describeGroup('g1', 'Planung für Samstag');

      // A fresh listing, as after a restart: the sealed blob is opened again.
      store.upsertGroup(const GroupInfo(groupId: 'g1', role: 'admin'));
      await controller.refreshGroups();

      expect(controller.groupInfo('g1')?.description, 'Planung für Samstag');
      expect(server.calls, contains('GET /v1/groups'));
    });

    test('and stays sealed on a device that does not', () async {
      // Somebody who joined by a link and has not been sent the key yet sees
      // the group, and neither its name nor its description.
      final (services, server, store) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.describeGroup('g1', 'Planung für Samstag');

      store.clear();
      store.upsertGroup(const GroupInfo(groupId: 'g1', role: 'member'));
      await controller.refreshGroups();

      expect(controller.groupInfo('g1')?.description, isNull);
      expect(server.encryptedDescription, isNotNull, reason: 'the server still has it');
    });

    test('clearing it sends null rather than an empty string', () async {
      // The two are different requests: one removes the description, the other
      // would store a sealed blob containing nothing.
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.describeGroup('g1', 'etwas');
      await controller.describeGroup('g1', '   ');

      expect(server.patches.last['encryptedDescription'], isNull);
      expect(controller.groupInfo('g1')?.description, isNull);
    });

    test('a member is refused before anything is sent', () async {
      final (services, server, _) = await build(role: 'member');
      final controller = ConversationController(services)..accountId = 'me';

      final ok = await controller.describeGroup('g1', 'meins jetzt');
      expect(ok, isFalse);
      expect(controller.failure?.kind, FailureKind.insufficientPermission);
      expect(server.patches, isEmpty, reason: 'nothing should have gone out');
    });

    test('and so is a device without the group key', () async {
      final (services, server, store) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      store.clear();
      store.upsertGroup(const GroupInfo(groupId: 'g1', role: 'admin'));

      final ok = await controller.describeGroup('g1', 'etwas');
      expect(ok, isFalse);
      expect(controller.failure?.kind, FailureKind.groupKeyMissing);
      expect(server.patches, isEmpty);
    });
  });

  group('the picture', () {
    test('goes up as its own kind, and the group is pointed at it', () async {
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';

      final ok = await controller.setGroupAvatar('g1', picture());
      expect(ok, isTrue);
      expect(server.uploadKinds.single, 'group_avatar');
      expect(server.avatarMediaId, 'media-new');
      expect(controller.groupInfo('g1')?.avatarMediaId, 'media-new');
    });

    test('is not sealed — which is what lets it be drawn without the key',
        () async {
      // The trade migration 036 makes, asserted rather than described: a group
      // this device has no key for still shows its picture.
      final (services, _, store) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.setGroupAvatar('g1', picture());

      store.clear();
      store.upsertGroup(const GroupInfo(groupId: 'g1', role: 'member'));
      await controller.refreshGroups();

      expect(controller.groupInfo('g1')?.name, isNull, reason: 'no key, no name');
      expect(controller.groupInfo('g1')?.avatarMediaId, isNotNull);
      expect(await controller.groupAvatar('g1'), isNotNull);
    });

    test('a member may not set one', () async {
      final (services, server, _) = await build(role: 'member');
      final controller = ConversationController(services)..accountId = 'me';

      final ok = await controller.setGroupAvatar('g1', picture());
      expect(ok, isFalse);
      expect(controller.failure?.kind, FailureKind.insufficientPermission);
      expect(server.uploadKinds, isEmpty, reason: 'nothing should have been uploaded');
    });

    test('something that is not a picture is refused before it is uploaded',
        () async {
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';

      final ok = await controller.setGroupAvatar('g1', Uint8List.fromList([1, 2, 3]));
      expect(ok, isFalse);
      expect(controller.failure?.kind, FailureKind.notAnImage);
      expect(server.uploadKinds, isEmpty);
    });

    test('removing it clears the group and the cache', () async {
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.setGroupAvatar('g1', picture());
      expect(await controller.groupAvatar('g1'), isNotNull);

      final ok = await controller.clearGroupAvatar('g1');
      expect(ok, isTrue);
      expect(server.avatarMediaId, isNull);
      expect(controller.groupInfo('g1')?.avatarMediaId, isNull);
      expect(await controller.groupAvatar('g1'), isNull);
    });

    test('and a removal made elsewhere is picked up by the next listing',
        () async {
      final (services, server, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.setGroupAvatar('g1', picture());

      // Another admin removed it. The listing is the whole answer, so this
      // device has to let go of what it was holding.
      server.avatarMediaId = null;
      await controller.refreshGroups();

      expect(controller.groupInfo('g1')?.avatarMediaId, isNull);
    });
  });

  group('what the rest of the group survives', () {
    test('renaming keeps the picture and the description', () async {
      // A `GroupInfo` rebuilt from four fields drops the others, which is
      // exactly how a rename quietly forgets a picture.
      final (services, _, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.setGroupAvatar('g1', picture());
      await controller.describeGroup('g1', 'Planung');

      await controller.renameGroup('g1', 'Neue Wanderung');

      final group = controller.groupInfo('g1');
      expect(group?.name, 'Neue Wanderung');
      expect(group?.avatarMediaId, 'media-new');
      expect(group?.description, 'Planung');
    });

    test('and the chat list draws the picture once it is loaded', () async {
      final (services, _, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.setGroupAvatar('g1', picture());
      await controller.groupAvatar('g1');

      final row = controller.chats.firstWhere((chat) => chat.id == 'g1');
      expect(row.avatarBytes, isNotNull);
    });
  });
}
