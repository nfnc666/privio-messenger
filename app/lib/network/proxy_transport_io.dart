import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'proxy_config.dart';
import 'proxy_transport.dart';

ProxyTransport create(ProxyConfig? config) => _NativeTransport(config);

class _NativeTransport implements ProxyTransport {
  _NativeTransport(this.config) {
    config?.validate();
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    // Never consult system/environment proxy fallback lists.
    _http.findProxy = (_) => 'DIRECT';
    if (config?.enabled ?? false) {
      _http.connectionFactory = (uri, _, __) async {
        // Login tokens must not cross a proxy in plaintext. The socket below
        // remains end-to-end TLS to the API, with normal certificate checks.
        if (uri.scheme != 'https') {
          throw const SocketException('Proxy requires HTTPS');
        }
        var cancelled = false;
        Socket? socket;
        Future<Socket> open() async {
          try {
            final addresses = await InternetAddress.lookup(config!.host);
            if (cancelled || _closed) throw const SocketException('Closed');
            final connected = await SocksTCPClient.connect([
              ProxySettings(addresses.first, config!.port,
                username: config!.username.isEmpty ? null : config!.username,
                password: config!.password.isEmpty ? null : config!.password),
            ], InternetAddress(uri.host, type: InternetAddressType.unix), uri.port);
            socket = connected;
            if (cancelled || _closed) throw const SocketException('Closed');
            // Only the proxy host is resolved locally. The destination domain
            // is sent in SOCKS5, not looked up on the device.
            final secured = await connected.secure(uri.host);
            socket = secured;
            if (cancelled || _closed) throw const SocketException('Closed');
            return secured;
          } catch (_) {
            socket?.destroy();
            rethrow;
          }
        }
        void cancel() { cancelled = true; socket?.destroy(); }
        return ConnectionTask.fromSocket(
          open().timeout(const Duration(seconds: 15), onTimeout: () {
            cancel();
            throw TimeoutException('Proxy connection timed out');
          }), cancel);
      };
    }
    client = IOClient(_http);
  }

  final ProxyConfig? config;
  late final HttpClient _http;
  @override
  late final http.Client client;
  final _sockets = <WebSocketChannel>{};
  bool _closed = false;

  @override
  WebSocketChannel connect(Uri uri, {Iterable<String>? protocols}) {
    if (_closed) throw const SocketException('Closed');
    if ((config?.enabled ?? false) && uri.scheme != 'wss') {
      throw const SocketException('Proxy requires WSS');
    }
    final socket = IOWebSocketChannel.connect(uri,
      protocols: protocols,
      customClient: _http,
      connectTimeout: const Duration(seconds: 15));
    _sockets.add(socket);
    socket.sink.done.then<void>((_) => _sockets.remove(socket),
        onError: (Object _) { _sockets.remove(socket); });
    return socket;
  }

  @override
  void close() {
    _closed = true;
    for (final socket in _sockets.toList()) { socket.sink.close(); }
    _sockets.clear();
    _http.close(force: true);
  }
}
