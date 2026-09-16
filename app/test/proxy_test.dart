import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/network/proxy_config.dart';
import 'package:privio/network/proxy_controller.dart';
import 'package:privio/network/proxy_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeTransport implements ProxyTransport {
  FakeTransport(this.config);
  final ProxyConfig? config;
  bool closed = false;
  final requests = <http.Request>[];
  @override
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return http.Response('{}', 200);
  });
  @override
  WebSocketChannel connect(Uri uri, {Iterable<String>? protocols}) => throw UnimplementedError();
  @override
  void close() { closed = true; client.close(); }
}

void main() {
  const config = ProxyConfig(host: 'proxy.example', port: 1080,
    username: 'test-user', password: 'test-password', enabled: true);

  test('configuration round trips without printing credentials', () {
    final restored = ProxyConfig.fromJson(config.toJson());
    expect(restored.toJson(), config.toJson());
    expect('$restored', isNot(contains(config.password)));
    expect('$restored', isNot(contains(config.username)));
  });

  test('rejects invalid ports, injected URLs and partial authentication', () {
    for (final host in ['', 'http://proxy.example', 'host/path', 'host; DIRECT',
      'host\nother', 'user@host', 'proxy.example:1080']) {
      expect(() => ProxyConfig(host: host, port: 1080).validate(), throwsFormatException);
    }
    for (final port in [0, -1, 65536]) {
      expect(() => ProxyConfig(host: 'localhost', port: port).validate(), throwsFormatException);
    }
    expect(() => const ProxyConfig(host: 'localhost', port: 1080,
      password: 'password').validate(), throwsFormatException);
    expect(() => ProxyConfig(host: 'localhost', port: 1080,
      username: 'é' * 128, password: 'password').validate(), throwsFormatException);
    const ProxyConfig(host: '::1', port: 1080).validate();
  });

  test('startup restores policy before the first request', () async {
    final transports = <FakeTransport>[];
    final controller = ProxyController(read: () async => jsonEncode(config.toJson()),
      write: (_) async {}, factory: (value) {
        final transport = FakeTransport(value); transports.add(transport); return transport;
      });
    await controller.load();
    await controller.newClient().get(Uri.parse('https://privio.invalid'));
    expect(controller.enabled, isTrue);
    expect(transports.single.config!.host, config.host);
    expect(transports.single.requests, hasLength(1));
  });

  test('unreadable storage blocks traffic until explicitly repaired', () async {
    final controller = ProxyController(read: () async => '{broken',
      write: (_) async {}, factory: FakeTransport.new);
    await controller.load();
    expect(controller.enabled, isTrue);
    expect(() => controller.transport, throwsStateError);
    await controller.save(null);
    expect(controller.enabled, isFalse);
    expect(controller.transport, isA<FakeTransport>());
  });

  test('failed persistence does not change the effective policy', () async {
    final controller = ProxyController(read: () async => jsonEncode(config.toJson()),
      write: (_) async => throw StateError('storage unavailable'), factory: FakeTransport.new);
    await controller.load();
    final original = controller.transport as FakeTransport;
    await expectLater(controller.save(null), throwsStateError);
    expect(controller.enabled, isTrue);
    expect(controller.transport, same(original));
    expect(original.closed, isFalse);
  });

  test('existing API clients use the new policy; old connections close', () async {
    String? stored;
    final controller = ProxyController(read: () async => stored,
      write: (value) async { stored = value; }, factory: FakeTransport.new);
    final client = controller.newClient();
    await client.get(Uri.parse('https://privio.invalid'));
    final original = controller.transport as FakeTransport;
    await controller.save(config);
    expect(original.closed, isTrue);
    await client.get(Uri.parse('https://privio.invalid'));
    final active = controller.transport as FakeTransport;
    expect(active.config, same(config));
    expect(active.requests, hasLength(1));
    expect(jsonDecode(stored!)['enabled'], isTrue);
    await controller.save(null);
    expect(stored, isNull);
    expect(active.closed, isTrue);
  });

  test('connection test uses temporary policy and sends no account token', () async {
    final created = <FakeTransport>[];
    final controller = ProxyController(write: (_) async => fail('Must not save'),
      factory: (value) {
        final transport = FakeTransport(value); created.add(transport); return transport;
      });
    await controller.test(config, Uri.parse('https://privio.invalid'));
    final tested = created.single;
    expect(tested.config!.enabled, isTrue);
    expect(tested.requests.single.url.path, '/v1/server');
    expect(tested.requests.single.headers, isNot(contains('authorization')));
    expect(tested.requests.single.followRedirects, isFalse);
    expect(tested.closed, isTrue);
    expect(controller.config, isNull);
  });
}
