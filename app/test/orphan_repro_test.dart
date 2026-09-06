import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

/// The orphaned reservation, from the outside.
///
/// Self-contained rather than sharing the fake in `channel_service_test.dart`,
/// because it was written to compile against the client *before* the fix as
/// well — which is how the finding was confirmed rather than assumed. Run
/// against that code, the two assertions at the bottom were: epoch 2 reserved
/// on the server, and no key for it anywhere. The channel was stuck: nothing
/// could be published, the epoch could not be claimed again with a different
/// key without splitting the channel, and falling back to epoch 1 would have
/// handed the future back to whoever had just been removed.
///
/// Against the code in this branch the same interruption is survivable, which
/// is what it now asserts.
void main() {
  test('a reservation whose reply was lost is recoverable, not orphaned', () async {
    var epoch = 1;
    final claims = <int, String>{1: 'created'};
    var loseReply = false;

    final client = MockClient((request) async {
      final path = request.url.path;
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      Map<String, dynamic> json(Object b, [int s = 200]) => {'b': b, 's': s};
      http.Response ok(Object b, [int s = 200]) =>
          http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});
      json;

      if (path == '/v1/channels' && request.method == 'POST') {
        return ok({'id': 'c1', 'visibility': 'public', 'inviteCode': 'i', 'role': 'owner'}, 201);
      }
      if (path == '/v1/channels/c1/key-epochs/current') {
        return ok({'epoch': epoch, 'keyId': claims[epoch]});
      }
      if (path == '/v1/channels/c1/key-epochs' && request.method == 'POST') {
        final asked = (body['epoch'] as num).toInt();
        claims[asked] ??= body['keyId'] as String;
        // The server recorded it. The reply is lost on the way back.
        if (loseReply) return http.Response('', 502);
        return ok({'epoch': asked, 'keyId': claims[asked], 'claimed': claims[asked] == body['keyId']});
      }
      if (path == '/v1/channels/c1') return ok({'id': 'c1', 'visibility': 'public'});
      if (path == '/v1/channels/c1/members') return ok({'members': [], 'complete': true});
      if (path == '/v1/channels/c1/key-requests') return ok({'requests': []});
      return http.Response('{"error":"not_found","message":"no route"}', 404);
    });

    final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    final api = PrivioApiClient(baseUrl: Uri.parse('http://localhost:8080'), client: client)
      ..useToken('token');
    final admin = ChannelService(
      api: api,
      crypto: crypto,
      messaging: MessagingService(api: api, crypto: crypto),
    );

    await admin.create(visibility: ChannelVisibility.public, handle: 'ops', title: 'Ops');
    epoch = 2;

    loseReply = true;
    await admin.completeRotation('c1');

    expect(claims[2], isNotNull, reason: 'the server has reserved epoch 2');
    expect(
      await admin.keyFor('c1', 2),
      isNull,
      reason: 'nothing unconfirmed is ever promoted to being the channel key',
    );

    // The difference the fix makes: the key that was generated is still here,
    // written down before the request went out, so the reservation can be
    // resolved instead of being stranded.
    final pending = await admin.pendingKeyForTest('c1');
    expect(pending, isNotNull, reason: 'the candidate survived the lost reply');
    expect(pending!.epoch, 2);

    loseReply = false;
    expect(await admin.completeRotation('c1'), isTrue);
    expect(
      await admin.keyFor('c1', 2),
      equals(pending.key),
      reason: 'and the same key is promoted — not a second one generated',
    );
  });
}
