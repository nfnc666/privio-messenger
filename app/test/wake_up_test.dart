import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/edition.dart';
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

  test('the missing platform channel reads as "no distributor", not a crash', () async {
    // A phone with nothing installed and a build with no Android half give the
    // same answer, which is the honest one either way.
    const distributor = ChannelPushDistributor();

    expect(await distributor.isAvailable(), isFalse);
    expect(await distributor.register(), isNull);
    await distributor.unregister();
  });
}
