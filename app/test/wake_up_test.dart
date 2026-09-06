import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/edition.dart';
import 'package:privio/services/notification_permission.dart';
import 'package:privio/services/wake_up.dart';

/// A distributor that is installed, or is not, without an Android device.
class FakeDistributor implements PushDistributor {
  FakeDistributor({this.endpoint = 'https://ntfy.sh/UPabc123'});

  String? endpoint;
  bool unregistered = false;

  @override
  Future<bool> isAvailable() async => endpoint != null;

  @override
  Future<String?> register() async => endpoint;

  @override
  Future<void> unregister() async => unregistered = true;
}

/// The operating system's answer about notifications, without one.
class FakePermissions implements NotificationPermissions {
  FakePermissions(this._status, {this.grantsOnRequest = true});

  NotificationPermission _status;
  final bool grantsOnRequest;
  int prompts = 0;

  @override
  Future<NotificationPermission> status() async => _status;

  @override
  Future<NotificationPermission> request() async {
    prompts += 1;
    // Both platforms show the prompt once. Asking a second time returns the
    // standing answer without showing anything, and the fake behaves the same.
    if (_status == NotificationPermission.notRequested) {
      _status = grantsOnRequest
          ? NotificationPermission.granted
          : NotificationPermission.denied;
    }
    return _status;
  }
}

PrivioApiClient _client(
  http.Response Function(http.Request request) respond, {
  List<http.Request>? seen,
}) =>
    PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async {
        seen?.add(request);
        return respond(request);
      }),
    )..useToken('token');

http.Response _ok() => http.Response('{}', 200, headers: {'content-type': 'application/json'});

void main() {
  // The channel test below reaches for the platform, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the free builds have a wake-up path that is not Google\'s', () {
    // The whole point: Libre can be woken without Firebase in the APK.
    expect(PrivioEdition.parse('libre').pushProvider, 'unifiedpush');
    expect(PrivioEdition.parse('direct').pushProvider, 'unifiedpush');
    expect(PrivioEdition.parse('play').pushProvider, 'fcm');
    expect(PrivioEdition.parse('appstore').pushProvider, 'apns');
  });

  test('registering hands the endpoint to the server, and nothing else', () async {
    final seen = <http.Request>[];
    final wakeUp = WakeUpController(
      _client((_) => _ok(), seen: seen),
      distributor: FakeDistributor(),
    );

    expect(await wakeUp.useUnifiedPush(), isTrue);
    expect(wakeUp.method, WakeUpMethod.unifiedPush);

    final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(body, {'provider': 'unifiedpush', 'token': 'https://ntfy.sh/UPabc123'});
  });

  test('no distributor installed is said plainly, and nothing is sent', () async {
    final seen = <http.Request>[];
    final wakeUp = WakeUpController(
      _client((_) => _ok(), seen: seen),
      distributor: FakeDistributor(endpoint: null),
    );

    expect(await wakeUp.useUnifiedPush(), isFalse);
    expect(seen, isEmpty);
    expect(wakeUp.method, WakeUpMethod.socket);
    expect(wakeUp.error, contains('distributor'));
  });

  test('an endpoint the server refuses leaves nothing half-registered', () async {
    // The server checks that the URL is public and https. If it says no, the
    // distributor must not be left forwarding to a device that is not listening.
    final distributor = FakeDistributor(endpoint: 'https://10.0.0.1/up');
    final wakeUp = WakeUpController(
      _client(
        (_) => http.Response(
          jsonEncode(const {
            'error': 'invalid_push_config',
            'message': 'The endpoint must be publicly routable',
          }),
          400,
          headers: {'content-type': 'application/json'},
        ),
      ),
      distributor: distributor,
    );

    expect(await wakeUp.useUnifiedPush(), isFalse);
    expect(distributor.unregistered, isTrue);
    expect(wakeUp.method, WakeUpMethod.socket);
    expect(wakeUp.error, contains('public internet'));
  });

  test('turning it off clears the server first, then the distributor', () async {
    final seen = <http.Request>[];
    final distributor = FakeDistributor();
    final wakeUp = WakeUpController(_client((_) => _ok(), seen: seen), distributor: distributor);

    await wakeUp.useUnifiedPush();
    await wakeUp.useSocketOnly();

    expect(wakeUp.method, WakeUpMethod.socket);
    expect(distributor.unregistered, isTrue);
    expect(
      jsonDecode(seen.last.body),
      {'provider': null, 'token': null},
      reason: 'a stale endpoint would have the relay posting into the void',
    );
  });

  test('a failed switch-off does not pretend it worked', () async {
    final wakeUp = WakeUpController(
      _client((_) => throw http.ClientException('offline')),
      distributor: FakeDistributor(),
    );
    // Start from the unified state without going through the network.
    await wakeUp.useSocketOnly();

    expect(wakeUp.error, contains('has not been saved'));
  });

  group('the store builds, which register themselves', () {
    final play = PrivioEdition.parse('play');

    WakeUpController controllerFor(
      FakeDistributor push,
      FakePermissions permissions, {
      List<http.Request>? seen,
      http.Response Function(http.Request)? respond,
    }) =>
        WakeUpController(
          _client(respond ?? (_) => _ok(), seen: seen),
          distributor: push,
          permissions: permissions,
          edition: play,
        );

    test('signing in asks once and registers the token', () async {
      final seen = <http.Request>[];
      final permissions = FakePermissions(NotificationPermission.notRequested);
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: 'fcm-token-1'),
        permissions,
        seen: seen,
      );

      await wakeUp.ensureRegistered();

      expect(permissions.prompts, 1, reason: 'the system shows it once; so do we');
      expect(wakeUp.method, WakeUpMethod.fcm);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['provider'], 'fcm');
      expect(body['token'], 'fcm-token-1');
    });

    test('a second sign-in does not prompt again', () async {
      final permissions = FakePermissions(NotificationPermission.granted);
      final wakeUp = controllerFor(FakeDistributor(endpoint: 'fcm-token-1'), permissions);

      await wakeUp.ensureRegistered();
      await wakeUp.ensureRegistered();

      expect(permissions.prompts, 0, reason: 'already answered, so nothing to ask');
    });

    test('a refused permission still registers, and says what was lost', () async {
      // The distinction the screen has to make: a refusal costs the
      // notification, not the message. Not registering would cost both.
      final seen = <http.Request>[];
      final permissions = FakePermissions(
        NotificationPermission.notRequested,
        grantsOnRequest: false,
      );
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: 'fcm-token-1'),
        permissions,
        seen: seen,
      );

      await wakeUp.ensureRegistered();

      expect(seen, hasLength(1), reason: 'a push still wakes the process');
      expect(wakeUp.permission, NotificationPermission.denied);
      expect(wakeUp.permissionWarning, contains('system settings'));
      expect(wakeUp.permissionWarning, contains('while Privio is open'));
    });

    test('a phone with no push service is told so, and nothing is sent', () async {
      final seen = <http.Request>[];
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: null),
        FakePermissions(NotificationPermission.granted),
        seen: seen,
      );

      await wakeUp.ensureRegistered();

      expect(seen, isEmpty, reason: 'there is no token to register');
      expect(wakeUp.method, WakeUpMethod.socket);
      expect(wakeUp.error, contains('Google Play services'));
      expect(wakeUp.error, contains('while Privio is open'));
    });

    test('a server that will not take the token leaves the socket working', () async {
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: 'fcm-token-1'),
        FakePermissions(NotificationPermission.granted),
        respond: (_) => http.Response('{}', 500),
      );

      await wakeUp.ensureRegistered();

      expect(wakeUp.method, WakeUpMethod.socket, reason: 'nothing is registered, so nothing pretends to be');
    });

    test('a reissued token replaces the one the server holds', () async {
      // Both vendors reissue: a reinstall, a restore to a new phone, or their
      // own schedule. A server left holding the old one pushes into the void.
      final seen = <http.Request>[];
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: 'fcm-token-1'),
        FakePermissions(NotificationPermission.granted),
        seen: seen,
      );
      await wakeUp.ensureRegistered();

      expect(await wakeUp.handleTokenChanged('fcm-token-2'), isTrue);

      expect(seen, hasLength(2));
      final body = jsonDecode(seen.last.body) as Map<String, dynamic>;
      expect(body['token'], 'fcm-token-2');
      expect(body['provider'], 'fcm');
    });

    test('a rotation the server never heard is not treated as registered', () async {
      var calls = 0;
      final wakeUp = controllerFor(
        FakeDistributor(endpoint: 'fcm-token-1'),
        FakePermissions(NotificationPermission.granted),
        respond: (_) => (calls++ == 0) ? _ok() : http.Response('{}', 503),
      );
      await wakeUp.ensureRegistered();

      expect(await wakeUp.handleTokenChanged('fcm-token-2'), isFalse);
    });

    test('signing out clears the server, then the vendor, in that order', () async {
      final seen = <http.Request>[];
      final push = FakeDistributor(endpoint: 'fcm-token-1');
      final wakeUp = controllerFor(push, FakePermissions(NotificationPermission.granted), seen: seen);
      await wakeUp.ensureRegistered();

      await wakeUp.signOutOfPush();

      final body = jsonDecode(seen.last.body) as Map<String, dynamic>;
      expect(body['provider'], isNull, reason: 'the relay must stop first');
      expect(body['token'], isNull);
      expect(push.unregistered, isTrue);
      expect(wakeUp.method, WakeUpMethod.socket);
    });

    test('signing out with no network still stops locally', () async {
      // Sign-out cannot be blocked by a server that is not answering: the
      // session is going away either way, and it takes the token with it.
      final push = FakeDistributor(endpoint: 'fcm-token-1');
      final wakeUp = controllerFor(
        push,
        FakePermissions(NotificationPermission.granted),
        respond: (_) => http.Response('{}', 502),
      );

      await wakeUp.signOutOfPush();

      expect(push.unregistered, isTrue);
      expect(wakeUp.method, WakeUpMethod.socket);
    });
  });

  group('the free builds, which do not', () {
    test('signing in registers nothing — the choice is the user\'s', () async {
      // Picking a distributor tells whoever runs it that this phone exists.
      // That is a disclosure, and it is not made on somebody's behalf while
      // they are looking at a chat list.
      final seen = <http.Request>[];
      final push = FakeDistributor();
      final wakeUp = WakeUpController(
        _client((_) => _ok(), seen: seen),
        distributor: push,
        permissions: FakePermissions(NotificationPermission.granted),
        edition: PrivioEdition.parse('libre'),
      );

      await wakeUp.ensureRegistered();

      expect(seen, isEmpty);
      expect(wakeUp.method, WakeUpMethod.socket);
      expect(wakeUp.isVendorPush, isFalse);
    });
  });

  test('the missing platform channel reads as "no distributor", not a crash', () async {
    // A phone with nothing installed and a build with no Android half give the
    // same answer, which is the honest one either way.
    const distributor = ChannelPushDistributor();

    expect(await distributor.isAvailable(), isFalse);
    expect(await distributor.register(), isNull);
    await distributor.unregister();
  });
}
