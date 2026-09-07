import 'dart:convert';
import 'dart:typed_data';

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

  /// Which key version each channel is on, and who claimed it.
  ///
  /// Modelled here rather than stubbed, because the rules being tested are
  /// about exactly this: the epoch goes up on removal, the first claim wins,
  /// and a post under a superseded version is refused. A fake that simply said
  /// yes would test nothing.
  final Map<String, int> epochs = {};
  final Map<String, Map<int, String>> claims = {};

  /// Who is in each channel, so a removal is something that happens rather
  /// than something the test asserts about a counter.
  final Map<String, Set<String>> members = {};

  /// Set to refuse the next claim, standing in for another device winning the
  /// race by a few milliseconds.
  String? claimAlreadyHeldBy;

  /// When true the claim is recorded and the reply is thrown away, which is
  /// what a dropped connection looks like from the client: the server did the
  /// thing, the device never found out.
  bool loseClaimReply = false;

  /// Which epochs were abandoned as orphans.
  final List<int> abandoned = [];

  /// Which key version each channel's sealed name is under.
  final Map<String, int> metadataEpochs = {};

  /// How many times a channel's sealed name has actually been written.
  final Map<String, int> metadataWrites = {};

  /// When true, every attempt to re-seal the name fails — the device rotated
  /// the key and then lost the connection before the name followed it.
  bool failMetadataUpdate = false;

  int _nextChannelId = 1;
  int _nextPostId = 1;

  /// Advances a channel to its next key version, as removal and leaving do.
  int rotate(String channelId) => epochs[channelId] = (epochs[channelId] ?? 1) + 1;

  int epochOf(String channelId) => epochs[channelId] ?? 1;

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
          epochs[id] = 1;
          metadataEpochs[id] = 1;
          claims[id] = {1: body['keyId'] as String? ?? 'created-epoch-1'};
          members[id] = {'author'};
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

        final oneMatch = RegExp(r'^/v1/channels/([^/]+)$').firstMatch(path);
        if (oneMatch != null && method == 'GET') {
          final id = oneMatch.group(1)!;
          final channel = channels[id];
          if (channel == null) {
            return http.Response('{"error":"not_found","message":"no channel"}', 404);
          }
          return _json({
            ...channel,
            'role': 'owner',
            'keyEpoch': epochOf(id),
            'metadataKeyEpoch': metadataEpochs[id] ?? 1,
          });
        }

        final epochMatch =
            RegExp(r'^/v1/channels/([^/]+)/key-epochs/current$').firstMatch(path);
        if (epochMatch != null && method == 'GET') {
          final id = epochMatch.group(1)!;
          return _json({'epoch': epochOf(id), 'keyId': claims[id]?[epochOf(id)]});
        }

        final claimMatch = RegExp(r'^/v1/channels/([^/]+)/key-epochs$').firstMatch(path);
        if (claimMatch != null && method == 'POST') {
          final id = claimMatch.group(1)!;
          final epoch = (body['epoch'] as num).toInt();
          if (epoch != epochOf(id)) {
            return _json(
              {'error': 'not_the_current_epoch', 'message': 'superseded'},
              409,
            );
          }
          final held = claims.putIfAbsent(id, () => {});
          // A claim that lost the race: either somebody really got there first,
          // or the test asked for that to be what happened.
          held[epoch] ??= claimAlreadyHeldBy ?? body['keyId'] as String;
          if (loseClaimReply) {
            // Recorded, then the connection dies. The client must be able to
            // come back and find out what happened to it.
            return http.Response('', 502);
          }
          return _json({
            'epoch': epoch,
            'keyId': held[epoch],
            'claimed': held[epoch] == body['keyId'],
          });
        }

        final abandonMatch =
            RegExp(r'^/v1/channels/([^/]+)/key-epochs/abandon$').firstMatch(path);
        if (abandonMatch != null && method == 'POST') {
          final id = abandonMatch.group(1)!;
          final epoch = (body['epoch'] as num).toInt();
          if (epoch != epochOf(id)) {
            return _json({'error': 'not_the_current_epoch', 'message': 'stale'}, 409);
          }
          // The server refuses to abandon a version somebody has published
          // under — an epoch with posts is not an orphan.
          if (posts[id]!.any((p) => p['keyEpoch'] == epoch)) {
            return _json({'error': 'epoch_has_posts', 'message': 'somebody holds it'}, 409);
          }
          abandoned.add(epoch);
          claims[id]?.remove(epoch);
          return _json({'abandoned': epoch, 'keyEpoch': rotate(id)});
        }

        final patchMatch = RegExp(r'^/v1/channels/([^/]+)$').firstMatch(path);
        if (patchMatch != null && method == 'PATCH') {
          final id = patchMatch.group(1)!;
          if (body['encryptedMetadata'] != null) {
            if (failMetadataUpdate) {
              return _json({'error': 'unavailable', 'message': 'no'}, 503);
            }
            channels[id]!['encryptedMetadata'] = body['encryptedMetadata'];
            metadataEpochs[id] = (body['metadataKeyEpoch'] as num?)?.toInt() ?? 1;
            metadataWrites[id] = (metadataWrites[id] ?? 0) + 1;
          }
          return _json(channels[id]!);
        }

        final requestMatch =
            RegExp(r'^/v1/channels/([^/]+)/key-requests$').firstMatch(path);
        if (requestMatch != null) {
          if (method == 'POST') return _json({'requested': true});
          return _json({'requests': const []});
        }

        final membersMatch = RegExp(r'^/v1/channels/([^/]+)/members$').firstMatch(path);
        if (membersMatch != null && method == 'GET') {
          final id = membersMatch.group(1)!;
          return _json({
            'members': [
              for (final username in members[id] ?? const <String>{})
                {'id': username, 'username': username, 'role': 'subscriber'},
            ],
            'complete': true,
          });
        }

        final removeMatch =
            RegExp(r'^/v1/channels/([^/]+)/members/([^/]+)$').firstMatch(path);
        if (removeMatch != null && method == 'DELETE') {
          final id = removeMatch.group(1)!;
          members[id]?.remove(removeMatch.group(2));
          // The server's whole part in a rotation: advance the version. The
          // key that replaces it does not exist yet and never exists here.
          return _json({'removed': true, 'keyEpoch': rotate(id)});
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
            final claimed = (body['keyEpoch'] as num?)?.toInt() ?? 1;
            // The rule that makes a removal mean anything, enforced by the
            // server and therefore by this stand-in for it.
            if (claimed < epochOf(id)) {
              return _json(
                {'error': 'stale_key_epoch', 'message': 'the key has rotated'},
                409,
              );
            }
            final post = {
              'id': _nextPostId++,
              'authorUsername': 'author',
              'content': body['content'],
              'pinned': false,
              'keyEpoch': claimed,
              'createdAt': DateTime.utc(2026, 1, 1, 12).toIso8601String(),
            };
            posts[id]!.insert(0, post);
            return _json(
              {'id': post['id'], 'keyEpoch': claimed, 'createdAt': post['createdAt']},
              201,
            );
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

/// A messaging service that records key deliveries instead of encrypting them.
///
/// Everything about sealing a key into a Signal message is covered by the
/// `key delivery` group above, with real crypto. What this stands in for is
/// the fan-out decision on top of it: after a rotation, who is sent the new
/// key — which is not something the ordinary fake server can answer, because
/// it has no sessions and every send simply fails.
class RecordingMessaging extends MessagingService {
  RecordingMessaging({required super.api, required super.crypto});

  final List<({String username, String scopeId, int? epoch, String key})> delivered = [];

  /// Set to fail every delivery, which is what an unreachable member looks
  /// like from here.
  bool failEveryDelivery = false;

  @override
  Future<void> deliverKey({
    required String username,
    required String scope,
    required String scopeId,
    required String base64Key,
    int? keyEpoch,
  }) async {
    if (failEveryDelivery) throw StateError('unreachable');
    delivered.add((username: username, scopeId: scopeId, epoch: keyEpoch, key: base64Key));
  }
}

/// A service whose key deliveries are recorded rather than sent.
Future<(ChannelService, RecordingMessaging)> _recordingServiceOn(
  FakeChannelServer server,
) async {
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final api = PrivioApiClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    client: server.client(),
  );
  api.useToken('token');
  final messaging = RecordingMessaging(api: api, crypto: crypto);
  return (
    ChannelService(api: api, crypto: crypto, messaging: messaging),
    messaging,
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
        throwsA(isA<ChannelKeyPending>()),
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

      final key = (await service.keyFor(channel.id, 1))!;
      final link = ChannelService.linkForChannel(channel.inviteCode!);

      expect(link, 'https://privio.channel/c/${channel.inviteCode}');
      expect(link, isNot(contains('#')));
      expect(link, isNot(contains(base64Url.encode(key))));
      expect(link, isNot(contains(base64Encode(key))));
    });

    test('round-trip through the parser, for a channel and for a group', () {
      final channelLink = ChannelService.linkForChannel('abc123');
      final groupLink = ChannelService.linkForGroup('xyz789');

      expect(channelLink, 'https://privio.channel/c/abc123');
      expect(groupLink, 'https://privio.group/g/xyz789');

      expect(ChannelService.parseInviteLink(channelLink)!.code, 'abc123');
      expect(ChannelService.parseInviteLink(channelLink)!.kind, InviteKind.channel);
      expect(ChannelService.parseInviteLink(groupLink)!.code, 'xyz789');
      expect(ChannelService.parseInviteLink(groupLink)!.kind, InviteKind.group);
    });

    test('the path decides the kind, not the host', () {
      // A link that has been shortened, wrapped or re-hosted still names the
      // same thing, so the parser reads /c/ and /g/ rather than the domain.
      final wrapped = ChannelService.parseInviteLink('https://example.test/g/xyz789')!;
      expect(wrapped.kind, InviteKind.group);
      expect(wrapped.code, 'xyz789');
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
      await joiner.rememberKey(channel.id, 1, (await author.keyFor(channel.id, 1))!);
      final posts = await joiner.posts(channel.id);
      expect(posts.single.opened, isTrue);
      expect(posts.single.body, 'Deploy at 14:00');
    });
  });

  group('rotating the key when somebody goes', () {
    /*
     * The property, stated once so the tests below can be short: a removed
     * member keeps what they had already read and cannot open what is published
     * afterwards. Real AES-GCM throughout — the point is that the old key
     * genuinely does not open the new post, not that a mock said so.
     */

    late FakeChannelServer server;
    late ChannelService admin;
    late ChannelInfo channel;

    setUp(() async {
      server = FakeChannelServer();
      admin = await _serviceOn(server);
      channel = await admin.create(
        visibility: ChannelVisibility.public,
        handle: 'ops',
        title: 'Ops',
      );
      server.members[channel.id] = {'author', 'stays'};
    });

    /// A member who joined before the removal: holds epoch 1 and nothing after.
    Future<ChannelService> memberHoldingEpochOne() async {
      final other = await _serviceOn(server);
      await other.rememberKey(channel.id, 1, (await admin.keyFor(channel.id, 1))!);
      return other;
    }

    test('a removed member cannot open what is published afterwards', () async {
      final removed = await memberHoldingEpochOne();
      await admin.publish(channel.id, 'before the removal');

      server.rotate(channel.id);
      expect(await admin.completeRotation(channel.id), isTrue);
      await admin.publish(channel.id, 'after the removal');

      // They are handed the ciphertext deliberately — the real server would not
      // serve it to them, and the test is about the key, not the access check.
      final feed = await removed.posts(channel.id);
      final before = feed.firstWhere((p) => p.keyEpoch == 1);
      final after = feed.firstWhere((p) => p.keyEpoch == 2);

      expect(before.opened, isTrue, reason: 'what they had already read stays readable');
      expect(before.body, 'before the removal');
      expect(after.opened, isFalse, reason: 'and the future does not');
      expect(after.body, isEmpty);
    });

    test('a remaining member reads both the old posts and the new', () async {
      final stays = await memberHoldingEpochOne();
      await admin.publish(channel.id, 'before');

      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      await admin.publish(channel.id, 'after');

      // The rotation delivers to every remaining member; here that delivery is
      // applied by hand, which is what the message carries.
      await stays.rememberKey(channel.id, 2, (await admin.keyFor(channel.id, 2))!);

      final feed = await stays.posts(channel.id);
      expect(feed.every((p) => p.opened), isTrue);
      expect(feed.map((p) => p.body), containsAll(['before', 'after']));
    });

    test('the members who are left are sent the new key, and the one who went is not',
        () async {
      final (admin, deliveries) = await _recordingServiceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.public,
        handle: 'ops2',
        title: 'Ops',
      );
      server.members[channel.id] = {'author', 'stays', 'goes'};

      // What removal does on the server: the roster loses a member and the
      // channel moves to a version nobody has a key for yet.
      server.members[channel.id]!.remove('goes');
      server.rotate(channel.id);

      expect(await admin.completeRotation(channel.id), isTrue);

      expect(
        deliveries.delivered.map((d) => d.username),
        unorderedEquals(['author', 'stays']),
        reason: 'the remaining members have to receive the key they now need',
      );
      expect(deliveries.delivered.every((d) => d.epoch == 2), isTrue);
      expect(deliveries.delivered.every((d) => d.scopeId == channel.id), isTrue);
      expect(
        deliveries.delivered.map((d) => d.key),
        everyElement(base64Encode((await admin.keyFor(channel.id, 2))!)),
        reason: 'and the key they are sent is the one the channel is on',
      );
    });

    test('a member who could not be reached does not hold up the others', () async {
      final (admin, deliveries) = await _recordingServiceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.public,
        handle: 'ops3',
        title: 'Ops',
      );
      server.members[channel.id] = {'author', 'stays'};
      server.rotate(channel.id);

      deliveries.failEveryDelivery = true;
      // The rotation still completes: the key is the channel's key whether or
      // not the fan-out got through, and whoever missed it asks for it.
      expect(await admin.completeRotation(channel.id), isTrue);
      expect(await admin.keyFor(channel.id, 2), isNotNull);
      expect(deliveries.delivered, isEmpty);

      deliveries.failEveryDelivery = false;
      expect(await admin.distributeKey(channel.id, 2), 2, reason: 'a later pass reaches them');
    });

    test('the new key is a different key, not the old one relabelled', () async {
      final first = (await admin.keyFor(channel.id, 1))!;
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      final second = (await admin.keyFor(channel.id, 2))!;

      expect(second, isNot(equals(first)));
      expect(second, hasLength(32));
    });

    test('an offline device catches up to the version it missed', () async {
      // Away while two people were removed. It comes back holding epoch 1 and
      // has to end up on epoch 3 without anything in between being guessed.
      final away = await memberHoldingEpochOne();
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      await admin.publish(channel.id, 'published while it was away');

      expect(await away.hasCurrentKey(channel.id), isFalse);
      expect((await away.posts(channel.id)).single.opened, isFalse);

      await away.rememberKey(channel.id, 3, (await admin.keyFor(channel.id, 3))!);

      expect(await away.hasCurrentKey(channel.id), isTrue);
      expect((await away.posts(channel.id)).single.body, 'published while it was away');
      expect(
        await away.heldEpochs(channel.id),
        [1, 3],
        reason: 'the gap is real and is not papered over',
      );
    });

    test('losing the race to claim an epoch discards the losing key', () async {
      // Two admins removing two people in the same minute. Both generate a key;
      // only one may be distributed, or half the channel holds each.
      server.rotate(channel.id);
      server.claimAlreadyHeldBy = 'key-id-from-the-other-admin';

      expect(await admin.completeRotation(channel.id), isFalse);
      expect(
        await admin.keyFor(channel.id, 2),
        isNull,
        reason: 'a key that is not the agreed one is worse than no key',
      );
    });

    test('the winner keeps its key and the channel has exactly one', () async {
      server.rotate(channel.id);
      expect(await admin.completeRotation(channel.id), isTrue);
      final mine = await admin.keyFor(channel.id, 2);
      expect(mine, isNotNull);

      // A second attempt must not generate a second key over the first.
      expect(await admin.completeRotation(channel.id), isTrue);
      expect(await admin.keyFor(channel.id, 2), equals(mine));
    });

    test('a replayed key for an epoch already held does not overwrite it', () async {
      // The rollback this closes: an old delivery arriving late, or a replayed
      // one, putting the channel back on a key a removed member holds.
      final original = (await admin.keyFor(channel.id, 1))!;
      final impostor = Uint8List.fromList(List.filled(32, 7));

      await admin.rememberKey(channel.id, 1, impostor);

      expect(await admin.keyFor(channel.id, 1), equals(original));
    });

    test('publishing under a superseded key is refused, then retried correctly', () async {
      // The offline author: composed the post before the removal, sends it
      // after. The old key must not be what seals it.
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);

      final id = await admin.publish(channel.id, 'composed earlier');

      final stored = server.posts[channel.id]!.firstWhere((p) => p['id'] == id);
      expect(stored['keyEpoch'], 2, reason: 'sealed under what is current, not what was in hand');

      final removed = await memberHoldingEpochOne();
      expect((await removed.posts(channel.id)).single.opened, isFalse);
    });

    test('a device with no key for the current epoch will not post at all', () async {
      // No silent fallback: the alternative to failing here is publishing to
      // somebody who was just removed.
      final stays = await memberHoldingEpochOne();
      server.rotate(channel.id);

      await expectLater(
        stays.publish(channel.id, 'should not go out'),
        throwsA(isA<ChannelKeyPending>()),
      );
      expect(server.posts[channel.id], isEmpty);
    });

    test('and says which of the two waits it is', () async {
      final stays = await memberHoldingEpochOne();
      server.rotate(channel.id);

      // Nobody has generated the replacement yet.
      var failure = await stays.publish(channel.id, 'x').then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );
      expect((failure! as ChannelKeyPending).awaitingGeneration, isTrue);
      expect(failure.toString(), contains('after a member left'));

      // Now it exists, and this device is simply waiting for it to arrive.
      await admin.completeRotation(channel.id);
      failure = await stays.publish(channel.id, 'x').then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );
      expect((failure! as ChannelKeyPending).awaitingGeneration, isFalse);
      expect(failure.toString(), contains('reach this device'));
    });

    test('an existing channel migrates without losing anything', () async {
      // A device from before versioning: one key, stored under the old name.
      // Nothing may become unreadable, and the key must land as epoch 1.
      final legacy = await _serviceOn(server);
      final key = (await admin.keyFor(channel.id, 1))!;
      await legacy.writeLegacyKey(channel.id, key);
      await admin.publish(channel.id, 'written before any of this existed');

      final feed = await legacy.posts(channel.id);

      expect(feed.single.opened, isTrue, reason: 'no post becomes unreadable');
      expect(feed.single.body, 'written before any of this existed');
      expect(await legacy.heldEpochs(channel.id), [1]);
    });

    test('leaving a channel forgets every version of its key', () async {
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      expect(await admin.heldEpochs(channel.id), [1, 2]);

      await admin.forgetKey(channel.id);

      expect(await admin.heldEpochs(channel.id), isEmpty);
    });
  });

  group('what a new member is given', () {
    /*
     * The decision this pins down: a rotation is not a claim that past posts
     * become secret. On a private channel it does withhold them from somebody
     * who joins afterwards, which is real. On a public channel it does not,
     * because anyone may join and therefore anyone may hold the keys — saying
     * otherwise would be a guarantee that does not exist.
     */

    Future<({FakeChannelServer server, ChannelService admin, ChannelInfo channel})> setUpChannel(
      ChannelVisibility visibility,
    ) async {
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: visibility,
        handle: visibility == ChannelVisibility.public ? 'ops' : null,
        title: 'Ops',
      );
      server.members[channel.id] = {'author', 'joiner'};
      server.rotate(channel.id);
      await admin.completeRotation(channel.id);
      return (server: server, admin: admin, channel: channel);
    }

    test('a private channel hands over the current version only', () async {
      final env = await setUpChannel(ChannelVisibility.private);

      expect(await env.admin.heldEpochs(env.channel.id), [1, 2],
          reason: 'the sender holds both');
      expect(
        await env.admin.epochsToShareWith(env.channel.id),
        [2],
        reason: 'and passes on only the one that opens what is published now',
      );
    });

    test('a public channel does not pretend its past is secret', () async {
      // The code must not claim a property the design cannot support. A public
      // channel's history is as public as its membership, which is anybody.
      final env = await setUpChannel(ChannelVisibility.public);

      expect(await env.admin.epochsToShareWith(env.channel.id), [1, 2]);
    });

    test('the boundary is the last rotation, not the moment somebody joined', () async {
      // The limit most likely to be misread as something stronger, pinned here
      // so nobody can quietly start claiming it.
      //
      // "New members get the current version only" does not mean "new members
      // get nothing from before they arrived". A key version covers every post
      // sealed under it, so a joiner can read back to the last removal — which
      // may be months of conversation they were never part of.
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};

      // One removal, long ago. Everything since has been under epoch 2.
      server.rotate(channel.id);
      expect(await admin.completeRotation(channel.id), isTrue);
      await admin.publish(channel.id, 'months before the joiner had heard of it');
      await admin.publish(channel.id, 'the day before they joined');

      final joiner = await _serviceOn(server);
      await joiner.rememberKey(channel.id, 2, (await admin.keyFor(channel.id, 2))!);

      final feed = await joiner.posts(channel.id);
      expect(
        feed.every((p) => p.opened),
        isTrue,
        reason: 'both are epoch 2, so both open — this is the documented behaviour',
      );
      expect(
        feed.map((p) => p.body),
        contains('months before the joiner had heard of it'),
      );
      // Getting a join-time boundary would need a per-post ratchet rather than
      // one key per version. See docs/security-model.md; it is not implemented
      // and is not claimed.
    });

    test('rotation changes who is sent the feed, not who may ever read it again', () async {
      // Requirement in one sentence, asserted so it cannot be quietly reversed:
      // a removed person can rejoin a public channel under another account and
      // be a member again. The rotation is not, and is not presented as, a ban.
      final env = await setUpChannel(ChannelVisibility.public);

      env.server.members[env.channel.id]!.add('same_person_new_account');

      final roster = await env.admin.members(env.channel.id);
      expect(
        roster.members.map((m) => m.username),
        contains('same_person_new_account'),
        reason: 'joining again is joining again; the key follows membership',
      );
    });
  });

  group('surviving a crash mid-rotation', () {
    /*
     * Everything here is about the window between reserving a key version on
     * the server and having the key safely on disk. Before this branch the
     * order was claim-then-save, and a device that died in between left the
     * epoch reserved to a key that existed nowhere: a channel nobody could
     * publish to, that nobody could repair, because claiming it again with a
     * different key would split the channel in two.
     */

    late FakeChannelServer server;
    late ChannelService admin;
    late ChannelInfo channel;

    setUp(() async {
      server = FakeChannelServer();
      admin = await _serviceOn(server);
      channel = await admin.create(
        visibility: ChannelVisibility.public,
        handle: 'ops',
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};
      server.rotate(channel.id);
    });

    /// A fresh device on the same storage — what a restart looks like from here.
    Future<ChannelService> restart(ChannelService from) => _restartOn(server, from);

    test('a lost reply is resolved on the next attempt, not re-generated', () async {
      // The server recorded the claim; the answer never came back. The device
      // must not conclude it failed and make a second key.
      server.loseClaimReply = true;
      expect(await admin.completeRotation(channel.id), isFalse);
      expect(await admin.keyFor(channel.id, 2), isNull, reason: 'nothing unconfirmed is promoted');

      server.loseClaimReply = false;
      expect(await admin.completeRotation(channel.id), isTrue);

      expect(await admin.keyFor(channel.id, 2), isNotNull);
      expect(
        server.claims[channel.id]![2],
        isNotNull,
        reason: 'and it is the same reservation, not a second one',
      );
    });

    test('the candidate is on disk before the claim goes out', () async {
      // The ordering the whole thing rests on. If the write happened after the
      // claim, this would be null.
      server.loseClaimReply = true;
      await admin.completeRotation(channel.id);

      final pending = await admin.pendingKeyForTest(channel.id);
      expect(pending, isNotNull);
      expect(pending!.epoch, 2);
      expect(pending.key, hasLength(32));
    });

    test('a restart after a successful claim promotes the same key', () async {
      // Claimed, then killed before the key was stored. The replacement process
      // finds the candidate, asks the server what became of it, and is told it
      // won — so the key it generated before the crash becomes the channel key
      // rather than being lost with the epoch reserved to nothing.
      server.loseClaimReply = true;
      await admin.completeRotation(channel.id);
      final candidate = (await admin.pendingKeyForTest(channel.id))!.key;
      server.loseClaimReply = false;

      final afterCrash = await restart(admin);
      expect(await afterCrash.completeRotation(channel.id), isTrue);

      expect(await afterCrash.keyFor(channel.id, 2), equals(candidate));
      expect(
        await afterCrash.pendingKeyForTest(channel.id),
        isNull,
        reason: 'and the candidate is cleared once it is the real thing',
      );
    });

    test('a restart after losing the race discards the candidate', () async {
      server.loseClaimReply = true;
      await admin.completeRotation(channel.id);
      // While this device was away, another admin claimed the epoch.
      server.claims[channel.id]![2] = 'key-id-from-the-other-admin';
      server.loseClaimReply = false;

      final afterCrash = await restart(admin);
      expect(await afterCrash.completeRotation(channel.id), isFalse);

      expect(await afterCrash.keyFor(channel.id, 2), isNull);
      expect(await afterCrash.pendingKeyForTest(channel.id), isNull);
    });

    test('a candidate for an epoch the channel has left is not resurrected', () async {
      server.loseClaimReply = true;
      await admin.completeRotation(channel.id);
      // Two more people leave while this device is off.
      server.rotate(channel.id);
      server.loseClaimReply = false;

      await admin.completeRotation(channel.id);

      expect(await admin.keyFor(channel.id, 2), isNull, reason: 'epoch 2 is behind us');
      expect(await admin.keyFor(channel.id, 3), isNotNull);
    });

    test('a restart during distribution finishes it without a new key', () async {
      // Distribution is after the promotion and is repeatable on purpose: the
      // key is already the channel key, so a second pass sends it again rather
      // than making another one.
      expect(await admin.completeRotation(channel.id), isTrue);
      final key = await admin.keyFor(channel.id, 2);

      final afterCrash = await restart(admin);
      expect(await afterCrash.completeRotation(channel.id), isTrue);

      expect(await afterCrash.keyFor(channel.id, 2), equals(key));
      expect(server.claims[channel.id]![2], isNotNull);
    });

    test('an orphaned version is stepped over, never reused or rolled back', () async {
      // The device that generated epoch 2 is gone and took the key with it.
      server.claims[channel.id]![2] = 'key-id-from-a-device-that-is-gone';

      final rescuer = await _serviceOn(server);
      await rescuer.rememberKey(channel.id, 1, (await admin.keyFor(channel.id, 1))!);

      expect(await rescuer.abandonOrphanedEpoch(channel.id), isTrue);

      expect(server.abandoned, [2], reason: 'the dead version is left behind');
      expect(server.epochOf(channel.id), 3, reason: 'and the channel moves forward');
      expect(await rescuer.keyFor(channel.id, 3), isNotNull);
      expect(
        await rescuer.keyFor(channel.id, 2),
        isNull,
        reason: 'the orphaned version is never given a second key',
      );
    });

    test('a version with posts under it is not treated as an orphan', () async {
      // Somebody does hold that key and has been using it. Abandoning it would
      // strand posts people can read.
      expect(await admin.completeRotation(channel.id), isTrue);
      await admin.publish(channel.id, 'published under epoch 2');

      final other = await _serviceOn(server);
      await other.rememberKey(channel.id, 1, (await admin.keyFor(channel.id, 1))!);

      expect(await other.abandonOrphanedEpoch(channel.id), isFalse);
      expect(server.abandoned, isEmpty);
      expect(server.epochOf(channel.id), 2, reason: 'and nothing moved');
    });

    test('a device that already holds the key does not abandon anything', () async {
      expect(await admin.completeRotation(channel.id), isTrue);
      expect(await admin.abandonOrphanedEpoch(channel.id), isFalse);
      expect(server.abandoned, isEmpty);
    });
  });

  group('a private channel keeps its name across rotations', () {
    test('a member who joins after two rotations reads the name, not the past', () async {
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Sicherheitsteam',
      );
      server.members[channel.id] = {'author'};

      await admin.publish(channel.id, 'from before anybody joined');

      // Two removals, two rotations, two re-seals of the name.
      for (var i = 0; i < 2; i++) {
        server.rotate(channel.id);
        expect(await admin.completeRotation(channel.id), isTrue);
      }
      final current = server.epochOf(channel.id);
      expect(current, 3);
      await admin.publish(channel.id, 'after both rotations');

      // The joiner is given exactly what the rules say: the current key, and
      // nothing older.
      final joiner = await _serviceOn(server);
      await joiner.rememberKey(channel.id, current, (await admin.keyFor(channel.id, current))!);

      final seen = await joiner.byId(channel.id);
      expect(seen.title, 'Sicherheitsteam', reason: 'the name opens with the key they were given');

      final feed = await joiner.posts(channel.id);
      final old = feed.firstWhere((p) => p.keyEpoch == 1);
      final fresh = feed.firstWhere((p) => p.keyEpoch == current);
      expect(old.opened, isFalse, reason: 'and the posts from before they arrived do not');
      expect(fresh.opened, isTrue);
      expect(fresh.body, 'after both rotations');
    });

    test('the name is re-sealed under the new key, not left under the first', () async {
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};
      expect(server.metadataEpochs[channel.id], 1);

      server.rotate(channel.id);
      await admin.completeRotation(channel.id);

      expect(server.metadataEpochs[channel.id], 2);
    });

    test('an interrupted re-seal is finished on the next pass, not abandoned', () async {
      // The rotation itself is repeatable and survives a crash. The name was
      // not: the key was promoted, the re-seal failed, and every later pass
      // took the "already holding the current key" shortcut and returned
      // without ever trying again. The channel then kept a name sealed under a
      // key that new members are deliberately never given — permanently.
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};
      server.rotate(channel.id);

      server.failMetadataUpdate = true;
      expect(await admin.completeRotation(channel.id), isTrue);
      expect(await admin.keyFor(channel.id, 2), isNotNull, reason: 'the key is the channel key');
      expect(server.metadataEpochs[channel.id], 1, reason: 'the name did not follow it');

      server.failMetadataUpdate = false;
      expect(await admin.completeRotation(channel.id), isTrue);

      expect(server.metadataEpochs[channel.id], 2, reason: 'the next pass has to finish it');
    });

    test('and is finished after a restart, by the device that comes back', () async {
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};
      server.rotate(channel.id);

      server.failMetadataUpdate = true;
      await admin.completeRotation(channel.id);
      server.failMetadataUpdate = false;

      final afterCrash = await _restartOn(server, admin);
      expect(await afterCrash.completeRotation(channel.id), isTrue);

      expect(server.metadataEpochs[channel.id], 2);
    });

    test('and is not re-written once it is already current', () async {
      // The repair has to be cheap enough to run on every pass: a device that
      // opens the app should not re-seal a name that is already under the
      // current key, nor send that write on every poll.
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.private,
        title: 'Ops',
      );
      server.members[channel.id] = {'author'};
      server.rotate(channel.id);

      await admin.completeRotation(channel.id);
      expect(server.metadataWrites[channel.id], 1);

      await admin.completeRotation(channel.id);
      await admin.completeRotation(channel.id);
      expect(server.metadataWrites[channel.id], 1, reason: 'nothing left to repair');
    });

    test('a public channel is not re-sealed, because its title is not sealed', () async {
      final server = FakeChannelServer();
      final admin = await _serviceOn(server);
      final channel = await admin.create(
        visibility: ChannelVisibility.public,
        handle: 'open',
        title: 'Open',
      );
      server.members[channel.id] = {'author'};

      server.rotate(channel.id);
      await admin.completeRotation(channel.id);

      expect(server.metadataEpochs[channel.id], 1, reason: 'nothing to re-seal');
    });
  });
}

/// A second service over the same storage: what a restart looks like from here.
Future<ChannelService> _restartOn(FakeChannelServer server, ChannelService from) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    client: server.client(),
  );
  api.useToken('token');
  return ChannelService(
    api: api,
    crypto: from.cryptoForTest,
    messaging: MessagingService(api: api, crypto: from.cryptoForTest),
  );
}
