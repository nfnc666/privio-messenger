import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/biometric_gate.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';

/// Records what the device asked the server to do, and answers the way the real
/// one does: the wrong code is refused exactly as a wrong password is.
class FakeWipeServer {
  FakeWipeServer({this.reachable = true});

  bool reachable;
  String wipeCode = '9119';
  final List<String> wipeAttempts = [];

  http.Response call(http.Request request) {
    if (!reachable) throw const SocketFailure();
    if (request.url.path == '/v1/accounts/me/wipe') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final code = body['wipeCode'] as String;
      wipeAttempts.add(code);
      if (code != wipeCode) {
        return _json({'error': 'invalid_credentials', 'message': 'no'}, 401);
      }
      return _json({'wiped': true});
    }
    return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'remaining': 100});
  }

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

class SocketFailure implements Exception {
  const SocketFailure();
}

class Device {
  Device({required this.server, required this.store, required this.archive});

  final FakeWipeServer server;
  final InMemorySecureStore store;
  final InMemoryMessageStore archive;
  late final AppState state;
  late final InMemoryCryptoStorage cryptoStorage;

  Future<void> boot() async {
    final api = PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async => server.call(request)),
    );
    cryptoStorage = InMemoryCryptoStorage();
    final crypto = await PrivioCrypto.open(cryptoStorage);
    final messaging = MessagingService(api: api, crypto: crypto);
    state = AppState(
      services: PrivioServices(
        api: api,
        crypto: crypto,
        messaging: messaging,
        channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(api: api, store: store, messages: archive),
        store: archive,
        secureStore: store,
      ),
      store: store,
      biometrics: const NoBiometrics(),
    );
    await state.initialise();
  }
}

/// A device that is signed in, locked with a PIN, and armed with a duress code.
Future<Device> armedDevice({bool reachable = true}) async {
  final server = FakeWipeServer(reachable: reachable);
  final store = InMemorySecureStore();
  await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
  await store.setPin('1234');
  await store.setDuressCode('9119');

  final archive = InMemoryMessageStore()
    ..upsertUser(const KnownUser(accountId: 'acc-alice', username: 'alice'))
    ..append(
      'acc-alice',
      Message(id: '1', body: 'the thing they want to read', sentAt: DateTime.now(), isMine: false),
    );

  final device = Device(server: server, store: store, archive: archive);
  await device.boot();
  return device;
}

void main() {
  test('the right PIN unlocks and touches nothing', () async {
    final device = await armedDevice();
    expect(device.state.stage, AppStage.locked);

    expect(await device.state.unlockWithPin('1234'), isTrue);
    expect(device.state.stage, AppStage.ready);
    expect(device.archive.conversations(), isNotEmpty);
    expect(device.server.wipeAttempts, isEmpty);
    device.state.conversations.stop();
  });

  test('a wrong PIN is refused and touches nothing', () async {
    final device = await armedDevice();

    expect(await device.state.unlockWithPin('4321'), isFalse);
    expect(device.archive.conversations(), isNotEmpty);
    expect(device.server.wipeAttempts, isEmpty);
  });

  test('the duress code answers exactly as a wrong PIN does', () async {
    final device = await armedDevice();

    expect(
      await device.state.unlockWithPin('9119'),
      isFalse,
      reason: 'a wipe and a typo have to look the same from outside',
    );
    expect(device.state.stage, AppStage.locked);
  });

  test('the duress code destroys what this device holds', () async {
    final device = await armedDevice();
    await device.state.unlockWithPin('9119');
    await pumpEventQueue();

    expect(device.archive.conversations(), isEmpty, reason: 'the history is gone');
    expect(await device.store.readToken(), isNull, reason: 'the session is gone');
    expect(await device.store.hasPin(), isFalse);
    expect(
      await device.cryptoStorage.readBytes('identity'),
      isNull,
      reason: 'the identity is gone, so nothing sealed to it can ever be opened',
    );
    expect(await device.cryptoStorage.read('registration_id'), isNull);
  });

  test('and asks the server to destroy what it holds', () async {
    final device = await armedDevice();
    await device.state.unlockWithPin('9119');
    await pumpEventQueue();

    expect(device.server.wipeAttempts, ['9119']);
  });

  test('a device with no signal still loses its copy', () async {
    // The phone is in someone else's hands. The network is the part that might
    // not be there, so nothing local may wait on it.
    final device = await armedDevice(reachable: false);
    await device.state.unlockWithPin('9119');
    await pumpEventQueue();

    expect(device.archive.conversations(), isEmpty);
    expect(await device.store.readToken(), isNull);
  });

  test('turning the lock off takes the duress code with it', () async {
    final device = await armedDevice();
    await device.state.unlockWithPin('1234');
    device.state.conversations.stop();

    await device.state.clearScreenLock();

    expect(await device.store.hasPin(), isFalse);
    expect(
      await device.store.verifyDuressCode('9119'),
      isFalse,
      reason: 'a code armed on a screen nobody sees is a wipe waiting to happen',
    );
  });

  test('setting a lock is what makes the lock screen possible at all', () async {
    final store = InMemorySecureStore();
    await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
    final device = Device(
      server: FakeWipeServer(),
      store: store,
      archive: InMemoryMessageStore(),
    );
    await device.boot();
    device.state.conversations.stop();

    expect(device.state.stage, AppStage.ready, reason: 'no PIN, no lock screen');
    expect(device.state.screenLockSet, isFalse);

    await device.state.setScreenLock('1234');
    expect(device.state.screenLockSet, isTrue);
    expect(await store.hasPin(), isTrue);
  });
}
