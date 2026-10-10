import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/services/realtime_connection.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  test('the session token is not in the handshake URL', () async {
    // It used to be, and this test used to assert that it was. #123 moved it
    // into a WebSocket subprotocol header, for the reason written on
    // `_defaultConnect`: a URL is retained by reverse proxies and access logs,
    // and a bearer token must never become part of that logging surface.
    //
    // The assertion is inverted rather than deleted. A test that checked the
    // old behaviour and was removed leaves nothing watching the new one, and
    // the thing worth watching is precisely that the token stops appearing
    // where it used to.
    connect(token: 'secret-token').start();
    await waitUntil(() => server.handshakes.isNotEmpty, reason: 'never connected');

    final uri = server.handshakes.single;
    expect(uri.path, '/v1/ws');
    expect(uri.queryParameters['token'], isNull);
    expect(
      uri.toString(),
      isNot(contains('secret-token')),
      reason: 'not under another parameter name, and not in the fragment either',
    );
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

  test('a key request arrives as a signal with nothing in it', () async {
    var asked = 0;
    connect()
      ..keyRequests.listen((_) => asked++)
      ..start();
    await waitUntil(() => server.connections == 1);

    server.push({'type': 'key-request'});

    await waitUntil(() => asked > 0, reason: 'the signal never arrived');
    expect(asked, 1);
  });

  test('a key request is not mistaken for a message', () async {
    final batches = <List<dynamic>>[];
    connect()
      ..envelopes.listen(batches.add)
      ..start();
    await waitUntil(() => server.connections == 1);

    server.push({'type': 'key-request'});
    server.push({
      'type': 'envelopes',
      'envelopes': [
        {'id': 1, 'type': 'ciphertext', 'content': 'AAAA'},
      ],
    });

    await waitUntil(() => batches.isNotEmpty);
    expect(batches, hasLength(1), reason: 'the signal carries no envelopes');
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

  // This used to check the two constants and nothing else, which is how the
  // backoff could be reset on every attempt — so never grow — with the test
  // still green. It now counts attempts against a server that refuses them,
  // on the test's clock rather than the wall's.
  testWidgets('backoff grows rather than hammering a server that is down', (tester) async {
    expect(RealtimeConnection.minimumBackoff, const Duration(seconds: 1));
    expect(RealtimeConnection.maximumBackoff, const Duration(seconds: 60));

    var attempts = 0;
    final refusing = RealtimeConnection(
      baseUrl: Uri.parse('http://127.0.0.1:9'),
      token: 'test-token',
      connect: (_) {
        attempts += 1;
        return _RefusedChannel();
      },
    )..start();

    var wasConnected = false;
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      wasConnected = wasConnected || refusing.connected.value;
    }

    // Eight seconds of refusals: tries at 0, 1, 3 and 7 seconds. Once a second
    // would be nine.
    expect(attempts, 4);
    expect(wasConnected, isFalse, reason: 'a refused handshake is not a connection');

    await tester.runAsync(refusing.close);
    connection = connect();
  });

  test('the socket URL is the host and the path, with no query and no fragment', () {
    // A browser refuses a WebSocket URL with a fragment — even an empty one —
    // so `ws://host/v1/ws?#` meant no live connection on the web at all.
    for (final (base, expected) in [
      ('http://localhost:8080', 'ws://localhost:8080/v1/ws'),
      ('https://api.example.org', 'wss://api.example.org/v1/ws'),
      ('https://api.example.org/?x=1#top', 'wss://api.example.org/v1/ws'),
    ]) {
      final url = RealtimeConnection(baseUrl: Uri.parse(base), token: 't').socketUrl;
      expect(url.toString(), expected);
      expect(url.hasQuery, isFalse);
      expect(url.hasFragment, isFalse);
    }
    connection = connect();
  });

  test('closing is final', () async {
    connect().start();
    await waitUntil(() => server.connections == 1);
    await connection.close();

    expect(() => connection.start(), throwsStateError);
  });
}

/// A server that is not there: the handshake fails and the stream ends in an
/// error, the way a refused TCP connection surfaces through the channel.
class _RefusedChannel implements WebSocketChannel {
  _RefusedChannel() {
    scheduleMicrotask(() {
      _frames.addError(const SocketException('Connection refused'));
      unawaited(_frames.close());
    });
  }

  final _frames = StreamController<dynamic>();

  @override
  Future<void> get ready => Future<void>.error(const SocketException('Connection refused'));

  @override
  Stream<dynamic> get stream => _frames.stream;

  @override
  WebSocketSink get sink => _NowhereSink();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NowhereSink implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
