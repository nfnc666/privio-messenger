import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'proxy_config.dart';
import 'proxy_transport_web.dart'
    if (dart.library.io) 'proxy_transport_io.dart' as platform;

abstract interface class ProxyTransport {
  http.Client get client;
  WebSocketChannel connect(Uri uri, {Iterable<String>? protocols});
  void close();
}

ProxyTransport createProxyTransport(ProxyConfig? config) => platform.create(config);
