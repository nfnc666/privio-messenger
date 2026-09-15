import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/proxy_controller.dart';

/// The live connection to the server's delivery socket.
///
/// Replaces polling. Polling means a message waits up to the poll interval and
/// the radio wakes whether or not anything happened; a socket delivers as soon
/// as the envelope exists and is silent otherwise.
///
/// The socket is treated as a delivery pipe, not a source of truth: envelopes
/// are acknowledged only after they have been decrypted and filed, so a drop
/// mid-batch costs a redelivery rather than a lost message. A caller keeps a
/// slow poll as a safety net for the case where the socket is up but wrong.
class RealtimeConnection {
  RealtimeConnection({
    required this.baseUrl,
    required this.token,
    WebSocketChannel Function(Uri)? connect,
  }) : _connect = connect;

  static const String _authProtocolPrefix = 'privio-auth.';

  /// Opens the default socket with the session credential in the WebSocket
  /// subprotocol header rather than in the URL. URLs are commonly retained by
  /// reverse proxies and access logs; a bearer token must never become part of
  /// that logging surface.
  static WebSocketChannel _defaultConnect(Uri uri, String token) {
    final protocols = <String>['privio-v1', '$_authProtocolPrefix$token'];
    return ProxyController.instance.enabled
        ? ProxyController.instance.connect(uri, protocols: protocols)
        : WebSocketChannel.connect(uri, protocols: protocols);
  }

  final Uri baseUrl;
  final String token;

  /// Tests may inject their old URI-only connector. Production uses
  /// [_defaultConnect], which carries authentication separately from the URL.
  final WebSocketChannel Function(Uri)? _connect;

  /// Reconnect delay, doubling up to the cap. A server coming back from a
  /// restart should not be met with every client at once.
  static const Duration minimumBackoff = Duration(seconds: 1);
  static const Duration maximumBackoff = Duration(seconds: 60);

  /// Sent while idle so a dead connection is noticed rather than assumed alive.
  static const Duration heartbeatInterval = Duration(seconds: 45);

  final _envelopes = StreamController<List<dynamic>>.broadcast();
  final _keyRequests = StreamController<void>.broadcast();
  final _connected = ValueNotifier<bool>(false);

  Stream<List<dynamic>> get envelopes => _envelopes.stream;
  Stream<void> get keyRequests => _keyRequests.stream;
  ValueListenable<bool> get connected => _connected;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnect;
  Duration _backoff = minimumBackoff;
  bool _closed = false;

  Uri get _socketUrl {
    final scheme = baseUrl.scheme == 'https' ? 'wss' : 'ws';
    return baseUrl.replace(
      scheme: scheme,
      path: '/v1/ws',
      query: '',
      fragment: '',
    );
  }

  void start() {
    if (_closed) throw StateError('This connection was already closed');
    _open();
  }

  void _open() {
    _reconnect?.cancel();
    try {
      final channel = _connect?.call(_socketUrl) ?? _defaultConnect(_socketUrl, token);
      _channel = channel;
      unawaited(channel.ready.catchError((Object _) {}));
      _subscription = channel.stream.listen(
        _onFrame,
        onError: (Object _) => _dropAndRetry(),
        onDone: _dropAndRetry,
        cancelOnError: true,
      );
      _connected.value = true;
      _backoff = minimumBackoff;
      _heartbeat = Timer.periodic(heartbeatInterval, (_) => _send({'type': 'ping'}));
    } on Object {
      _dropAndRetry();
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return;
    }

    switch (frame['type']) {
      case 'envelopes':
        final batch = frame['envelopes'] as List<dynamic>? ?? const [];
        if (batch.isNotEmpty) _envelopes.add(batch);
      case 'key-request':
        _keyRequests.add(null);
      case 'error':
        if (frame['code'] == 'unauthorized') close();
      default:
        break;
    }
  }

  /// Tells the server the envelopes through [upToId] have been decrypted and
  /// filed, which is what makes it safe to delete them.
  void acknowledge(int upToId) => _send({'type': 'ack', 'upTo': upToId});

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } on Object {
      _dropAndRetry();
    }
  }

  void _dropAndRetry() {
    _teardown();
    if (_closed) return;
    _connected.value = false;
    _reconnect = Timer(_backoff, _open);
    final next = _backoff * 2;
    _backoff = next > maximumBackoff ? maximumBackoff : next;
  }

  void _teardown() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> close() async {
    _closed = true;
    _reconnect?.cancel();
    _teardown();
    _connected.value = false;
    await _envelopes.close();
    await _keyRequests.close();
  }
}
