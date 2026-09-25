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
import 'package:privio/models/group_bot.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

/// Bots in a group, from the device's side.
///
/// The filter is the feature, and it runs **here** rather than on the server —
/// a group message is ciphertext the server cannot open, so the only party
/// that can hand one to a bot is the device that wrote it. These tests are
/// about what that device hands over, and above all about what it does not.

const bot = GroupBot(botId: 'bot-1', username: 'helper', displayName: 'Helper');

void main() {
  group('what addresses a bot', () {
    test('a command does', () {
      expect(addressesBot(bot, '/help'), isTrue);
      expect(addressesBot(bot, '  /start now'), isTrue);
    });

    test('a command aimed at another bot does not', () {
      // `/help@other` in a group with several bots is for one of them.
      expect(addressesBot(bot, '/help@helper'), isTrue);
      expect(addressesBot(bot, '/help@other'), isFalse);
    });

    test('a mention of it does', () {
      expect(addressesBot(bot, 'frag mal @helper'), isTrue);
    });

    test('a mention of somebody else does not', () {
      expect(addressesBot(bot, 'frag mal @max'), isFalse);
    });

    test('a name inside a URL or a code span does not', () {
      // The same tokenizer the chat draws mentions with, so the rules match
      // what the reader sees.
      expect(addressesBot(bot, 'https://example.com/@helper'), isFalse);
      expect(addressesBot(bot, 'nimm `@helper` wörtlich'), isFalse);
    });

    test('an ordinary sentence does not', () {
      expect(addressesBot(bot, 'Wann treffen wir uns?'), isFalse);
      expect(addressesBot(bot, 'helper kommt auch mit'), isFalse);
    });

    test('a reply to the bot does', () {
      expect(addressesBot(bot, 'danke', repliesToBot: true), isTrue);
    });

    test('and with the explicit setting, everything does', () {
      const reads = GroupBot(
        botId: 'bot-1',
        username: 'helper',
        displayName: 'Helper',
        readsAllMessages: true,
      );
      expect(addressesBot(reads, 'Wann treffen wir uns?'), isTrue);
    });
  });

  group('what the device actually hands over', () {
    late List<Map<String, dynamic>> handed;

    Future<(PrivioServices, InMemoryMessageStore)> build({
      bool readsAll = false,
    }) async {
      handed = [];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' && path.startsWith('/v1/bots/')) {
          handed.add({
            'botId': path.split('/')[3],
            ...jsonDecode(request.body) as Map<String, dynamic>,
          });
          return http.Response(
            jsonEncode({'messageId': 1}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && path.endsWith('/bots')) {
          return http.Response(
            jsonEncode({
              'bots': [
                {
                  'botId': 'bot-1',
                  'username': 'helper',
                  'displayName': 'Helper',
                  'maySend': true,
                  'readsAllMessages': readsAll,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(const {'envelopes': [], 'more': false, 'devices': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: client)
        ..useToken('token');
      final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
      final messaging = MessagingService(api: api, crypto: crypto);
      final store = InMemoryMessageStore();
      final secureStore = InMemorySecureStore();

      store.upsertGroup(
        const GroupInfo(
          groupId: 'g1',
          role: 'admin',
          name: 'Wanderung',
          groupKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          memberIds: ['me', 'them'],
        ),
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
        store
      );
    }

    /// Handing a message over is deliberately not awaited by `send`: a slow or
    /// unreachable bot must not hold up the sender's own screen. So a test has
    /// to let those futures run before it looks.
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('nothing at all, before the bot list has been read', () async {
      // The safe direction: a device that does not know which bots are present
      // hands nothing over. A bot receives less, never more.
      final (services, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';

      await controller.send('g1', '/help');
      await settle();
      expect(handed, isEmpty);
    });

    test('a command, once it has', () async {
      final (services, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.refreshGroupBots('g1');

      await controller.send('g1', '/help');
      await settle();

      expect(handed, hasLength(1));
      expect(handed.single['botId'], 'bot-1');
      expect(handed.single['text'], '/help');
      expect(handed.single['groupId'], 'g1');
      expect(handed.single['clientId'], isNotNull, reason: 'a retry must not be a second message');
    });

    test('and not an ordinary message', () async {
      final (services, _) = await build();
      final controller = ConversationController(services)..accountId = 'me';
      await controller.refreshGroupBots('g1');

      await controller.send('g1', 'Wann treffen wir uns?');
      await settle();

      expect(
        handed,
        isEmpty,
        reason: 'the bot must not receive what nobody addressed to it',
      );
    });

    test('everything, once an admin has said so', () async {
      final (services, _) = await build(readsAll: true);
      final controller = ConversationController(services)..accountId = 'me';
      await controller.refreshGroupBots('g1');

      await controller.send('g1', 'Wann treffen wir uns?');
      await settle();

      expect(handed, hasLength(1));
    });

    test('nothing from a one-to-one chat, whatever is typed', () async {
      // A bot in a group is in that group. A command typed in a private chat
      // with somebody else is not the bot's business.
      final (services, store) = await build();
      store.upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
      final controller = ConversationController(services)..accountId = 'me';
      await controller.refreshGroupBots('g1');

      await controller.send('acc-bob', '/help');
      await settle();

      expect(handed, isEmpty);
    });

    test('and nothing that was written before the bot was there', () async {
      // Forwarding happens at send time, so a message already in the history
      // is never offered — no setting reaches it.
      final (services, store) = await build(readsAll: true);
      store.append(
        'g1',
        Message(
          id: 'old',
          clientId: 'old',
          body: 'von vorher',
          sentAt: DateTime(2026),
          isMine: false,
        ),
      );
      final controller = ConversationController(services)..accountId = 'me';
      await controller.refreshGroupBots('g1');

      expect(handed, isEmpty);
    });
  });
}
