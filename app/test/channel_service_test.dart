import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

/// A stand-in for the channel endpoints that keeps exactly what the real server
/// keeps — and nothing more. Everything it stores for a private channel is
/// base64 of bytes it cannot read, which is the property the tests below check.
class FakeChannelServer {
  final Map<String, Map<String, dynamic>> channels = {};
  final Map<String, List<Map<String, dynamic>>> posts = {};
  int _nextChannelId = 1;
  int _nextPostId = 1;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        final method = request.method;
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;

        if (method == 'POST' && path == '/v1/channels') {
          final id = 'channel-${_nextChannelId++}';
          channels[id] = {
            'id': id,
            'visibility': body['visibility'],
            'handle': body['handle'],
            'title': body['title'],
            'description': body['description'],
            'category': body['category'],
            'encryptedMetadata': body['encryptedMetadata'],
            'restrictSaving': body['restrictSaving'] ?? false,
            'memberCount': 1,
            'inviteCode': 'invite-$id',
          };
          posts[id] = [];
          return _json(
            {
              ...channels[id]!,
              'role': 'owner',
              'permissions': const {
                'canPost': true,
                'canEditChannel': true,
                'canDeletePosts': true,
                'canManageMembers': true,
                'canDeleteChannel': true,
              },
            },
            201,
          );
        }

        if (method == 'GET' && path == '/v1/channels') {
          return _json({
            'channels': [
              for (final channel in channels.values) {...channel, 'role': 'owner'},
            ],
          });
        }

        final joinMatch = RegExp(r'^/v1/channels/([^/]+)/join$').firstMatch(path);
        if (joinMatch != null && method == 'POST') {
          final channel = channels[joinMatch.group(1)!]!;
          channel['memberCount'] = (channel['memberCount'] as int) + 1;
          return _json({
            'joined': true,
            'role': 'subscriber',
            'permissions': const {'canPost': false},
          });
        }

        final postsMatch = RegExp(r'^/v1/channels/([^/]+)/posts$').firstMatch(path);
        if (postsMatch != null) {
          final id = postsMatch.group(1)!;
          if (method == 'POST') {
            final post = {
              'id': _nextPostId++,
              'authorUsername': 'author',
              'content': body['content'],
              'pinned': false,
              'createdAt': DateTime.utc(2026, 1, 1, 12).toIso8601String(),
            };
            posts[id]!.insert(0, post);
            return _json({'id': post['id'], 'createdAt': post['createdAt']}, 201);
          }
          return _json({'posts': posts[id] ?? const [], 'more': false});
        }

        return http.Response('{"error":"not_found","message":"no route"}', 404);
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Future<ChannelService> _serviceOn(FakeChannelServer server) async {
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final api = PrivioApiClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    client: server.client(),
  );
  api.useToken('token');
  return ChannelService(
    api: api,
    crypto: crypto,
    messaging: MessagingService(api: api, crypto: crypto),
  );
}

void main() {
  group('creating a channel', () {
    test('a private channel uploads its name sealed and nothing else', () async {
      final server = FakeChannelServer();
      final service = await _serviceOn(server);

      final channel = await service.create(
        visibility: ChannelVisibility.private,
        title: 'Reading group',
      );

      final stored = server.channels[channel.id]!;
      expect(stored['title'], isNull, reason: 'the server must not be given the name');
      expect(stored['handle'], isNull);
      expect(stored['description'], isNull);

      final sealed = utf8.decode(
        base64Decode(stored['encryptedMetadata'] as String),
        allowMalformed: true,
      );
      expect(sealed, isNot(contains('Reading group')));

      // The name comes back on this device because the key is on this device.
      expect(channel.title, 'Reading group');
      expect(channel.hasKey, isTrue);
      expect((await service.mine()).single.title, 'Reading group');
    });

    test('a public channel is discoverable by name, and still seals its posts', () async {
      final server = FakeChannelServer();
      final service = await _serviceOn(server);

      final channel = await service.create(
        visibility: ChannelVisibility.public,
        title: 'Privio news',
        handle: 'privio_news',
        description: 'Release notes',
      );

      expect(server.channels[channel.id]!['title'], 'Privio news');

      await service.publish(channel.id, 'Version 1 is out');
      final stored = server.posts[channel.id]!.single['content'] as String;
      expect(
        utf8.decode(base64Decode(stored), allowMalformed: true),
        isNot(contains('Version 1')),
      );
    });
  });

  group('posts', () {
    test('round-trip through the server', () async {
      final server = FakeChannelServer();
      final service = await _serviceOn(server);
      final channel = await service.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );

      await service.publish(channel.id, 'Deploy at 14:00');
      final posts = await service.posts(channel.id);

      expect(posts.single.opened, isTrue);
      expect(posts.single.body, 'Deploy at 14:00');
      expect(posts.single.authorUsername, 'author');
    });

    test('are padded, so the ciphertext does not leak the length', () async {
      final server = FakeChannelServer();
      final service = await _serviceOn(server);
      final channel = await service.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );

      await service.publish(channel.id, 'ok');
      await service.publish(channel.id, 'a much, much longer post than the first one');

      final lengths = [
        for (final post in server.posts[channel.id]!)
          base64Decode(post['content'] as String).length,
      ];
      expect(lengths.first, lengths.last, reason: 'both fall in the same padding bucket');
    });

    test('a device without the key gets locked placeholders, not an empty feed', () async {
      final server = FakeChannelServer();
      final author = await _serviceOn(server);
      final channel = await author.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      await author.publish(channel.id, 'Deploy at 14:00');

      // A second device on the same server that was never handed the key.
      final reader = await _serviceOn(server);
      final posts = await reader.posts(channel.id);

      expect(posts.single.opened, isFalse);
      expect(posts.single.body, isEmpty);
    });

    test('publishing without the key fails instead of sending readable text', () async {
      final server = FakeChannelServer();
      final author = await _serviceOn(server);
      final channel = await author.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );

      final reader = await _serviceOn(server);
      expect(
        () => reader.publish(channel.id, 'anything'),
        throwsA(isA<StateError>()),
      );
      expect(server.posts[channel.id], isEmpty);
    });
  });

  group('membership', () {
    test('joining counts this account, so the header is not one short', () async {
      final server = FakeChannelServer();
      final owner = await _serviceOn(server);
      final channel = await owner.create(
        visibility: ChannelVisibility.public,
        title: 'Privio news',
        handle: 'privio_news',
      );
      expect(channel.memberCount, 1);
      expect(channel.memberLabel, '1 member');

      final joiner = await _serviceOn(server);
      final joined = await joiner.join(channel);
      expect(joined.memberCount, 2);
      expect(joined.memberLabel, '2 members');
      expect(joined.role, 'subscriber');
    });
  });

  group('invite links', () {
    test('carry no key, so they are safe to post anywhere', () async {
      final server = FakeChannelServer();
      final service = await _serviceOn(server);
      final channel = await service.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );

      final key = (await service.keyFor(channel.id))!;
      final link = ChannelService.linkForChannel(channel.inviteCode!);

      expect(link, 'https://privio.channel/c/${channel.inviteCode}');
      expect(link, isNot(contains('#')));
      expect(link, isNot(contains(base64Url.encode(key))));
      expect(link, isNot(contains(base64Encode(key))));
    });

    test('round-trip through the parser, for a channel and for a group', () {
      final channelLink = ChannelService.linkForChannel('abc123');
      final groupLink = ChannelService.linkForGroup('xyz789');

      expect(ChannelService.parseInviteLink(channelLink)!.code, 'abc123');
      expect(ChannelService.parseInviteLink(channelLink)!.kind, InviteKind.channel);
      expect(ChannelService.parseInviteLink(groupLink)!.code, 'xyz789');
      expect(ChannelService.parseInviteLink(groupLink)!.kind, InviteKind.group);
    });

    test('rubbish is rejected rather than half-accepted', () {
      expect(ChannelService.parseInviteLink('https://privio.channel/'), isNull);
      expect(ChannelService.parseInviteLink('not a link at all'), isNull);
      expect(ChannelService.parseInviteLink('https://privio.channel/c/'), isNull);
    });
  });

  group('key delivery', () {
    test('a key sealed into a payload survives encoding, and shows as a key', () {
      final key = base64Encode(List<int>.generate(32, (i) => i));
      final payload = MessagePayload.key(
        keyScope: 'channel',
        keyScopeId: 'channel-1',
        deliveredKey: key,
      );

      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isKeyDelivery, isTrue);
      expect(decoded.keyScope, 'channel');
      expect(decoded.keyScopeId, 'channel-1');
      expect(decoded.deliveredKey, key);
      // Nothing about it should read as something to show in a chat.
      expect(decoded.body, isEmpty);
      expect(decoded.isMedia, isFalse);
    });

    test('an ordinary message is not mistaken for a key', () {
      final decoded = MessagePayload.decode(const MessagePayload.text('hallo').encode());
      expect(decoded.isKeyDelivery, isFalse);
      expect(decoded.deliveredKey, isNull);
    });

    test('a delivered key opens the posts it was sent for', () async {
      final server = FakeChannelServer();
      final author = await _serviceOn(server);
      final channel = await author.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      await author.publish(channel.id, 'Deploy at 14:00');

      final joiner = await _serviceOn(server);
      expect((await joiner.posts(channel.id)).single.opened, isFalse);

      // What the delivery message carries, applied on the other side.
      await joiner.rememberKey(channel.id, (await author.keyFor(channel.id))!);
      final posts = await joiner.posts(channel.id);
      expect(posts.single.opened, isTrue);
      expect(posts.single.body, 'Deploy at 14:00');
    });
  });
}
