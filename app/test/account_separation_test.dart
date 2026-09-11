import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
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

/// Two accounts on one device.
///
/// The scenario is the one that was reported: somebody signs out and creates a
/// second account on the same phone, and the second account opens onto the
/// first one's profile. Everything here is about what survives that boundary
/// when it should not.
class FakeAuthServer {
  /// What `GET /v1/contacts` answers for each token, so a test can tell whose
  /// data reached the screen rather than only that some data did.
  final Map<String, List<Map<String, dynamic>>> contactsByToken = {};

  /// Requests the server saw, as `METHOD /path token`. The token is recorded
  /// because the question is *which account* a late reply belongs to.
  final List<String> calls = [];

  /// Held replies, so a test can make account A's request land after account B
  /// has signed in. Completed by hand.
  final List<void Function()> pending = [];
  bool holdContacts = false;

  int _accounts = 0;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        final token = request.headers['authorization']?.replaceFirst('Bearer ', '') ?? '';
        calls.add('${request.method} $path $token');

        if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final username = body['username'] as String;
          _accounts += 1;
          return _json({
            'token': 'token-$username',
            'accountId': 'acc-$username',
            'username': username,
            'deviceId': 'device-$_accounts',
          }, path == '/v1/accounts' ? 201 : 200);
        }

        if (path == '/v1/contacts' && request.method == 'GET') {
          final answer = _json({'contacts': contactsByToken[token] ?? const []});
          if (!holdContacts) return answer;
          // Held: the reply is handed back only when the test releases it.
          final completer = _Gate<http.Response>();
          pending.add(() => completer.open(answer));
          return completer.wait;
        }

        if (path == '/v1/keys/count' && request.method == 'GET') {
          return _json({'remaining': 50});
        }

        if (path == '/v1/accounts/me' && request.method == 'GET') {
          return _json({'accountId': 'acc', 'username': 'x', 'avatarMediaId': null});
        }

        return _json({'envelopes': [], 'more': false, 'channels': []});
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// A reply the test opens by hand, so "slow network" is a thing that happens
/// rather than a duration somebody hopes is long enough.
class _Gate<T> {
  final _completer = Completer<T>();
  Future<T> get wait => _completer.future;
  void open(T value) => _completer.complete(value);
}

class Harness {
  Harness({
    required this.state,
    required this.server,
    required this.services,
    required this.archive,
    required this.cryptoStorage,
  });

  final AppState state;
  final FakeAuthServer server;
  final PrivioServices services;
  final InMemoryArchiveStorage archive;
  final InMemoryCryptoStorage cryptoStorage;
}

Future<Harness> build() async {
  final server = FakeAuthServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  );
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
  return Harness(
    state: state,
    server: server,
    services: services,
    archive: archiveStorage,
    cryptoStorage: cryptoStorage,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a second account does not open onto the first one\'s profile', () async {
    final h = await build();
    h.server.contactsByToken['token-anna'] = [
      {'id': 'acc-carl', 'username': 'carl'},
    ];

    // --- Account A signs up and puts something in front of itself ----------
    expect(await h.state.register(username: 'anna', password: 'pw'), isTrue);
    final a = h.state.conversations;
    await a.refreshContacts();
    // Set after the refresh: `refreshContacts` also reloads the own picture
    // from the server, which would otherwise overwrite what this line puts
    // there and leave the test proving nothing.
    a.ownAvatar = Uint8List.fromList([1, 2, 3, 4]);
    h.services.store.upsertUser(const KnownUser(accountId: 'acc-carl', username: 'carl'));
    h.services.store.append(
      'acc-carl',
      Message(id: 'm1', body: 'private to anna', sentAt: DateTime(2026), isMine: false),
    );

    expect(a.ownAvatar, isNotNull);
    expect(a.contacts, isNotEmpty);

    // --- A signs out, B signs up on the same device ------------------------
    await h.state.signOut();
    expect(await h.state.register(username: 'bodo', password: 'pw'), isTrue);

    final b = h.state.conversations;
    expect(h.state.accountId, 'acc-bodo');

    // This is the bug as reported: the new account opened onto the old one's
    // profile picture. The controller was never replaced, only told to stop
    // its timers, so every cache it held came straight through.
    expect(b.ownAvatar, isNull, reason: "B must not be wearing A's picture");
    expect(b.contacts, isEmpty, reason: "B must not see A's contacts");
    expect(
      h.services.store.conversationWith('acc-carl'),
      isNull,
      reason: "B must not see A's conversations",
    );
  });

  test('and the device does not keep signing as the account that left', () async {
    final h = await build();
    expect(await h.state.register(username: 'anna', password: 'pw'), isTrue);
    final anna = await h.services.crypto.identityFingerprint();

    await h.state.signOut();
    expect(await h.state.register(username: 'bodo', password: 'pw'), isTrue);
    final bodo = await h.services.crypto.identityFingerprint();

    // The identity key is what a safety number is computed from and what every
    // session is pinned to. Carrying A's into B means B's device signs as A,
    // shows A's safety number to anyone who checks, and still holds the keys to
    // A's private channels and groups.
    expect(bodo, isNot(anna), reason: 'a new account is a new identity');
  });

  test('a late reply for the account that left is not written into the new one',
      () async {
    final h = await build();
    h.server.contactsByToken['token-anna'] = [
      {'id': 'acc-carl', 'username': 'carl'},
    ];

    expect(await h.state.register(username: 'anna', password: 'pw'), isTrue);

    // A's contacts request goes out and does not come back yet.
    h.server.holdContacts = true;
    final slow = h.state.conversations.refreshContacts();

    // Meanwhile the user signs out and B signs up.
    await h.state.signOut();
    expect(await h.state.register(username: 'bodo', password: 'pw'), isTrue);

    // Now A's reply finally lands.
    for (final release in h.server.pending) {
      release();
    }

    // The request is refused rather than quietly ignored, and the difference
    // matters: "ignored" is a property of whoever happened to be holding the
    // result, and there are dozens of those. Refusing it in the transport is
    // one rule that every call obeys, including ones not written yet.
    await expectLater(slow, throwsA(isA<StaleSessionException>()));
    await Future<void>.delayed(Duration.zero);

    expect(
      h.state.conversations.contacts,
      isEmpty,
      reason: "a reply addressed to A's session must not land in B's screen",
    );
  });

  test('a history left behind by a half-finished sign-out is not adopted',
      () async {
    // The case a clean sign-out does not cover: the phone is killed between
    // clearing the archive and clearing the keystore, or the app is force-quit
    // while signed in and the next person signs up instead of in. The history
    // is still on disk and the session that owned it is not.
    final h = await build();
    expect(await h.state.register(username: 'anna', password: 'pw'), isTrue);

    h.services.store.upsertUser(const KnownUser(accountId: 'acc-carl', username: 'carl'));
    h.services.store.append(
      'acc-carl',
      Message(id: 'm1', body: 'private to anna', sentAt: DateTime(2026), isMine: false),
    );
    await h.state.conversations.flush();
    expect(await h.archive.sizeInBytes(), greaterThan(0), reason: 'A wrote a history');

    // Cleared, so what the assertion below sees can only have come back from
    // the archive rather than having been left in memory by the setup.
    h.services.store.clear();

    // B arrives with A's sealed history still sitting there, and with the key
    // that opens it — the worst case, not the convenient one.
    final b = ConversationController(h.services)..accountId = 'acc-bodo';
    await b.restore();

    expect(
      h.services.store.conversationWith('acc-carl'),
      isNull,
      reason: "the archive names its owner, and it is not B",
    );
  });

  test('an archive from before owners were stamped still opens', () async {
    // Every history already on a phone was written without an owner. Refusing
    // those would be a data-loss bug dressed up as a security fix: there is no
    // second account on those devices for it to have leaked to.
    final h = await build();
    h.services.store.upsertUser(const KnownUser(accountId: 'acc-carl', username: 'carl'));
    h.services.store.append(
      'acc-carl',
      Message(id: 'm1', body: 'from before', sentAt: DateTime(2026), isMine: false),
    );
    await h.services.archive.save(h.services.store.conversations());
    h.services.store.clear();

    final anna = ConversationController(h.services)..accountId = 'acc-anna';
    await anna.restore();
    expect(h.services.store.conversationWith('acc-carl'), isNotNull);
  });
}
