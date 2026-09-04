import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
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

/// Answers the delete route the way the server does: only with the password.
class FakeAccountServer {
  static const password = 'correct-horse-battery';
  final List<String> calls = [];
  bool reachable = true;

  http.Client client() => MockClient((request) async {
        if (!reachable) throw http.ClientException('offline', request.url);
        final path = request.url.path;
        calls.add('${request.method} $path');
        if (request.method == 'DELETE' && path == '/v1/accounts/me') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['currentPassword'] != password) {
            return _json(
              {'error': 'invalid_credentials', 'message': 'Current password is incorrect'},
              401,
            );
          }
          return _json({'deleted': true});
        }
        return _json({'contacts': [], 'envelopes': [], 'more': false});
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Future<(AppState, FakeAccountServer, PrivioServices, InMemoryArchiveStorage)> build() async {
  final server = FakeAccountServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final cryptoStorage = InMemoryCryptoStorage();
  final crypto = await PrivioCrypto.open(cryptoStorage);
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secureStore = InMemorySecureStore();
  final archiveStorage = InMemoryArchiveStorage();

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
    archive: EncryptedMessageArchive(
      storage: archiveStorage,
      keyStore: InMemorySecureStore(),
    ),
  );

  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  store.upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
  store.append(
    'acc-bob',
    Message(id: 'm1', body: 'hallo', sentAt: DateTime(2026), isMine: false),
  );
  await services.archive.save(store.conversations());
  return (state, server, services, archiveStorage);
}

void main() {
  // AppState.initialise asks the launcher what it can do, over a method
  // channel, so the binding has to exist even without a widget in sight.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the wrong password deletes nothing, here or there', () async {
    final (state, server, services, archive) = await build();

    final failure = await state.deleteAccount('not-the-password');
    expect(failure, contains('password'));
    expect(server.calls, contains('DELETE /v1/accounts/me'));
    expect(
      services.store.conversationWith('acc-bob'),
      isNotNull,
      reason: 'a refused delete that had already wiped the phone is the worst of both',
    );
    expect(await archive.sizeInBytes(), greaterThan(0));
  });

  test('an unreachable server deletes nothing either', () async {
    final (state, server, services, _) = await build();
    server.reachable = false;

    expect(await state.deleteAccount(FakeAccountServer.password), isNotNull);
    expect(services.store.conversationWith('acc-bob'), isNotNull);
  });

  test('the right password takes the account and the device with it', () async {
    final (state, server, services, archive) = await build();
    final identityBefore = await services.crypto.identityFingerprint();

    expect(await state.deleteAccount(FakeAccountServer.password), isNull);
    expect(server.calls, contains('DELETE /v1/accounts/me'));

    expect(services.store.conversations(), isEmpty);
    expect(await archive.sizeInBytes(), 0);
    expect(state.stage, AppStage.welcome);
    expect(state.username, isNull);
    expect(state.accountId, isNull);

    // Unlike signing out, the identity goes too: there is no account left for
    // these keys to belong to.
    final identityAfter = await services.crypto.identityFingerprint();
    expect(identityAfter, isNot(identityBefore));
  });
}
