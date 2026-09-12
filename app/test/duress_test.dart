import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/disguise/launcher_disguise.dart';
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
  String duressCode = '9119';
  final List<String> wipeAttempts = [];

  http.Response call(http.Request request) {
    if (!reachable) throw const SocketFailure();
    if (request.url.path == '/v1/accounts/me/wipe') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final code = body['duressCode'] as String;
      wipeAttempts.add(code);
      if (code != duressCode) {
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
  Device({
    required this.server,
    required this.store,
    required this.archive,
    this.launcher,
    this.supportsDisguise = true,
  });

  /// Whether this stands in for a phone the disguise is offered on.
  final bool supportsDisguise;

  /// Stands in for the platform's launcher entry where a test drives one.
  final LauncherDisguise? launcher;

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
      launcher: launcher ?? const NoLauncherDisguise(),
      supportsDisguise: supportsDisguise,
    );
    await state.initialise();
  }
}

/// A device that is signed in, locked with a PIN, and armed with a duress code.
Future<Device> armedDevice({
  bool reachable = true,
  LauncherDisguise? launcher,
  bool supportsDisguise = true,
}) async {
  final server = FakeWipeServer(reachable: reachable);
  final store = InMemorySecureStore();
  await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
  await store.setPasscode('1234', PasscodeKind.digits4);
  await store.setDuressCode('9119');

  final archive = InMemoryMessageStore()
    ..upsertUser(const KnownUser(accountId: 'acc-alice', username: 'alice'))
    ..append(
      'acc-alice',
      Message(id: '1', body: 'the thing they want to read', sentAt: DateTime.now(), isMine: false),
    );

  final device = Device(
    server: server,
    store: store,
    archive: archive,
    launcher: launcher,
    supportsDisguise: supportsDisguise,
  );
  await device.boot();
  return device;
}

void main() {
  test('the right passcode unlocks and touches nothing', () async {
    final device = await armedDevice();
    expect(device.state.stage, AppStage.locked);

    expect(await device.state.unlockWithPasscode('1234'), isTrue);
    expect(device.state.stage, AppStage.ready);
    expect(device.archive.conversations(), isNotEmpty);
    expect(device.server.wipeAttempts, isEmpty);
    device.state.conversations.stop();
  });

  test('a wrong passcode is refused and touches nothing', () async {
    final device = await armedDevice();

    expect(await device.state.unlockWithPasscode('4321'), isFalse);
    expect(device.archive.conversations(), isNotEmpty);
    expect(device.server.wipeAttempts, isEmpty);
  });

  test('the duress code answers exactly as a wrong passcode does', () async {
    final device = await armedDevice();

    expect(
      await device.state.unlockWithPasscode('9119'),
      isFalse,
      reason: 'a wipe and a typo have to look the same from outside',
    );
    expect(device.state.stage, AppStage.locked);
  });

  test('the duress code destroys what this device holds', () async {
    final device = await armedDevice();
    final identityBefore = await device.cryptoStorage.readBytes('identity');
    expect(identityBefore, isNotNull, reason: 'there was one to destroy');
    await device.state.unlockWithPasscode('9119');
    await pumpEventQueue();

    expect(device.archive.conversations(), isEmpty, reason: 'the history is gone');
    expect(await device.store.readToken(), isNull, reason: 'the session is gone');
    expect(await device.store.hasPasscode(), isFalse);
    // Not empty: replaced. What matters is that the identity everything was
    // sealed to is unrecoverable, and a device that keeps the old one loaded
    // in memory would publish it again on the next registration — with its
    // private half stored nowhere. A wiped device looks like a fresh one.
    expect(
      await device.cryptoStorage.readBytes('identity'),
      isNot(identityBefore),
      reason: 'the identity is gone, so nothing sealed to it can ever be opened',
    );
    expect(await device.cryptoStorage.read('registration_id'), isNotNull);
  });

  test('and asks the server to destroy what it holds', () async {
    final device = await armedDevice();
    await device.state.unlockWithPasscode('9119');
    await pumpEventQueue();

    expect(device.server.wipeAttempts, ['9119']);
  });

  test('a device with no signal still loses its copy', () async {
    // The phone is in someone else's hands. The network is the part that might
    // not be there, so nothing local may wait on it.
    final device = await armedDevice(reachable: false);
    await device.state.unlockWithPasscode('9119');
    await pumpEventQueue();

    expect(device.archive.conversations(), isEmpty);
    expect(await device.store.readToken(), isNull);
  });

  test('the lock screen a wipe leaves behind is not a dead end', () async {
    final device = await armedDevice();
    await device.state.unlockWithPasscode('9119');
    await pumpEventQueue();

    expect(
      device.state.stage,
      AppStage.locked,
      reason: 'the wipe itself still passes for a typo to whoever is watching',
    );

    // The passcode was destroyed with everything else, so nothing opens this
    // screen any more — including what its owner knows. One entry later the app
    // is where a fresh install is, instead of a lock nobody can pass until
    // somebody thinks to kill the app.
    expect(await device.state.unlockWithPasscode('1234'), isFalse);
    expect(device.state.stage, AppStage.welcome);
  });

  test('and a restart lands in the same place', () async {
    final device = await armedDevice();
    await device.state.unlockWithPasscode('9119');
    await pumpEventQueue();

    final restarted = Device(
      server: device.server,
      store: device.store,
      archive: device.archive,
    );
    await restarted.boot();

    expect(restarted.state.stage, AppStage.welcome);
    expect(restarted.state.screenLockSet, isFalse);
  });

  group('text size', () {
    test('is remembered, and comes back at the size it was left', () async {
      final store = InMemorySecureStore();
      final first = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await first.boot();
      first.state.conversations.stop();

      expect(first.state.textScale, 1, reason: 'the design size, until asked otherwise');
      expect(first.state.textScaleId, 'medium');

      await first.state.setTextScale(AppState.textScales['larger']!);
      expect(first.state.textScaleId, 'larger');

      final second = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await second.boot();
      second.state.conversations.stop();

      expect(second.state.textScale, AppState.textScales['larger']);
    });

    test('an unrecognised scale falls back to a label rather than crashing', () async {
      final store = InMemorySecureStore();
      await store.writeTextScale(1.07);
      final device = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await device.boot();
      device.state.conversations.stop();

      expect(device.state.textScale, 1.07, reason: 'what was stored is what applies');
      expect(device.state.textScaleId, 'medium', reason: 'no row is ticked wrongly');
    });
  });

  group('the passcode shapes', () {
    test('four digits, six digits, or a phrase with a letter in it', () {
      expect(PasscodeKind.digits4.accepts('1234'), isTrue);
      expect(PasscodeKind.digits4.accepts('12345'), isFalse);
      expect(PasscodeKind.digits4.accepts('12a4'), isFalse);

      expect(PasscodeKind.digits6.accepts('123456'), isTrue);
      expect(PasscodeKind.digits6.accepts('1234'), isFalse);

      expect(PasscodeKind.phrase.accepts('correct horse'), isTrue);
      expect(PasscodeKind.phrase.accepts('tr0ub4dor&3'), isTrue);
      // Otherwise choosing "passphrase" and typing digits would be a six-digit
      // code wearing the label of something stronger.
      expect(PasscodeKind.phrase.accepts('123456'), isFalse);
      expect(PasscodeKind.phrase.accepts('abc'), isFalse);
    });

    test('the complaint says what is wrong, not that something is', () {
      expect(PasscodeKind.digits4.complaintAbout('1234'), isNull);
      expect(PasscodeKind.digits6.complaintAbout('12'), 'Six digits.');
      expect(PasscodeKind.phrase.complaintAbout('ab'), contains('At least'));
      expect(PasscodeKind.phrase.complaintAbout('123456'), contains('letter'));
    });

    test('a phrase unlocks the same way a keypad code does', () async {
      final store = InMemorySecureStore();
      await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
      await store.setPasscode('correct horse battery', PasscodeKind.phrase);
      final device = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await device.boot();

      expect(device.state.stage, AppStage.locked);
      expect(device.state.passcodeKind, PasscodeKind.phrase);
      expect(await device.state.unlockWithPasscode('correct horse'), isFalse);
      expect(await device.state.unlockWithPasscode('correct horse battery'), isTrue);
      device.state.conversations.stop();
    });

    test('the shape survives a restart, because the lock screen needs it', () async {
      final store = InMemorySecureStore();
      await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
      final first = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await first.boot();
      first.state.conversations.stop();
      await first.state.setScreenLock('123456', PasscodeKind.digits6);

      final second = Device(
        server: FakeWipeServer(),
        store: store,
        archive: InMemoryMessageStore(),
      );
      await second.boot();

      expect(second.state.stage, AppStage.locked);
      expect(second.state.passcodeKind, PasscodeKind.digits6);
    });

    test('a duress code only reaches the lock screen in the lock\'s own shape', () async {
      // The lock screen has nowhere to type a phrase when it draws a keypad,
      // and the screen says which one you have rather than letting you believe
      // it is armed where it cannot be.
      const lock = PasscodeKind.digits4;
      expect(lock.accepts('9119'), isTrue);
      expect(lock.accepts('911911'), isFalse);
      expect(lock.accepts('open sesame'), isFalse);
    });
  });

  test('turning the lock off takes the duress code with it', () async {
    final device = await armedDevice();
    await device.state.unlockWithPasscode('1234');
    device.state.conversations.stop();

    await device.state.clearScreenLock();

    expect(await device.store.hasPasscode(), isFalse);
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

    expect(device.state.stage, AppStage.ready, reason: 'no passcode, no lock screen');
    expect(device.state.screenLockSet, isFalse);

    await device.state.setScreenLock('1234', PasscodeKind.digits4);
    expect(device.state.screenLockSet, isTrue);
    expect(await store.hasPasscode(), isTrue);
  });
}
