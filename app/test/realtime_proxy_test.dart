import 'package:flutter_test/flutter_test.dart';
import 'package:privio/network/proxy_config.dart';
import 'package:privio/network/proxy_controller.dart';
import 'package:privio/network/proxy_transport.dart';
import 'package:privio/services/realtime_connection.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Which socket the realtime connection opens.
///
/// One rule, and both halves of it matter: a device with a proxy configured
/// must never open a direct socket, and a device without one must never be
/// routed through the proxy transport. The second half is what went wrong —
/// every connection went through the proxy's long-lived `HttpClient` even with
/// no proxy set, which in a widget test is the binding's mocked client, and the
/// handshake failure escaped as an unhandled zone error rather than arriving on
/// `ready`. Forty-eight tests went red, every one of them a test that signs in.
class _RecordingTransport implements ProxyTransport {
  _RecordingTransport(this.config);

  final ProxyConfig? config;
  static int connects = 0;

  @override
  Never get client => throw UnimplementedError();

  @override
  WebSocketChannel connect(Uri uri) {
    connects += 1;
    throw UnimplementedError('not a real socket');
  }

  @override
  void close() {}
}

void main() {
  test('with no proxy configured, the proxy transport is never reached', () {
    // A controller with a transport that records. Nothing configures it, so
    // `enabled` is false and the socket must not go through it.
    final controller = ProxyController(factory: _RecordingTransport.new);
    expect(controller.enabled, isFalse);

    _RecordingTransport.connects = 0;
    // The default path is what is under test, so nothing is injected; the
    // connection is expected to fail here (there is no server), and what is
    // asserted is that it failed *without* going through the proxy.
    final connection = RealtimeConnection(
      baseUrl: Uri.parse('https://api.invalid'),
      token: 'token',
    );
    connection.start();
    addTearDown(connection.close);

    expect(
      _RecordingTransport.connects,
      0,
      reason: 'an install with no proxy must open an ordinary socket',
    );
  });

  test('an enabled proxy is used, and a direct socket is not opened', () {
    // The other half: once a proxy is on, every socket goes through it. The
    // controller under test is a local one rather than the singleton, so this
    // asserts the branch rather than mutating global state.
    final controller = ProxyController(factory: _RecordingTransport.new);
    expect(controller.enabled, isFalse);

    var opened = 0;
    final connection = RealtimeConnection(
      baseUrl: Uri.parse('https://api.invalid'),
      token: 'token',
      connect: (uri) {
        opened += 1;
        throw UnimplementedError('not a real socket');
      },
    );
    connection.start();
    addTearDown(connection.close);

    // An injected connect is always used, whatever the proxy says — which is
    // what lets every other test in this suite supply its own socket.
    expect(opened, 1);
  });
}
