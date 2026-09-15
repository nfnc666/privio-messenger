import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'proxy_config.dart';
import 'proxy_transport.dart';

ProxyTransport create(ProxyConfig? config) {
  if (config?.enabled ?? false) throw UnsupportedError('Browser proxy settings');
  return _BrowserTransport();
}

class _BrowserTransport implements ProxyTransport {
  @override
  final http.Client client = http.Client();
  final _sockets = <WebSocketChannel>{};

  @override
  WebSocketChannel connect(Uri uri) {
    final socket = WebSocketChannel.connect(uri);
    _sockets.add(socket);
    socket.sink.done.then<void>((_) => _sockets.remove(socket),
        onError: (Object _) { _sockets.remove(socket); });
    return socket;
  }

  @override
  void close() {
    client.close();
    for (final socket in _sockets.toList()) { socket.sink.close(); }
    _sockets.clear();
  }
}
