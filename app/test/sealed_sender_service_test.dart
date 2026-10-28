import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/sealed_sender.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/services/sealed_sender_service.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;
import 'sealed_sender_crypto_test.dart' show FakeIssuer, aliceId, bobId;

/// Sealed sender end to end: two devices, each with its own messaging service,
/// against a fake server that behaves like `server/src/routes/sealed_sender.ts`
/// where it matters — the sealed route refuses a session, checks the access
/// key, and stores no sender.

class Account {
  Account(this.username, this.device);

  final String username;
  final TestDevice device;
  String get accountId => device.accountId;
}

class FakeServer {
  final keys = FakeKeyServer();
  FakeIssuer issuer = FakeIssuer();
  final Map<String, Account> _byToken = {};
  final Map<String, Account> _byUsername = {};
  final Map<String, String> accessKeys = {};
  final Map<String, List<Map<String, dynamic>>> queues = {};
  final Map<String, Set<String>> blocks = {};
  final List<Map<String, String>> sealedHeaders = [];
  bool sealedOffered = true;
  int sealedAttempts = 0;
  bool certificates = true;
  int trustRootAsked = 0;
  int _nextId = 1;

  Future<Account> join(String username, String accountId) async {
    final device = TestDevice(accountId, 'device-$username-1', 1);
    await device.boot(keys);
    final account = Account(username, device);
    _byToken[username] = account;
    _byUsername[username] = account;
    queues[device.deviceId] = [];
    return account;
  }

  void enqueue(String deviceId, Map<String, dynamic> envelope) =>
      queues[deviceId]!.add({'id': _nextId++, 'createdAt': DateTime.now().toUtc().toIso8601String(), ...envelope});

  Account? _accountById(String id) => _byUsername.values.where((a) => a.accountId == id).firstOrNull;

  http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Response _error(int status, String code) => _json(status, {'error': code, 'message': code});

  http.Client clientFor(String token) => MockClient((request) async {
        final path = request.url.path;
        final auth = request.headers['authorization'];
        final me = auth == null ? null : _byToken[auth.replaceFirst('Bearer ', '')];

        if (request.method == 'POST' && path == '/v1/messages/sealed') {
          sealedAttempts += 1;
          if (auth != null) return _error(400, 'do_not_identify');
          if (!sealedOffered) return _error(503, 'sealed_sender_unavailable');
          sealedHeaders.add(Map.of(request.headers));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final recipient = body['accountId'] as String;
          if (accessKeys[recipient] == null ||
              accessKeys[recipient] != request.headers['unidentified-access-key']) {
            return _error(401, 'unidentified_access_denied');
          }
          final to = _accountById(recipient)!;
          for (final message in body['messages'] as List<dynamic>) {
            enqueue(to.device.deviceId, {'type': 'sealed', 'content': (message as Map)['content']});
          }
          return _json(202, {'accepted': true, 'deliveredTo': (body['messages'] as List).length});
        }
        if (me == null) return _error(401, 'unauthorized');

        if (request.method == 'GET' && path.startsWith('/v1/keys/')) {
          final username = path.substring('/v1/keys/'.length);
          final whom = _byUsername[username]!;
          if (whom == me) return _error(404, 'no_devices');
          return _json(200, {
            'accountId': whom.accountId,
            'devices': [keys.bundleFor(whom.accountId, 1)],
          });
        }
        if (request.method == 'POST' && path == '/v1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final to = _byUsername[body['username'] as String]!;
          final dropped = blocks[to.accountId]?.contains(me.accountId) ?? false;
          for (final message in body['messages'] as List<dynamic>) {
            final copy = message as Map<String, dynamic>;
            if (dropped) continue;
            enqueue(to.device.deviceId, {
              'type': copy['type'],
              'content': copy['content'],
              'senderAccountId': me.accountId,
              'senderDeviceIndex': me.device.deviceIndex,
            });
          }
          return _json(200, {'deliveredTo': (body['messages'] as List).length});
        }
        if (request.method == 'GET' && path == '/v1/messages') {
          return _json(200, {'envelopes': queues[me.device.deviceId], 'more': false});
        }
        if (request.method == 'DELETE' && path == '/v1/messages') {
          final upTo = int.parse(request.url.queryParameters['upTo']!);
          queues[me.device.deviceId]!.removeWhere((e) => (e['id'] as int) <= upTo);
          return _json(200, {});
        }
        if (request.method == 'GET' && path == '/v1/certificate/trust-root') {
          trustRootAsked += 1;
          if (!sealedOffered) return _error(503, 'sealed_sender_unavailable');
          return _json(200, {'trustRoot': base64Encode(issuer.trustRoot)});
        }
        if (request.method == 'GET' && path == '/v1/certificate/delivery') {
          if (!certificates) return _error(402, 'license_required');
          final certificate = await issuer.issue(me.device);
          return _json(200, {'certificate': base64Encode(certificate)});
        }
        if (request.method == 'PUT' && path == '/v1/accounts/me/unidentified-access') {
          accessKeys[me.accountId] = (jsonDecode(request.body) as Map)['accessKey'] as String;
          return _json(200, {'enabled': true});
        }
        if (request.method == 'GET' && path == '/v1/blocks') {
          return _json(200, {
            'blocked': [
              for (final id in blocks[me.accountId] ?? const <String>{}) {'accountId': id},
            ],
          });
        }
        return _error(404, 'not_found');
      });
}

/// One account's side: its client, messaging service and sealed sender.
class Side {
  Side(this.server, this.account, {String buildPin = ''}) {
    api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: server.clientFor(account.username))
      ..useToken(account.username);
    messaging = MessagingService(api: api, crypto: account.device.crypto)..identifyAs(account.username);
    sealed = SealedSenderService(api: api, crypto: account.device.crypto, store: store, buildPin: buildPin);
    messaging.sealedSender = sealed;
  }

  final FakeServer server;
  final Account account;
  final store = InMemorySecureStore();
  late final PrivioApiClient api;
  late final MessagingService messaging;
  late final SealedSenderService sealed;

  Future<void> start() => sealed.start(account.accountId);
}

void main() {
  late FakeServer server;
  late Side alice;
  late Side bob;

  setUpAll(() async => expect(await SealedSender.load(), isTrue));

  setUp(() async {
    server = FakeServer();
    alice = Side(server, await server.join('alice', aliceId));
    bob = Side(server, await server.join('bob', bobId));
  });

  /// Alice holds Bob's profile key, as she does once Bob has written to her.
  Future<void> aliceKnowsBob() async {
    final key = await bob.account.device.crypto.profileKey();
    alice.messaging.profileKeyOf = (accountId) => accountId == bobId ? key : null;
  }

  List<Map<String, dynamic>> bobsQueue() => server.queues[bob.account.device.deviceId]!;

  group('sending', () {
    test('goes sealed to somebody who can receive it, and arrives from the right person', () async {
      await bob.start();
      await alice.start();
      expect(alice.sealed.status, SealedSenderStatus.on);
      await aliceKnowsBob();

      await alice.messaging.sendPayload('bob', const MessagePayload.text('hallo', clientId: 'c1'));

      final envelope = bobsQueue().single;
      expect(envelope['type'], 'sealed');
      expect(envelope.containsKey('senderAccountId'), isFalse, reason: 'the server learned the sender');
      expect(server.sealedHeaders.single.containsKey('authorization'), isFalse);
      expect(server.sealedHeaders.single['unidentified-access-key'], server.accessKeys[bobId]);

      final received = await bob.messaging.receive();
      expect(received.failures, isEmpty);
      final message = received.messages.single;
      expect(message.senderAccountId, aliceId);
      expect(message.senderDeviceIndex, 1);
      expect(message.payload.body, 'hallo');
      expect(bobsQueue(), isEmpty, reason: 'it was not acknowledged');
    });

    test('goes the usual way without the recipient’s profile key', () async {
      await bob.start();
      await alice.start();

      await alice.messaging.sendPayload('bob', const MessagePayload.text('hallo'));

      expect(bobsQueue().single['type'], 'prekey');
      expect(bobsQueue().single['senderAccountId'], aliceId);
      expect(server.sealedHeaders, isEmpty);
    });

    test('falls back when the door refuses the key, and does not knock again for a while', () async {
      await bob.start();
      await alice.start();
      alice.messaging.profileKeyOf = (_) => List.filled(32, 9);

      await alice.messaging.sendPayload('bob', const MessagePayload.text('eins'));
      await alice.messaging.sendPayload('bob', const MessagePayload.text('zwei'));

      expect(server.sealedHeaders, hasLength(1));
      expect(bobsQueue().map((e) => e['type']), everyElement(isNot('sealed')));
      final received = await bob.messaging.receive();
      expect(received.messages.map((m) => m.payload.body), ['eins', 'zwei']);
    });

    test('a server that stops offering it mid-way is not asked again', () async {
      await bob.start();
      await alice.start();
      await aliceKnowsBob();
      server.sealedOffered = false;

      await alice.messaging.sendPayload('bob', const MessagePayload.text('eins'));
      await alice.messaging.sendPayload('bob', const MessagePayload.text('zwei'));

      expect(server.sealedAttempts, 1);
      expect(alice.sealed.status, SealedSenderStatus.serverOff);
      final received = await bob.messaging.receive();
      expect(received.messages.map((m) => m.payload.body), ['eins', 'zwei']);
    });

    test('nothing is sealed to this account itself', () async {
      await alice.start();
      expect(await alice.sealed.routeTo(aliceId, List.filled(32, 1)), isNull);
    });
  });

  group('setting up', () {
    test('publishes the access key derived from this account’s profile key', () async {
      await bob.start();
      final expected = await SealedSender.accessKey(await bob.account.device.crypto.profileKey());
      expect(server.accessKeys[bobId], base64Encode(expected));
    });

    test('a server without sealed sender: nothing is sealed or opened', () async {
      server.sealedOffered = false;
      await bob.start();
      await alice.start();
      await aliceKnowsBob();
      expect(alice.sealed.status, SealedSenderStatus.serverOff);
      expect(bob.sealed.canOpen, isFalse);

      await alice.messaging.sendPayload('bob', const MessagePayload.text('hallo'));
      expect(bobsQueue().single['type'], 'prekey');
      expect(server.sealedAttempts, 0);
      expect(server.accessKeys, isEmpty, reason: 'a key was published to a server that does not use it');
    });

    test('the trust root is pinned on first use, and a different one later is refused', () async {
      await alice.start();
      expect(await alice.store.readSealedTrustRoot(), base64Encode(server.issuer.trustRoot));

      server.issuer = FakeIssuer();
      await alice.start();
      expect(alice.sealed.status, SealedSenderStatus.trustRootChanged);
      expect(alice.sealed.canOpen, isFalse);
      expect(await alice.sealed.routeTo(bobId, List.filled(32, 1)), isNull,
          reason: 'something would be sealed under a root this device refused');
      expect(await alice.store.readSealedTrustRoot(), isNot(base64Encode(server.issuer.trustRoot)),
          reason: 'the new root replaced the pinned one');
    });

    test('a trust root built into the app is the only one, and the server is not asked', () async {
      final pinned = Side(
        server,
        await server.join('carol', '5a3e2c1d-0b9f-4e8d-a7c6-b5a4f3e2d1c0'),
        buildPin: base64Encode(server.issuer.trustRoot),
      );
      await pinned.start();
      expect(server.trustRootAsked, 0);
      expect(pinned.sealed.status, SealedSenderStatus.on);
    });

    test('without a certificate it still receives, and sends the usual way', () async {
      server.certificates = false;
      await bob.start();
      await alice.start();
      await aliceKnowsBob();
      expect(alice.sealed.status, SealedSenderStatus.receiveOnly);
      expect(bob.sealed.canOpen, isTrue);

      await alice.messaging.sendPayload('bob', const MessagePayload.text('hallo'));
      expect(bobsQueue().single['type'], 'prekey');
    });
  });

  group('receiving', () {
    test('a sealed message from a blocked account is dropped here, which the server cannot do',
        () async {
      await bob.start();
      await alice.start();
      await aliceKnowsBob();
      server.blocks[bobId] = {aliceId};
      await bob.messaging.refreshBlocked();

      await alice.messaging.sendPayload('bob', const MessagePayload.text('trotzdem'));
      expect(bobsQueue().single['type'], 'sealed', reason: 'the server let it through, as it must');

      final received = await bob.messaging.receive();
      expect(received.messages, isEmpty);
      expect(received.failures, isEmpty, reason: 'a dropped message is not an error to show');
      expect(bobsQueue(), isEmpty, reason: 'it was left in the queue');
    });

    test('the blocked list is read before the first sealed message, even unasked', () async {
      await bob.start();
      await alice.start();
      await aliceKnowsBob();
      server.blocks[bobId] = {aliceId};

      await alice.messaging.sendPayload('bob', const MessagePayload.text('gleich nach dem Start'));
      final received = await bob.messaging.receive();
      expect(received.messages, isEmpty);
    });

    test('a sealed envelope that will not open is reported, naming nobody', () async {
      await bob.start();
      server.enqueue(bob.account.device.deviceId, {
        'type': 'sealed',
        'content': base64Encode(Uint8List.fromList(List.filled(120, 7))),
      });

      final received = await bob.messaging.receive();
      expect(received.messages, isEmpty);
      expect(received.failures.single.senderAccountId, isNull);
    });

    test('a device that cannot open sealed messages reports them rather than guessing', () async {
      server.enqueue(bob.account.device.deviceId, {'type': 'sealed', 'content': 'AAAA'});
      final received = await bob.messaging.receive();
      expect(received.failures.single.senderAccountId, isNull);
    });
  });
}
