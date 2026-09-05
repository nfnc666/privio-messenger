import 'dart:convert';
import 'dart:typed_data';

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
import 'package:privio/media/voice.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

/// A server that can be taken away and given back, which is the whole point of
/// an outbox.
class FlakyServer {
  bool online = true;

  /// Media ids handed out, in order.
  final List<String> uploads = [];

  /// Idempotency keys seen on sends.
  final List<String> sendKeys = [];

  int _nextMedia = 1;

  http.Client client() => MockClient((request) async {
        if (!online) {
          throw http.ClientException('offline', request.url);
        }
        final path = request.url.path;

        if (request.method == 'POST' && path == '/v1/media') {
          final n = _nextMedia++;
          uploads.add('media-$n');
          // Minted once and never stored: the real server hands the token back
          // here and keeps only its hash.
          return _json({'id': 'media-$n', 'token': 'token-$n'}, 201);
        }
        if (request.method == 'GET' && path == '/v1/keys/bob') {
          return _json({'accountId': 'account-bob', 'devices': const []});
        }
        if (request.method == 'POST' && path == '/v1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sendKeys.add(body['idempotencyKey'] as String? ?? '');
          return _json({'accepted': true, 'deliveredTo': 1}, 202);
        }
        return _json({'error': 'not_found', 'message': path}, 404);
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// Sends nothing, but remembers what it was asked to send — enough to drive the
/// queue without a second device on the other end.
class RecordingMessagingService extends MessagingService {
  RecordingMessagingService({required super.api, required super.crypto});

  final List<String> sentClientIds = [];

  /// What each send carried, so a test can check the capability went with it.
  final List<MessagePayload> sent = [];
  bool failSends = false;

  @override
  Future<int> sendPayload(String username, payload) async {
    if (failSends) throw ApiException(503, 'unavailable', 'no route to host');
    sentClientIds.add(payload.clientId as String);
    sent.add(payload);
    return 1;
  }
}

Future<(PrivioServices, RecordingMessagingService, FlakyServer, InMemoryArchiveStorage)>
    buildServices() async {
  final server = FlakyServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = RecordingMessagingService(api: api, crypto: crypto);
  final storage = InMemoryArchiveStorage();
  final store = InMemoryMessageStore();
  final secureStore = InMemorySecureStore();

  final services = PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    store: store,
    secureStore: secureStore,
    backup: BackupService(api: api, store: secureStore, messages: store),
    archive: EncryptedMessageArchive(storage: storage, keyStore: InMemorySecureStore()),
  );
  services.store.upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));
  return (services, messaging, server, storage);
}

Future<VoiceRecording> record({Duration duration = const Duration(seconds: 5)}) async {
  final recorder = FakeVoiceRecorder(duration: duration);
  await recorder.start();
  return recorder.stop();
}

void main() {
  test('a voice message sent with a network goes out and is marked sent', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services);

    await controller.sendVoice('account-bob', await record());

    final message = services.store.conversationWith('account-bob')!.messages.single;
    expect(message.kind, MessageKind.voice);
    expect(message.state, DeliveryState.sent);
    expect(message.voiceDuration, const Duration(seconds: 5));
    expect(message.waveform, hasLength(VoiceLimits.waveformBars));
    expect(message.attachment!.mediaId, server.uploads.single);
    expect(messaging.sentClientIds, hasLength(1));
    expect(controller.queuedCount, 0);
  });

  test('with no network it is queued, not lost', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services);
    server.online = false;

    await controller.sendVoice('account-bob', await record());

    expect(controller.queuedCount, 1);
    final message = services.store.conversationWith('account-bob')!.messages.single;
    expect(message.state, DeliveryState.queued);
    expect(message.waveform, isNotNull, reason: 'the bubble is complete while it waits');
    expect(messaging.sentClientIds, isEmpty);
  });

  test('the queue drains when the network comes back', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services);
    server.online = false;
    await controller.sendVoice('account-bob', await record());
    expect(controller.queuedCount, 1);

    server.online = true;
    await controller.flushOutbox();

    expect(controller.queuedCount, 0);
    expect(messaging.sentClientIds, hasLength(1));
    expect(
      services.store.conversationWith('account-bob')!.messages.single.state,
      DeliveryState.sent,
    );
  });

  test('a retry does not upload the recording a second time', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services);

    // The upload gets through; the send does not.
    messaging.failSends = true;
    await controller.sendVoice('account-bob', await record());
    expect(server.uploads, hasLength(1));
    expect(controller.queuedCount, 1);

    messaging.failSends = false;
    await controller.flushOutbox();

    expect(server.uploads, hasLength(1), reason: 'the queue remembered its upload');
    expect(messaging.sentClientIds, hasLength(1));
    expect(controller.queuedCount, 0);

    // And it remembered the token with it. The server issues that once and
    // keeps only its hash, so a retry that kept the id and dropped the token
    // would send a message pointing at bytes nobody could ever fetch.
    expect(messaging.sent.single.mediaId, 'media-1');
    expect(messaging.sent.single.mediaToken, 'token-1');
  });

  test('the same message is never sent twice, however often the queue runs', () async {
    final (services, messaging, _, _) = await buildServices();
    final controller = ConversationController(services);

    await controller.sendVoice('account-bob', await record());
    await controller.flushOutbox();
    await controller.flushOutbox();

    expect(messaging.sentClientIds.toSet(), hasLength(1));
    expect(messaging.sentClientIds, hasLength(1));
  });

  test('a queued recording survives a restart, still as ciphertext', () async {
    final (services, messaging, server, storage) = await buildServices();
    final controller = ConversationController(services);
    server.online = false;

    final recording = await record();
    await controller.sendVoice('account-bob', recording);
    await controller.flush();

    // Nothing recognisable of the recording is in what was written.
    final atRest = storage.bytes!;
    expect(_contains(atRest, recording.bytes.sublist(0, 32)), isFalse);

    // A new controller over the same archive picks the queue back up.
    final reopened = ConversationController(services);
    await reopened.restore();
    expect(reopened.queuedCount, 1);

    server.online = true;
    await reopened.flushOutbox();
    expect(messaging.sentClientIds, hasLength(1));
  });

  test('a user who gives up on a queued message loses the bubble too', () async {
    final (services, _, server, _) = await buildServices();
    final controller = ConversationController(services);
    server.online = false;
    await controller.sendVoice('account-bob', await record());

    final clientId =
        services.store.conversationWith('account-bob')!.messages.single.clientId!;
    controller.discard(clientId);

    expect(controller.queuedCount, 0);
    expect(services.store.conversationWith('account-bob')!.messages, isEmpty);
  });

  test('the chat timer is applied to a voice message as it is sent', () async {
    final (services, _, _, _) = await buildServices();
    final controller = ConversationController(services);
    controller.setDisappearAfter('account-bob', const Duration(seconds: 30));

    await controller.sendVoice('account-bob', await record());

    // Setting the timer writes its own line into the chat, so the voice message
    // is the last thing here rather than the only thing.
    final message = services.store.conversationWith('account-bob')!.messages.last;
    expect(message.isVoice, isTrue);
    expect(message.expiresAt, isNotNull);
    expect(
      message.expiresAt!.difference(DateTime.now()).inSeconds,
      closeTo(30, 2),
    );

    // And it goes when its time is up.
    expect(
      services.store.pruneExpired(DateTime.now().add(const Duration(minutes: 1))),
      hasLength(1),
    );
    // The notice stays: it is the record that the rule changed, and a record
    // that deletes itself under the rule it describes explains nothing.
    final left = services.store.conversationWith('account-bob')!.messages;
    expect(left.single.isNotice, isTrue);
  });
}

bool _contains(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
