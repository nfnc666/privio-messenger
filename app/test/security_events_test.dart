import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/core/security_controller.dart';
import 'package:privio/core/security_event_controller.dart';
import 'package:privio/data/security_log.dart';
import 'package:privio/models/security_event.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// A store that already holds an archive key, which is what the log seals with.
Future<InMemorySecureStore> keyed() async {
  final store = InMemorySecureStore();
  await store.writeArchiveKey(base64Encode(List<int>.filled(32, 7)));
  return store;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A server whose device list can be changed between calls.
class DeviceServer {
  List<Map<String, dynamic>> devices = [];

  http.Client client() => MockClient((request) async {
        if (request.url.path == '/v1/devices') return _json({'devices': devices});
        return _json({'error': 'not_found', 'message': request.url.path}, 404);
      });
}

void main() {
  group('the log on disk', () {
    test('what is written is not readable without the key', () async {
      final storage = InMemorySecurityLogStorage();
      final log = EncryptedSecurityLog(storage: storage, keyStore: await keyed());

      await log.append(
        SecurityEvent(
          kind: SecurityEventKind.deviceAdded,
          at: DateTime(2026, 3, 1),
          subject: 'Anna’s iPhone',
        ),
        accountId: 'account-a',
      );

      final bytes = storage.bytes!;
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains('iPhone')),
        reason: 'a device name must not be readable in the blob',
      );
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains('account-a')),
        reason: 'the owner is inside the sealed payload, not beside it',
      );
    });

    test('it reads back for the account that wrote it', () async {
      final log = EncryptedSecurityLog(
        storage: InMemorySecurityLogStorage(),
        keyStore: await keyed(),
      );
      await log.append(
        SecurityEvent(kind: SecurityEventKind.twoFactorEnabled, at: DateTime(2026, 3, 1)),
        accountId: 'account-a',
      );

      final events = await log.load(accountId: 'account-a');
      expect(events.single.kind, SecurityEventKind.twoFactorEnabled);
    });

    test('another account on the same phone sees nothing of it', () async {
      // The account-separation guarantee, at the layer that actually holds the
      // bytes. One keystore entry, two accounts, and the second must not read
      // the first one's security history.
      final log = EncryptedSecurityLog(
        storage: InMemorySecurityLogStorage(),
        keyStore: await keyed(),
      );
      await log.append(
        SecurityEvent(kind: SecurityEventKind.phoneLinked, at: DateTime(2026, 3, 1)),
        accountId: 'account-a',
      );

      expect(await log.load(accountId: 'account-b'), isEmpty);
    });

    test('a wrong key is an empty list, not half a history', () async {
      final storage = InMemorySecurityLogStorage();
      await EncryptedSecurityLog(storage: storage, keyStore: await keyed()).append(
        SecurityEvent(kind: SecurityEventKind.proxyEnabled, at: DateTime(2026, 3, 1)),
        accountId: 'account-a',
      );

      final other = InMemorySecureStore();
      await other.writeArchiveKey(base64Encode(List<int>.filled(32, 9)));
      final wrong = EncryptedSecurityLog(storage: storage, keyStore: other);

      expect(await wrong.load(accountId: 'account-a'), isEmpty);
    });

    test('with no key yet nothing is written in the clear', () async {
      // A device whose archive has never been opened has no key to seal with.
      // Dropping the event is the point: an unencrypted list of when this
      // account changed its password is what must not exist on a lost phone.
      final storage = InMemorySecurityLogStorage();
      final log = EncryptedSecurityLog(storage: storage, keyStore: InMemorySecureStore());

      await log.append(
        SecurityEvent(kind: SecurityEventKind.passwordChanged, at: DateTime(2026, 3, 1)),
        accountId: 'account-a',
      );

      expect(storage.bytes, isNull);
    });

    test('newest first, whatever order they went in', () async {
      final log = EncryptedSecurityLog(
        storage: InMemorySecurityLogStorage(),
        keyStore: await keyed(),
      );
      for (final day in [3, 1, 2]) {
        await log.append(
          SecurityEvent(kind: SecurityEventKind.proxyEnabled, at: DateTime(2026, 3, day)),
          accountId: 'account-a',
        );
      }

      final events = await log.load(accountId: 'account-a');
      expect(events.map((e) => e.at.day), [3, 2, 1]);
    });

    test('it stops growing at the limit, dropping the oldest', () async {
      final log = EncryptedSecurityLog(
        storage: InMemorySecurityLogStorage(),
        keyStore: await keyed(),
      );
      for (var i = 0; i < EncryptedSecurityLog.keep + 5; i++) {
        await log.append(
          SecurityEvent(
            kind: SecurityEventKind.proxyEnabled,
            at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
          accountId: 'account-a',
        );
      }

      final events = await log.load(accountId: 'account-a');
      expect(events, hasLength(EncryptedSecurityLog.keep));
      expect(events.last.at, DateTime(2026, 1, 1).add(const Duration(minutes: 5)));
    });

    test('a row this build does not understand is dropped, not drawn', () {
      expect(SecurityEvent.fromJson({'kind': 'somethingFromTheFuture', 'at': '2026-03-01'}),
          isNull);
      expect(SecurityEvent.fromJson({'kind': 'proxyEnabled', 'at': 'not a date'}), isNull);
    });

    test('clearing takes the blob with it', () async {
      final storage = InMemorySecurityLogStorage();
      final log = EncryptedSecurityLog(storage: storage, keyStore: await keyed());
      await log.append(
        SecurityEvent(kind: SecurityEventKind.proxyEnabled, at: DateTime(2026, 3, 1)),
        accountId: 'account-a',
      );

      await log.clear();

      expect(storage.bytes, isNull);
      expect(await log.load(accountId: 'account-a'), isEmpty);
    });
  });

  group('the controller', () {
    test('records nothing while nobody is signed in', () async {
      final storage = InMemorySecurityLogStorage();
      final controller = SecurityEventController(
        EncryptedSecurityLog(storage: storage, keyStore: await keyed()),
      );

      await controller.record(SecurityEventKind.twoFactorDisabled);

      expect(controller.events, isEmpty);
      expect(storage.bytes, isNull, reason: 'an event with no owner is filed under nobody');
    });

    test('an answer that arrives after a switch is dropped', () async {
      final controller = SecurityEventController(
        EncryptedSecurityLog(
          storage: InMemorySecurityLogStorage(),
          keyStore: await keyed(),
        ),
      );
      await controller.load('account-a');
      await controller.record(SecurityEventKind.twoFactorEnabled);
      expect(controller.events, hasLength(1));

      // The switch happens while a write is in flight.
      final pending = controller.record(SecurityEventKind.proxyEnabled);
      controller.signedOut();
      await pending;

      expect(controller.events, isEmpty);
      expect(controller.accountId, isNull);
    });

    test('only the two that matter are counted as warnings', () async {
      final controller = SecurityEventController(
        EncryptedSecurityLog(
          storage: InMemorySecurityLogStorage(),
          keyStore: await keyed(),
        ),
      );
      await controller.load('account-a');

      await controller.record(SecurityEventKind.proxyEnabled);
      await controller.record(SecurityEventKind.contactKeyChanged, subject: 'Bob');
      await controller.record(SecurityEventKind.twoFactorDisabled);

      expect(controller.events, hasLength(3));
      expect(controller.warnings, 2);
    });
  });

  group('noticing a device that was not added here', () {
    Future<(SecurityController, DeviceServer, List<SecurityEvent>)> build() async {
      final server = DeviceServer();
      final api = PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: server.client(),
      )..useToken('token');
      final recorded = <SecurityEvent>[];
      final controller = SecurityController(api, store: InMemorySecureStore())
        ..accountId = 'account-a'
        ..onSecurityEvent = (kind, {String? subject}) =>
            recorded.add(SecurityEvent(kind: kind, at: DateTime.now(), subject: subject));
      return (controller, server, recorded);
    }

    test('the first load says nothing — there is nothing to compare against',
        () async {
      final (controller, server, recorded) = await build();
      server.devices = [
        {'id': 'device-1', 'name': 'This phone', 'current': true},
        {'id': 'device-2', 'name': 'Laptop'},
      ];

      await controller.loadDevices();

      expect(
        recorded,
        isEmpty,
        reason: 'a security screen that cries wolf on first run is read once',
      );
    });

    test('a device that appears afterwards is reported by name', () async {
      final (controller, server, recorded) = await build();
      server.devices = [
        {'id': 'device-1', 'name': 'This phone', 'current': true},
      ];
      await controller.loadDevices();

      server.devices = [
        ...server.devices,
        {'id': 'device-2', 'name': 'Unknown Android'},
      ];
      await controller.loadDevices();

      expect(recorded.single.kind, SecurityEventKind.deviceAdded);
      expect(recorded.single.subject, 'Unknown Android');
    });

    test('it is reported once, not on every refresh', () async {
      final (controller, server, recorded) = await build();
      server.devices = [
        {'id': 'device-1', 'name': 'This phone', 'current': true},
      ];
      await controller.loadDevices();
      server.devices = [
        ...server.devices,
        {'id': 'device-2', 'name': 'Unknown Android'},
      ];

      await controller.loadDevices();
      await controller.loadDevices();
      await controller.loadDevices();

      expect(recorded, hasLength(1));
    });

    test('a device that disappears is reported too', () async {
      final (controller, server, recorded) = await build();
      server.devices = [
        {'id': 'device-1', 'name': 'This phone', 'current': true},
        {'id': 'device-2', 'name': 'Laptop'},
      ];
      await controller.loadDevices();

      server.devices = [
        {'id': 'device-1', 'name': 'This phone', 'current': true},
      ];
      await controller.loadDevices();

      expect(recorded.single.kind, SecurityEventKind.deviceRemoved);
    });

    test('with no store behind it nothing is remembered and nothing is claimed',
        () async {
      final server = DeviceServer()
        ..devices = [
          {'id': 'device-1', 'name': 'This phone', 'current': true},
        ];
      final api = PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: server.client(),
      )..useToken('token');
      final recorded = <SecurityEventKind>[];
      final controller = SecurityController(api)
        ..accountId = 'account-a'
        ..onSecurityEvent = (kind, {String? subject}) => recorded.add(kind);

      await controller.loadDevices();
      server.devices = [
        ...server.devices,
        {'id': 'device-2', 'name': 'Laptop'},
      ];
      await controller.loadDevices();

      expect(recorded, isEmpty);
    });
  });
}
