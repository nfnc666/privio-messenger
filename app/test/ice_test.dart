import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/calls/ice_servers.dart';
import 'package:privio/core/api_client.dart';

/// A server that hands out one STUN and one credentialed TURN, and counts how
/// often it was asked.
class FakeIceServer {
  FakeIceServer({this.expiresAt, this.fails = false});

  int? expiresAt;
  bool fails;
  int requests = 0;

  http.Client get client => MockClient((request) async {
        if (request.url.path != '/v1/calls/ice') {
          return http.Response('{}', 200, headers: _json);
        }
        requests += 1;
        if (fails) return http.Response('{"error":"nope"}', 503, headers: _json);
        return http.Response(
          jsonEncode({
            'iceServers': [
              {'urls': 'stun:stun.example.org:3478'},
              {
                'urls': 'turns:turn.example.org:5349',
                'username': '$expiresAt',
                'credential': 'a-minted-secret',
              },
            ],
            'expiresAt': expiresAt,
          }),
          200,
          headers: _json,
        );
      });

  static const Map<String, String> _json = {'content-type': 'application/json'};
}

void main() {
  late FakeIceServer server;
  late IceServerCache cache;
  var clock = DateTime.utc(2026, 1, 1, 12);

  setUp(() {
    server = FakeIceServer(expiresAt: DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000);
    cache = IceServerCache(
      api: PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: server.client)
        ..useToken('token'),
      now: () => clock,
    );
  });

  test('it takes what the server offers, credentials and all', () async {
    final servers = await cache.ensure();

    expect(servers.servers, hasLength(2));
    expect(servers.servers.first, {'urls': 'stun:stun.example.org:3478'});
    expect(servers.servers.last['credential'], 'a-minted-secret');
    expect(
      servers.servers.first.containsKey('credential'),
      isFalse,
      reason: 'a STUN server has none, and an empty one is not the same as none',
    );
  });

  test('it is fetched once and held, not asked for on every call', () async {
    await cache.ensure();
    await cache.ensure();
    await cache.ensure();

    expect(
      server.requests,
      1,
      reason: 'asking when a call starts would tell the server a call is starting',
    );
  });

  test('two callers at once make one request, not two', () async {
    await Future.wait([cache.ensure(), cache.ensure()]);
    expect(server.requests, 1);
  });

  test('a credential about to expire is replaced', () async {
    await cache.ensure();
    expect(server.requests, 1);

    // Five minutes before expiry counts as stale: a call that outlives its
    // relay credential loses the relay mid-sentence.
    clock = DateTime.utc(2026, 1, 1, 23, 58);
    await cache.ensure();
    expect(server.requests, 2);
  });

  test('a deployment that offers nothing is a real answer, not an error', () async {
    server.fails = true;
    final servers = await cache.ensure();

    expect(servers.isEmpty, isTrue);
    expect(
      servers.expiresAt,
      isNull,
      reason: 'a call without STUN still connects on most networks',
    );
  });

  test('signing out drops the credential with the session it belongs to', () async {
    await cache.ensure();
    expect(cache.current.isEmpty, isFalse);

    cache.clear();
    expect(cache.current.isEmpty, isTrue);
  });

  test('a server with nothing configured answers with nothing', () {
    final none = IceServers.fromJson(const {'iceServers': <Object>[], 'expiresAt': null});
    expect(none.isEmpty, isTrue);
    expect(none.isStaleAt(DateTime.now()), isFalse, reason: 'nothing cannot go stale');
  });
}
