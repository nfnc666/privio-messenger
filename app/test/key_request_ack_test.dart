import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';

import 'support/fake_server.dart';
import 'support/fake_voice.dart';

/// Who clears a request for a key.
///
/// The server lets only the waiting device clear its own request, so that no
/// member can starve a new device of a group's key. The app was not changed
/// with it: key holders kept clearing after delivering, were refused with 403
/// every time — seen in a browser on every start — and so sent the same key
/// again on every pass, for ever. Now the device that receives the key clears
/// its own request.
void main() {
  late FakeServer server;
  late Participant alice;
  late Participant bob;
  late ConversationController bobs;

  setUp(() async {
    server = FakeServer();
    alice = Participant('alice', 'account-alice', 1);
    bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);
    final store = InMemoryMessageStore()
      ..upsertUser(KnownUser(accountId: alice.accountId, username: alice.username));
    bobs = ConversationController(
      PrivioServices(
        api: bob.api,
        crypto: bob.crypto,
        messaging: bob.messaging,
        channels: ChannelService(api: bob.api, crypto: bob.crypto, messaging: bob.messaging),
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(
          api: bob.api,
          store: InMemorySecureStore(),
          messages: InMemoryMessageStore(),
        ),
        store: store,
        secureStore: InMemorySecureStore(),
      ),
    )..accountId = bob.accountId;
    addTearDown(bobs.stop);
  });

  final groupKey = base64Encode(List<int>.filled(32, 7));

  test('a group key is delivered once, and the receiver clears its own request', () async {
    await bob.api.requestGroupKey('g1');
    expect(server.keyRequests['group:g1'], {bob.deviceId});

    expect(await alice.messaging.deliverGroupKeys('g1', groupKey), 1);
    expect(server.refused, isEmpty, reason: 'nobody clears a request that is not theirs');
    expect(server.keyRequests['group:g1'], {bob.deviceId}, reason: "still Bob's to clear");

    await bobs.drain();
    await pumpEventQueue();
    expect(bobs.groupInfo('g1')?.groupKey, groupKey);
    expect(server.keyRequests['group:g1'], isEmpty);

    expect(
      await alice.messaging.deliverGroupKeys('g1', groupKey),
      0,
      reason: 'nothing is waiting, so nothing is sent again',
    );
    expect(server.refused, isEmpty);
  });

  test('a channel key clears the channel request the same way', () async {
    await bob.api.requestChannelKey('c1');
    expect(server.keyRequests['channel:c1'], {bob.deviceId});

    await alice.messaging.deliverKey(
      username: bob.username,
      scope: 'channel',
      scopeId: 'c1',
      base64Key: groupKey,
      keyEpoch: 1,
    );
    await bobs.drain();
    await pumpEventQueue();

    expect(server.keyRequests['channel:c1'], isEmpty);
    expect(server.refused, isEmpty);
  });
}
