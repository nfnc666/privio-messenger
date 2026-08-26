import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:image/image.dart' as img;
import 'package:privio/media/avatar.dart';
import 'package:privio/services/messaging_service.dart';

/// A stand-in for the Privio API that behaves the way the real one does: it
/// holds published public keys and sealed envelopes, hands out one one-time
/// prekey per bundle request, rejects a send that misses a recipient device,
/// and keeps envelopes until they are acknowledged.
class FakeServer {
  final Map<String, FakeAccount> accounts = {};
  final List<Map<String, dynamic>> envelopes = [];
  final Map<String, List<int>> media = {};
  final Map<String, String> avatars = {};
  int _nextEnvelopeId = 1;
  int _nextMediaId = 1;

  /// How many of the next sends answer with a stale-device-list rejection.
  int mismatchesToServe = 0;
  int sendAttempts = 0;

  FakeDevice register(String username, String accountId, int deviceIndex, Map<String, dynamic> payload) {
    final account = accounts.putIfAbsent(username, () => FakeAccount(accountId));
    final device = FakeDevice(
      deviceId: '$username-device-$deviceIndex',
      deviceIndex: deviceIndex,
      registrationId: payload['registrationId'] as int,
      identityKey: payload['identityKey'] as String,
      signedPreKey: payload['signedPreKey'] as Map<String, dynamic>,
      preKeys: [
        for (final key in payload['oneTimePreKeys'] as List<dynamic>)
          key as Map<String, dynamic>,
      ],
    );
    account.devices.add(device);
    return device;
  }

  http.Client clientFor(String deviceId) => MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (method == 'PUT' && path == '/v1/accounts/me/avatar') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          avatars[deviceId] = body['mediaId'] as String;
          return _json({'avatarMediaId': body['mediaId']});
        }

        if (method == 'POST' && path == '/v1/media') {
          final id = 'media-${_nextMediaId++}';
          media[id] = request.bodyBytes;
          return _json({'id': id, 'byteSize': request.bodyBytes.length}, status: 201);
        }

        if (method == 'GET' && path.startsWith('/v1/media/')) {
          final id = path.split('/').last;
          final stored = media[id];
          if (stored == null) return _json({'error': 'media_not_found'}, status: 404);
          return http.Response.bytes(stored, 200,
              headers: {'content-type': 'application/octet-stream'},);
        }

        if (method == 'GET' && path.startsWith('/v1/keys/count')) {
          final device = _deviceById(deviceId);
          return _json({'remaining': device.preKeys.length});
        }

        if (method == 'POST' && path == '/v1/keys/one-time') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final device = _deviceById(deviceId);
          device.preKeys.addAll(
            (body['keys'] as List<dynamic>).cast<Map<String, dynamic>>(),
          );
          return _json({'remaining': device.preKeys.length});
        }

        if (method == 'GET' && path.startsWith('/v1/keys/')) {
          final username = path.split('/').last;
          final account = accounts[username]!;
          return _json({
            'accountId': account.id,
            'username': username,
            'devices': [for (final device in account.devices) device.bundle()],
          });
        }

        if (method == 'POST' && path == '/v1/messages') {
          sendAttempts += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final account = accounts[body['username'] as String]!;
          final sender = _deviceById(deviceId);
          final messages = (body['messages'] as List<dynamic>).cast<Map<String, dynamic>>();

          if (mismatchesToServe > 0) {
            mismatchesToServe -= 1;
            return _json({
              'error': 'device_mismatch',
              'message': 'Recipient device list is stale',
              'missingDevices': [account.devices.last.deviceId],
            }, status: 409,);
          }

          final expected = account.devices.map((d) => d.deviceId).toSet();
          final provided = messages.map((m) => m['deviceId'] as String).toSet();
          if (expected.length != provided.length ||
              !expected.containsAll(provided)) {
            return _json({
              'error': 'device_mismatch',
              'message': 'Recipient device list is stale',
              'missingDevices': expected.difference(provided).toList(),
            }, status: 409,);
          }

          for (final message in messages) {
            envelopes.add({
              'id': _nextEnvelopeId++,
              'recipientDeviceId': message['deviceId'],
              'type': message['type'],
              'senderAccountId': _accountIdOf(sender),
              'senderDeviceId': sender.deviceId,
              'senderDeviceIndex': sender.deviceIndex,
              'groupId': null,
              'content': message['content'],
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
          return _json({'accepted': true, 'deliveredTo': messages.length}, status: 202);
        }

        if (method == 'GET' && path == '/v1/messages') {
          final mine = envelopes.where((e) => e['recipientDeviceId'] == deviceId).toList();
          return _json({
            'envelopes': [
              for (final envelope in mine)
                {
                  'id': envelope['id'],
                  'type': envelope['type'],
                  'senderAccountId': envelope['senderAccountId'],
                  'senderDeviceId': envelope['senderDeviceId'],
                  'senderDeviceIndex': envelope['senderDeviceIndex'],
                  'groupId': envelope['groupId'],
                  'content': envelope['content'],
                  'createdAt': envelope['createdAt'],
                },
            ],
            'more': false,
          });
        }

        if (method == 'DELETE' && path == '/v1/messages') {
          final upTo = int.parse(request.url.queryParameters['upTo']!);
          envelopes.removeWhere(
            (e) => e['recipientDeviceId'] == deviceId && (e['id'] as int) <= upTo,
          );
          return _json({'acknowledged': true});
        }

        return _json({'error': 'not_found', 'message': path}, status: 404);
      });

  FakeDevice _deviceById(String deviceId) => accounts.values
      .expand((account) => account.devices)
      .firstWhere((device) => device.deviceId == deviceId);

  String _accountIdOf(FakeDevice device) => accounts.values
      .firstWhere((account) => account.devices.contains(device))
      .id;

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

class FakeAccount {
  FakeAccount(this.id);
  final String id;
  final List<FakeDevice> devices = [];
}

class FakeDevice {
  FakeDevice({
    required this.deviceId,
    required this.deviceIndex,
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKey,
    required this.preKeys,
  });

  final String deviceId;
  final int deviceIndex;
  final int registrationId;
  final String identityKey;
  final Map<String, dynamic> signedPreKey;
  final List<Map<String, dynamic>> preKeys;

  Map<String, dynamic> bundle() => {
        'deviceId': deviceId,
        'deviceIndex': deviceIndex,
        'registrationId': registrationId,
        'identityKey': identityKey,
        'signedPreKey': signedPreKey,
        'oneTimePreKey': preKeys.isEmpty ? null : preKeys.removeAt(0),
      };
}

/// One participant: crypto, transport and the service that joins them.
class Participant {
  Participant(this.username, this.accountId, this.deviceIndex);

  final String username;
  final String accountId;
  final int deviceIndex;
  late final String deviceId;
  late final PrivioCrypto crypto;
  late final MessagingService messaging;

  Future<void> join(FakeServer server) async {
    crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    final payload = await crypto.buildRegistration(
      name: 'Test',
      platform: 'ios',
      preKeyCount: 3,
    );
    deviceId = server.register(username, accountId, deviceIndex, payload).deviceId;
    final api = PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: server.clientFor(deviceId),
    )..useToken('token-$deviceId');
    messaging = MessagingService(api: api, crypto: crypto);
  }
}

void main() {
  late FakeServer server;
  late Participant alice;
  late Participant bob;

  setUp(() async {
    server = FakeServer();
    alice = Participant('alice', 'account-alice', 1);
    bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);
  });

  test('a message travels end to end and the server only ever holds ciphertext', () async {
    await alice.messaging.sendToUser('bob', 'Bis später!');

    expect(server.envelopes, hasLength(1));
    expect(
      utf8.decode(base64Decode(server.envelopes.single['content'] as String), allowMalformed: true),
      isNot(contains('später')),
      reason: 'this is exactly what the server database would hold',
    );

    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty);
    expect(received.messages.single.body, 'Bis später!');
    expect(received.messages.single.senderAccountId, alice.accountId);
  });

  test('envelopes are acknowledged only after they decrypt', () async {
    await alice.messaging.sendToUser('bob', 'eins');
    expect(server.envelopes, hasLength(1));

    await bob.messaging.receive();
    expect(server.envelopes, isEmpty, reason: 'acknowledged after decryption');

    final second = await bob.messaging.receive();
    expect(second.messages, isEmpty, reason: 'nothing is redelivered');
  });

  test('a stale device list is refetched and the send retried once', () async {
    server.mismatchesToServe = 1;

    await alice.messaging.sendToUser('bob', 'trotzdem angekommen');

    expect(server.sendAttempts, 2, reason: 'one rejection, one successful retry');
    final received = await bob.messaging.receive();
    expect(received.messages.single.body, 'trotzdem angekommen');
  });

  test('a mismatch that survives a refetch is reported, not retried forever', () async {
    // Two in a row is not a race any more — it is a bug or an attack, and the
    // caller has to see it rather than the client looping.
    server.mismatchesToServe = 2;

    await expectLater(
      alice.messaging.sendToUser('bob', 'geht nicht'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'device_mismatch')),
    );
    expect(server.sendAttempts, 2, reason: 'exactly one retry, then it gives up');
  });

  test('a tampered envelope is reported, not silently dropped', () async {
    await alice.messaging.sendToUser('bob', 'Überweisung 100 Euro');

    final content = base64Decode(server.envelopes.single['content'] as String);
    content[content.length - 5] ^= 0xFF;
    server.envelopes.single['content'] = base64Encode(content);

    final received = await bob.messaging.receive();
    expect(received.messages, isEmpty);
    expect(received.failures, hasLength(1));
    expect(server.envelopes, isEmpty, reason: 'a poison envelope must not block the queue');
  });

  test('a conversation continues in both directions', () async {
    await alice.messaging.sendToUser('bob', 'Hallo');
    await bob.messaging.receive();

    await bob.messaging.sendToUser('alice', 'Hallo zurück');
    final atAlice = await alice.messaging.receive();
    expect(atAlice.messages.single.body, 'Hallo zurück');

    await alice.messaging.sendToUser('bob', 'Und noch eine');
    final atBob = await bob.messaging.receive();
    expect(atBob.messages.single.body, 'Und noch eine');
  });

  test('prekeys are topped up when the pool runs low', () async {
    // Three were published and the low-water mark is far above that.
    final remaining = await alice.messaging.maintainPreKeys();
    expect(remaining, PrivioCrypto.preKeyBatchSize);

    // Ids must not collide with the ones already on the server.
    final device = server.accounts['alice']!.devices.single;
    final ids = device.preKeys.map((k) => k['keyId'] as int).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'no reused prekey ids');
  });
  test('a photo arrives with its metadata stripped', () async {
    final photo = File('test/fixtures/photo_with_exif.jpg').readAsBytesSync();
    // The fixture really does carry a camera model, a serial number and GPS.
    expect(utf8.decode(photo, allowMalformed: true), contains('ACME Ultra 12 Pro'));

    final report = await alice.messaging.sendAttachment(
      'bob',
      file: photo,
      fileName: 'urlaub.jpg',
    );
    expect(report.removed, contains('EXIF / XMP (camera, GPS, timestamps)'));

    // What the server now holds must give nothing away.
    final stored = server.media.values.single;
    final storedText = utf8.decode(stored, allowMalformed: true);
    expect(storedText, isNot(contains('ACME')));
    expect(storedText, isNot(contains('urlaub.jpg')));
    expect(utf8.decode(base64Decode(server.envelopes.single['content'] as String),
        allowMalformed: true,), isNot(contains('urlaub.jpg')),);

    final received = await bob.messaging.receive();
    final payload = received.messages.single.payload;
    expect(payload.isMedia, isTrue);
    expect(payload.fileName, 'urlaub.jpg', reason: 'the name rides inside the sealed message');
    expect(payload.mediaType, 'image/jpeg');

    final opened = await bob.messaging.openAttachment(payload);
    final openedText = utf8.decode(opened, allowMalformed: true);
    expect(openedText, isNot(contains('ACME')), reason: 'no camera or serial number');
    expect(openedText, isNot(contains('SN-4711-XYZ')));
    expect(opened.sublist(0, 2), [0xFF, 0xD8], reason: 'still a usable JPEG');
  });

  test('upload size is a bucket, never the file’s real size', () async {
    // Files of different real sizes that land in the same bucket become
    // indistinguishable; the exact size is never on the wire.
    for (final length in [40, 100, 200]) {
      await alice.messaging.sendAttachment(
        'bob',
        file: Uint8List.fromList(List.filled(length, 7)),
        fileName: 'datei-$length.bin',
      );
    }

    final sizes = server.media.values.map((bytes) => bytes.length).toSet();
    expect(sizes, hasLength(1), reason: '40, 100 and 200 bytes all look the same');
    expect(sizes.single, isNot(anyOf(40, 100, 200)));

    // A larger file steps to the next bucket rather than revealing its length:
    // an observer learns the size only to within a factor of two.
    await alice.messaging.sendAttachment(
      'bob',
      file: Uint8List.fromList(List.filled(300, 9)),
      fileName: 'groesser.bin',
    );
    final withLarger = server.media.values.map((bytes) => bytes.length).toSet();
    expect(withLarger, hasLength(2));
    expect(withLarger.reduce((a, b) => a > b ? a : b), isNot(300));
  });

  test('a file the server tampered with will not open', () async {
    final payloadSource = await alice.messaging.sendAttachment(
      'bob',
      file: File('test/fixtures/image_with_text.png').readAsBytesSync(),
      fileName: 'bild.png',
    );
    expect(payloadSource.recognised, isTrue);

    final id = server.media.keys.single;
    final tampered = [...server.media[id]!];
    tampered[tampered.length ~/ 2] ^= 0xFF;
    server.media[id] = tampered;

    final received = await bob.messaging.receive();
    await expectLater(
      bob.messaging.openAttachment(received.messages.single.payload),
      throwsA(isA<Exception>()),
      reason: 'a modified file must fail rather than be shown as genuine',
    );
  });
  test('a profile picture reaches a contact and nobody else', () async {
    // What a phone would hand over: a wide photo with camera tags.
    final source = img.encodeJpg(img.Image(width: 900, height: 600), quality: 90);
    final prepared = AvatarImage.prepare(Uint8List.fromList(source))!;

    final mediaId = await alice.messaging.uploadAvatar(prepared);
    expect(server.avatars[alice.deviceId], mediaId);

    // The server now holds the picture. It must not be a picture to the server.
    final stored = Uint8List.fromList(server.media[mediaId]!);
    expect(stored.sublist(0, 3), isNot([0xFF, 0xD8, 0xFF]));
    expect(utf8.decode(stored, allowMalformed: true), isNot(contains('JFIF')));

    // A contact who has been sent the profile key can open it.
    final profileKey = await alice.crypto.profileKey();
    final opened = await bob.messaging.openAvatar(mediaId, profileKey);
    expect(opened, prepared);
    expect(img.decodeImage(opened)?.width, AvatarImage.size);

    // Someone who has not cannot.
    await expectLater(
      bob.messaging.openAvatar(mediaId, await bob.crypto.profileKey()),
      throwsA(isA<Exception>()),
    );
  });

  test('the profile key travels with an ordinary message', () async {
    await alice.messaging.sendToUser('bob', 'hallo');

    // Read the wire bytes first: receiving acknowledges, which deletes them.
    final onTheWire = utf8.decode(
      base64Decode(server.envelopes.single['content'] as String),
      allowMalformed: true,
    );

    final received = await bob.messaging.receive();
    final key = received.messages.single.payload.profileKey;

    expect(key, isNotNull, reason: 'this is how a contact comes to see your picture');
    expect(base64Decode(key!), await alice.crypto.profileKey());

    // And it was inside the sealed payload, not next to it.
    expect(onTheWire, isNot(contains(key)));
  });
}
