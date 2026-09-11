import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/channel_controller.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

/// Unread counts, and a channel that is not empty when the network is.
///
/// The point of the cache is the case where nothing can be fetched at all: a
/// channel opened on a train should show what was in it, not a blank screen
/// that is indistinguishable from a channel nobody has posted to.

/// A server that answers posts until it is switched off.
class FlakyServer {
  FlakyServer({this.posts = const []});

  List<Map<String, dynamic>> posts;

  /// Everything fails from here on — a tunnel, a dead server, aeroplane mode.
  bool offline = false;

  final List<String> reads = [];

  http.Client client() => MockClient((request) async {
        if (offline) throw const SocketishFailure();
        final path = request.url.path;
        if (path.endsWith('/read')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          reads.add('${body['postId']}');
          return _json({'lastReadPostId': body['postId']});
        }
        if (path.endsWith('/posts')) return _json({'posts': posts});
        if (path == '/v1/channels') return _json({'channels': const []});
        return _json(const {});
      });

  http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}

/// Stands in for a network that is simply not there.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => 'no route to host';
}

Map<String, dynamic> postJson(int id, String body) => {
      'id': id,
      'content': base64Encode(utf8.encode(body)),
      'createdAt': DateTime.utc(2026, 9, 11, 12).toIso8601String(),
      'keyEpoch': 1,
    };

Future<
    ({
      ChannelController channels,
      ConversationController chats,
      InMemoryArchiveStorage disk,
      InMemorySecureStore keys,
    })> build(
  FlakyServer server, {
  InMemoryArchiveStorage? disk,
  InMemorySecureStore? keys,
}) async {
  final storage = disk ?? InMemoryArchiveStorage();
  // The archive's own key has to survive a "restart" as well as the blob does.
  // A fresh key store means a fresh key, and a fresh key cannot open what the
  // last run sealed — which looks exactly like an empty cache.
  final archiveKeys = keys ?? InMemorySecureStore();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secure = InMemorySecureStore();
  final services = PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    store: store,
    secureStore: secure,
    backup: BackupService(api: api, store: secure, messages: store),
    // The same archive across a "restart", which is what makes this a test of
    // persistence rather than of a map.
    archive: EncryptedMessageArchive(storage: storage, keyStore: archiveKeys),
  );
  final chats = ConversationController(services)..accountId = 'account-me';
  final channels = ChannelController(services);
  // Wired as `AppState` wires them.
  channels.onPostsChanged = chats.cacheChannelPosts;
  chats.onChannelPostsRestored = channels.restorePosts;
  addTearDown(() {
    channels.dispose();
    chats.dispose();
  });
  return (channels: channels, chats: chats, disk: storage, keys: archiveKeys);
}

ChannelInfo channel({int unread = 0, int lastRead = 0}) => ChannelInfo(
      id: 'channel-1',
      visibility: ChannelVisibility.public,
      title: 'HouseOfTrading',
      role: 'subscriber',
      hasKey: true,
      unreadCount: unread,
      lastReadPostId: lastRead,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the unread count', () {
    test('reads as a badge, capped where the number stops meaning anything', () {
      expect(channel().hasUnread, isFalse);
      expect(channel(unread: 3).unreadLabel, '3');
      expect(channel(unread: 99).unreadLabel, '99');
      expect(channel(unread: 100).unreadLabel, '99+');
      expect(channel(unread: 4821).unreadLabel, '99+');
    });

    test('clears before the round trip, because reading is immediate', () async {
      final server = FlakyServer(posts: [postJson(7, 'hallo')]);
      final app = await build(server);
      app.channels.adopt(channel(unread: 5));
      await app.channels.loadPosts('channel-1');

      await app.channels.markRead('channel-1');

      expect(app.channels.channelById('channel-1')!.unreadCount, 0);
      expect(app.channels.channelById('channel-1')!.lastReadPostId, 7);
      expect(server.reads, ['7'],
          reason: 'and the server is told, so other devices agree');
    });

    test('says nothing when the server is already at or past the newest', () async {
      final server = FlakyServer(posts: [postJson(7, 'hallo')]);
      final app = await build(server);
      app.channels.adopt(channel(lastRead: 7));
      await app.channels.loadPosts('channel-1');

      await app.channels.markRead('channel-1');

      expect(server.reads, isEmpty,
          reason: 'a request that changes nothing is not sent');
    });

    test('says nothing about a channel with no posts', () async {
      final server = FlakyServer();
      final app = await build(server);
      app.channels.adopt(channel());
      await app.channels.loadPosts('channel-1');

      await app.channels.markRead('channel-1');

      expect(server.reads, isEmpty);
    });
  });

  group('the offline cache', () {
    test('a channel opened with no network shows what was in it', () async {
      final server = FlakyServer(posts: [postJson(1, 'erster'), postJson(2, 'zweiter')]);
      final online = await build(server);
      online.channels.adopt(channel());
      await online.channels.loadPosts('channel-1');
      expect(online.channels.postsIn('channel-1'), hasLength(2));
      // The debounced write, flushed the way backgrounding flushes it.
      await online.chats.flush();

      // A new run over the same disk, and nothing answers.
      final offlineServer = FlakyServer()..offline = true;
      final after = await build(offlineServer, disk: online.disk, keys: online.keys);
      after.channels.adopt(channel());
      await after.chats.restore();

      expect(
        after.channels.postsIn('channel-1').map((p) => p.id).toList(),
        [1, 2],
        reason: 'an empty screen is indistinguishable from a channel nobody posts to',
      );
    });

    test('and a failed fetch does not wipe what is held', () async {
      final server = FlakyServer(posts: [postJson(1, 'erster')]);
      final app = await build(server);
      app.channels.adopt(channel());
      await app.channels.loadPosts('channel-1');
      expect(app.channels.postsIn('channel-1'), hasLength(1));

      server.offline = true;
      await app.channels.loadPosts('channel-1');

      expect(
        app.channels.postsIn('channel-1'),
        hasLength(1),
        reason: 'the cache standing is the whole point of having one',
      );
    });

    test('what the server says wins over what was cached', () async {
      final server = FlakyServer(posts: [postJson(1, 'alt')]);
      final online = await build(server);
      online.channels.adopt(channel());
      await online.channels.loadPosts('channel-1');
      await online.chats.flush();

      final fresh = FlakyServer(posts: [postJson(1, 'alt'), postJson(2, 'neu')]);
      final after = await build(fresh, disk: online.disk, keys: online.keys);
      after.channels.adopt(channel());
      await after.channels.loadPosts('channel-1');
      await after.chats.restore();

      expect(
        after.channels.postsIn('channel-1').map((p) => p.id).toList(),
        [1, 2],
        reason: 'a restore must never overwrite what has just been fetched',
      );
    });

    test('holds no decrypted file bytes, only the pointer to them', () async {
      // The rule everywhere else in this app: a decrypted photo does not reach
      // disk. The archive is sealed, but that is not a reason to put plaintext
      // in it.
      final post = ChannelPost(
        id: 1,
        body: 'mit Bild',
        createdAt: DateTime.utc(2026, 9, 11),
        attachment: const ChannelAttachment(
          mediaId: 'media-1',
          token: 'token-1',
          mimeType: 'image/jpeg',
          bytes: 4096,
          name: 'foto.jpg',
        ),
      );

      final cached = post.toCacheJson();
      final attachment = cached['attachment']! as Map<String, dynamic>;
      expect(attachment['id'], 'media-1');
      expect(attachment['bytes'], 4096, reason: 'the size, not the file');
      expect(attachment.containsKey('data'), isFalse);
      expect(attachment.containsKey('content'), isFalse);

      final back = ChannelPost.fromCacheJson(cached)!;
      expect(back.body, 'mit Bild');
      expect(back.attachment!.mediaId, 'media-1');
    });

    test('a padlock stays a padlock across a restart', () async {
      final post = ChannelPost(
        id: 1,
        body: '',
        createdAt: DateTime.utc(2026, 9, 11),
        opened: false,
      );
      expect(ChannelPost.fromCacheJson(post.toCacheJson())!.opened, isFalse);
    });

    test('one malformed row does not cost the whole history', () {
      expect(ChannelPost.fromCacheJson('not a post'), isNull);
      expect(ChannelPost.fromCacheJson(const {'body': 'no id'}), isNull);
    });
  });
}
