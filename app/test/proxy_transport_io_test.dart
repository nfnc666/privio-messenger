import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/network/proxy_config.dart';
import 'package:privio/network/proxy_transport_io.dart' as native;

class Reader {
  Reader(Socket socket) : input = StreamIterator<Uint8List>(socket);
  final StreamIterator<Uint8List> input;
  final bytes = <int>[];
  Future<List<int>> take(int count) async {
    while (bytes.length < count) {
      if (!await input.moveNext()) throw StateError('Unexpected end');
      bytes.addAll(input.current);
    }
    final value = bytes.sublist(0, count);
    bytes.removeRange(0, count);
    return value;
  }
}

void main() {
  test('SOCKS5 receives destination domain; rejection never falls back', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<String>();
    Socket? accepted;
    final subscription = server.listen((socket) async {
      accepted = socket;
      try {
        final reader = Reader(socket);
        final greeting = await reader.take(2);
        expect(greeting.first, 5);
        await reader.take(greeting[1]);
        socket.add([5, 0]); await socket.flush();
        final command = await reader.take(4);
        expect(command, [5, 1, 0, 3]);
        final length = (await reader.take(1)).single;
        final domain = utf8.decode(await reader.take(length));
        expect(await reader.take(2), [1, 187]); // HTTPS port 443.
        received.complete(domain);
        socket.add([5, 5, 0, 1, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        socket.destroy();
      } catch (error, stack) {
        if (!received.isCompleted) received.completeError(error, stack);
        socket.destroy();
      }
    });
    final transport = native.create(ProxyConfig(host: '127.0.0.1', port: server.port,
      enabled: true));
    try {
      final request = transport.client.get(Uri.parse('https://never-resolve.invalid'));
      await expectLater(request, throwsA(anything));
      expect(await received.future.timeout(const Duration(seconds: 5)), 'never-resolve.invalid');
    } finally {
      transport.close(); accepted?.destroy(); await subscription.cancel(); await server.close();
    }
  });

  test('proxy mode refuses plaintext HTTP and WebSockets', () async {
    final transport = native.create(const ProxyConfig(host: '127.0.0.1', port: 1, enabled: true));
    try {
      await expectLater(transport.client.get(Uri.parse('http://never-resolve.invalid')),
        throwsA(anything));
      expect(() => transport.connect(Uri.parse('ws://never-resolve.invalid')), throwsA(anything));
    } finally { transport.close(); }
  });
}
