import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'proxy_config.dart';
import 'proxy_transport.dart';

/// One network policy per installation, also available before login.
class ProxyController extends ChangeNotifier {
  ProxyController({Future<String?> Function()? read,
    Future<void> Function(String?)? write,
    ProxyTransport Function(ProxyConfig?)? factory})
      : _read = read ?? _readStored, _write = write ?? _writeStored,
        _factory = factory ?? createProxyTransport;

  static final instance = ProxyController();
  static const supported = !kIsWeb;
  static const storageKey = 'privio.network.proxy';
  static const _storage = FlutterSecureStorage();
  static const _ios = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);
  static const _android = AndroidOptions();
  static Future<String?> _readStored() => _storage.read(key: storageKey,
    iOptions: _ios, aOptions: _android);
  static Future<void> _writeStored(String? value) => value == null
    ? _storage.delete(key: storageKey, iOptions: _ios, aOptions: _android)
    : _storage.write(key: storageKey, value: value, iOptions: _ios, aOptions: _android);

  final Future<String?> Function() _read;
  final Future<void> Function(String?) _write;
  final ProxyTransport Function(ProxyConfig?) _factory;
  ProxyTransport? _transport;
  ProxyConfig? _config;
  bool _busy = false;
  bool _loadFailed = false;
  ProxyConfig? get config => _config;
  bool get enabled => _loadFailed || (_config?.enabled ?? false);
  bool get blocksCalls => enabled || _busy;
  ProxyTransport get transport {
    if (_loadFailed) throw StateError('Review proxy settings before connecting');
    return _transport ??= _factory(_config);
  }

  Future<void> load() async {
    if (!supported) return;
    try {
    final raw = await _read();
    if (raw == null) return;
    // Corrupt/unreadable credentials must never silently select a direct path.
    final config = ProxyConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final next = _factory(config);
    final previous = _transport;
    _config = config;
    _transport = next;
    previous?.close();
    _loadFailed = false;
    } on Object {
      _transport?.close();
      _transport = null;
      _loadFailed = true;
    }
  }

  Future<void> save(ProxyConfig? config) async {
    if (_busy) throw StateError('Network settings are being saved');
    if (!supported) throw UnsupportedError('Browser proxy settings');
    config?.validate();
    _busy = true;
    ProxyTransport? next;
    try {
      next = _factory(config);
      await _write(config == null ? null : jsonEncode(config.toJson()));
      final previous = _transport;
      _config = config;
      _loadFailed = false;
      _transport = next;
      next = null;
      previous?.close();
      notifyListeners();
    } finally {
      next?.close();
      _busy = false;
    }
  }

  /// Logout clears account secrets, but must not change device routing.
  Future<void> persistAfterLogout() async {
    if (_config != null) await _write(jsonEncode(_config!.toJson()));
  }

  WebSocketChannel connect(Uri uri) => transport.connect(uri);
  http.Client newClient() => _PolicyClient(this);

  /// Checks the actual Privio endpoint, without authentication or redirects.
  Future<void> test(ProxyConfig config, Uri baseUrl) async {
    config.validate();
    if (!config.enabled) throw StateError('Enable proxy for the test');
    final temporary = _factory(config);
    try {
      final request = http.Request('GET', baseUrl.replace(path: '/v1/server',
        query: '', fragment: ''))..followRedirects = false;
      final response = await temporary.client.send(request).timeout(const Duration(seconds: 20));
      await response.stream.drain<void>().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw StateError('Endpoint unreachable');
    } finally { temporary.close(); }
  }
}

class _PolicyClient extends http.BaseClient {
  _PolicyClient(this.owner);
  final ProxyController owner;
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) throw http.ClientException('Client is closed');
    return owner.transport.client.send(request);
  }
  @override
  void close() { _closed = true; }
}
