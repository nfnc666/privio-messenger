import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/services/realtime_connection.dart';
import 'package:web_socket_channel/io.dart';

/// A real WebSocket server, so the connection is exercised over an actual
/// socket rather than a stand-in for one.
class TestSocketServer {
  TestSocketServer._(this._server);

  static Future<TestSocketServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = TestSocketServer._(server);
    unawaited(instance._accept());
    return instance;
  }

  final HttpServer _server;
  final List<String> received = [];
  final List<Uri> handshakes = [];

  WebSocket? _socket;
  int connections = 0;

  Uri get baseUrl => Uri.parse('http://${_server.address.host}:${_server.port}');

  Future<void> _accept() async {
    await for (final request in _server) {
      handshakes.add(request.uri);
      final socket = await WebSocketTransformer.upgrade(request);
      _socket = socket;
      connections += 1;
      socket.listen(
        (dynamic frame) => received.add(frame as String),
        onDone: () {},
        onError: (Object _) {},
      );
    }
  }

  void push(Object frame) => _socket?.add(jsonEncode(frame));

  /// Drops the connection the way a server restart or a lost network would.
  Future<void> dropConnection() async => _socket?.close();

  Future<void> stop() async {
    await _socket?.close();
    await _server.close(force: true);
  }
}

void main() {
  late TestSocketServer server;
  late RealtimeConnection connection;

  setUp(() async {
    server = await TestSocketServer.start();
  });

  tearDown(() async {
    await connection.close();
    await server.stop();
  });

  RealtimeConnection connect({String token = 'test-token'}) => connection =
      RealtimeConnection(
        baseUrl: server.baseUrl,
        token: token,
        connect: (uri) => IOWebSocketChannel.connect(uri),
      );

  /// Waits for [check] to hold, so tests do not depend on fixed sleeps.
  Future<void> waitUntil(bool Function() check, {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!check()) {
      if (DateTime.now().isAfter(deadline)) fail(reason ?? 'Condition never became true');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('authenticates the handshake with the session token', () async {
    connect(token: 'secret-token').start();
    await waitUntil(() => server.handshakes.isNotEmpty, reason: 'never connected');

    final uri = server.handshakes.single;
    expect(uri.path, '/v1/ws');
    expect(uri.queryParameters['token'], 'secret-token');
  });

  test('delivers pushed envelopes without any polling', () async {
    final batches = <List<dynamic>>[];
    connect()
      ..envelopes.listen(batches.add)
      ..start();
    await waitUntil(() => server.connections == 1);

    server.push({
      'type': 'envelopes',
      'envelopes': [
        {'id': 7, 'type': 'ciphertext', 'content': 'AAAA'},
      ],
    });

    await waitUntil(() => batches.isNotEmpty, reason: 'nothing arrived');
    expect(batches.single.single, containsPair('id', 7));
  });

  test('acknowledges on the same socket the envelopes arrived on', () async {
    connect().start();
    await waitUntil(() => server.connections == 1);

    connection.acknowledge(42);

    await waitUntil(() => server.received.isNotEmpty, reason: 'no ack was sent');
    expect(jsonDecode(server.received.single), {'type': 'ack', 'upTo': 42});
  });

  test('an empty batch is not passed on', () async {
    final batches = <List<dynamic>>[];
    connect()
      ..envelopes.listen(batches.add)
      ..start();
    await waitUntil(() => server.connections == 1);

    server.push({'type': 'envelopes', 'envelopes': <dynamic>[]});
    server.push({'type': 'pong'});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(batches, isEmpty);
  });

  test('a frame it cannot parse does not take the connection down', () async {
    final batches = <List<dynamic>>[];
    connect()
      ..envelopes.listen(batches.add)
      ..start();
    await waitUntil(() => server.connections == 1);

    server._socket?.add('not json at all');
    server.push({'type': 'envelopes', 'envelopes': [<String, dynamic>{'id': 1}]});

    await waitUntil(() => batches.isNotEmpty, reason: 'the connection was lost');
    expect(connection.connected.value, isTrue);
  });

  test('reconnects after the connection drops', () async {
    connect().start();
    await waitUntil(() => server.connections == 1);

    await server.dropConnection();
    await waitUntil(() => connection.connected.value == false, reason: 'never noticed the drop');

    await waitUntil(
      () => server.connections >= 2,
      reason: 'never reconnected',
    );
    expect(connection.connected.value, isTrue);
  });

  test('a rejected token stops it retrying', () async {
    connect().start();
    await waitUntil(() => server.connections == 1);

    server.push({'type': 'error', 'code': 'unauthorized'});
    await waitUntil(() => connection.connected.value == false);

    // Retrying with a token the server just refused would be a loop.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.connections, 1);
  });

  test('backoff grows rather than hammering a server that is down', () {
    expect(RealtimeConnection.minimumBackoff, const Duration(seconds: 1));
    expect(RealtimeConnection.maximumBackoff, const Duration(seconds: 60));
  });

  test('closing is final', () async {
    connect().start();
    await waitUntil(() => server.connections == 1);
    await connection.close();

    expect(() => connection.start(), throwsStateError);
  });
}
