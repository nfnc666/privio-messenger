import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
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
  final Map<String, Map<String, dynamic>> groups = {};
  int _nextGroupId = 1;
  int _nextEnvelopeId = 1;
  int _nextMediaId = 1;

  /// How many of the next sends answer with a stale-device-list rejection.
  int mismatchesToServe = 0;
  int sendAttempts = 0;

  /// How many of the next sends fail outright, the way a dropped connection
  /// does — after the server has already queued the envelopes.
  int failuresAfterQueueing = 0;

  /// Idempotency keys the server has already seen, per sending device.
  final Map<String, int> seenKeys = {};

  FakeDevice register(
    String username,
    String accountId,
    int deviceIndex,
    Map<String, dynamic> payload,
  ) {
    final account = accounts.putIfAbsent(username, () => FakeAccount(accountId));
    final device = FakeDevice(
      deviceId: '$username-device-$deviceIndex',
      deviceIndex: deviceIndex,
      registrationId: payload['registrationId'] as int,
      identityKey: payload['identityKey'] as String,
      signedPreKey: payload['signedPreKey'] as Map<String, dynamic>,
      preKeys: [
        for (final key in payload['oneTimePreKeys'] as List<dynamic>) key as Map<String, dynamic>,
      ],
    );
    account.devices.add(device);
    return device;
  }

  http.Client clientFor(String deviceId) => MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (method == 'POST' && path == '/v1/groups') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = 'group-${_nextGroupId++}';
          final creator = _deviceById(deviceId);
          groups[id] = {
            'id': id,
            'role': 'admin',
            'encryptedMetadata': body['encryptedMetadata'],
            'memberIds': [_accountIdOf(creator), ...(body['memberIds'] as List<dynamic>)],
          };
          return _json(
            {
              'id': id,
              'members': [
                for (final member in groups[id]!['memberIds'] as List<dynamic>) {'id': member},
              ],
            },
            status: 201,
          );
        }

        if (method == 'GET' && path == '/v1/groups') {
          return _json({
            'groups': [
              for (final group in groups.values)
                {
                  'id': group['id'],
                  'role': group['role'],
                  'encryptedMetadata': group['encryptedMetadata'],
                  'memberCount': (group['memberIds'] as List<dynamic>).length,
                },
            ],
          });
        }

        if (method == 'GET' && path.endsWith('/devices')) {
          final groupId = path.split('/')[3];
          final memberIds = (groups[groupId]!['memberIds'] as List<dynamic>).cast<String>();
          final sender = _deviceById(deviceId);
          return _json({
            'devices': [
              for (final entry in accounts.entries)
                if (memberIds.contains(entry.value.id))
                  for (final device in entry.value.devices)
                    if (device.deviceId != sender.deviceId)
                      {
                        'deviceId': device.deviceId,
                        'accountId': entry.value.id,
                        'username': entry.key,
                        'deviceIndex': device.deviceIndex,
                        'registrationId': device.registrationId,
                        'identityKey': device.identityKey,
                      },
            ],
          });
        }

        if (method == 'POST' && path.startsWith('/v1/messages/group/')) {
          final groupId = path.split('/').last;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final sender = _deviceById(deviceId);
          final messages = (body['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
          for (final message in messages) {
            envelopes.add({
              'id': _nextEnvelopeId++,
              'recipientDeviceId': message['deviceId'],
              'type': message['type'],
              'senderAccountId': _accountIdOf(sender),
              'senderDeviceId': sender.deviceId,
              'senderDeviceIndex': sender.deviceIndex,
              'groupId': groupId,
              'content': message['content'],
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
          return _json({'accepted': true, 'deliveredTo': messages.length}, status: 202);
        }

        if (method == 'PUT' && path == '/v1/accounts/me/avatar') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          avatars[deviceId] = body['mediaId'] as String;
          return _json({'avatarMediaId': body['mediaId']});
        }

        if (method == 'POST' && path == '/v1/media') {
          final id = 'media-${_nextMediaId++}';
          media[id] = request.bodyBytes;
          // The real server mints a download capability here and keeps only
          // its hash; an avatar gets none, because its id is published.
          final avatar = request.url.queryParameters['kind'] == 'avatar';
          return _json({
            'id': id,
            'byteSize': request.bodyBytes.length,
            if (!avatar) 'token': 'token-$id',
          }, status: 201,);
        }

        if (method == 'GET' && path.startsWith('/v1/media/')) {
          final id = path.split('/').last;
          final stored = media[id];
          if (stored == null) return _json({'error': 'media_not_found'}, status: 404);
          return http.Response.bytes(
            stored,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
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
          // Asking for your own account means "my other devices", as the real
          // server answers it: a device never needs a session with itself, and
          // the send route would refuse a copy addressed back to the sender.
          final own = account.devices.any((device) => device.deviceId == deviceId);
          final bundles = [
            for (final device in account.devices)
              if (!(own && device.deviceId == deviceId)) device.bundle(),
          ];
          // The real server answers 404 rather than an empty list, which is
          // what tells a lone device it has nobody to copy to.
          if (bundles.isEmpty) {
            return _json(
              {'error': 'no_devices', 'message': 'User has no active devices'},
              status: 404,
            );
          }
          return _json({
            'accountId': account.id,
            'username': username,
            'devices': bundles,
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
            return _json(
              {
                'error': 'device_mismatch',
                'message': 'Recipient device list is stale',
                'missingDevices': [account.devices.last.deviceId],
              },
              status: 409,
            );
          }

          // A self-addressed send is the multi-device copy, and the real server
          // never echoes it back to the device that sent it.
          final expected = account.devices
              .map((d) => d.deviceId)
              .where((id) => id != sender.deviceId || !account.devices.contains(sender))
              .toSet();
          final provided = messages.map((m) => m['deviceId'] as String).toSet();
          if (expected.length != provided.length || !expected.containsAll(provided)) {
            return _json(
              {
                'error': 'device_mismatch',
                'message': 'Recipient device list is stale',
                'missingDevices': expected.difference(provided).toList(),
              },
              status: 409,
            );
          }

          // The real server records the key and answers a repeat with the
          // first attempt's result rather than queueing again.
          final key = body['idempotencyKey'] as String?;
          if (key != null && seenKeys.containsKey('$deviceId/$key')) {
            return _json(
              {
                'accepted': true,
                'deliveredTo': seenKeys['$deviceId/$key'],
                'duplicate': true,
              },
              status: 202,
            );
          }
          if (key != null) seenKeys['$deviceId/$key'] = messages.length;

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

          if (failuresAfterQueueing > 0) {
            // Queued, then the answer never made it back — the case a retry has
            // to survive without delivering the message twice.
            failuresAfterQueueing -= 1;
            return _json(
              {
                'error': 'unavailable',
                'message': 'connection lost',
              },
              status: 503,
            );
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

  String _accountIdOf(FakeDevice device) =>
      accounts.values.firstWhere((account) => account.devices.contains(device)).id;

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
  late final PrivioApiClient api;

  Future<void> join(FakeServer server) async {
    crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    final payload = await crypto.buildRegistration(
      name: 'Test',
      platform: 'ios',
      preKeyCount: 3,
    );
    deviceId = server.register(username, accountId, deviceIndex, payload).deviceId;
    api = PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: server.clientFor(deviceId),
    )..useToken('token-$deviceId');
    messaging = MessagingService(api: api, crypto: crypto)
      // What signing in does, so a send can address this account's own other
      // devices exactly as it does on a real device.
      ..identifyAs(username);
  }
}
