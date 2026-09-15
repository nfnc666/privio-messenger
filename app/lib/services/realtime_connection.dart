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
  }) : _connect = connect ?? _defaultConnect;

  /// How the socket is opened when nothing was injected.
  ///
  /// Through the proxy **only when one is switched on**, and through
  /// `WebSocketChannel.connect` otherwise — which is what this did before the
  /// proxy existed, and what it has to go on doing for every install that has
  /// no proxy configured.
  ///
  /// Reaching for `ProxyController.instance` unconditionally meant every
  /// connection went through the proxy transport's own long-lived `HttpClient`,
  /// including on the ordinary path where there is no proxy. That client is
  /// built once, inside a singleton, so in a widget test it captures the
  /// binding's mocked `HttpClient` and then carries it into later tests; the
  /// WebSocket handshake fails, `dart:_http` calls `detachSocket()` on the
  /// mocked response in its *error* path, and the `UnsupportedError` that
  /// throws escapes into the zone rather than arriving on `ready` or on the
  /// stream — which is why `_open`'s guards did not catch it. Forty-eight tests
  /// across the suite went red, every one of them a test that signs in.
  ///
  /// `enabled` is the controller's own fail-closed answer: true when a proxy is
  /// configured *and* true when its settings could not be read, so a device
  /// that is meant to be proxied never quietly falls back to a direct socket.
  static WebSocketChannel _defaultConnect(Uri uri) =>
      ProxyController.instance.enabled
          ? ProxyController.instance.connect(uri)
          : WebSocketChannel.connect(uri);

  final Uri baseUrl;
  final String token;
  final WebSocketChannel Function(Uri) _connect;

  /// Reconnect delay, doubling up to the cap. A server coming back from a
  /// restart should not be met with every client at once.
  static const Duration minimumBackoff = Duration(seconds: 1);
  static const Duration maximumBackoff = Duration(seconds: 60);

  /// Sent while idle so a dead connection is noticed rather than assumed alive.
  static const Duration heartbeatInterval = Duration(seconds: 45);

  final _envelopes = StreamController<List<dynamic>>.broadcast();
  final _keyRequests = StreamController<void>.broadcast();
  final _connected = ValueNotifier<bool>(false);

  /// Batches of envelopes as the server pushes them, still encrypted.
  Stream<List<dynamic>> get envelopes => _envelopes.stream;

  /// "Somebody in a group or channel you are in is waiting for its key."
  ///
  /// Carries nothing: what to do about it is entirely this device's business,
  /// and the server could not say more if it wanted to — it has never had a
  /// key to talk about.
  Stream<void> get keyRequests => _keyRequests.stream;

  /// Whether the socket is currently up, for a connection indicator.
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
      // The token goes in the query because browsers cannot set headers on a
      // WebSocket handshake. It is inside TLS, and the server accepts a header
      // too for the platforms that can send one.
      queryParameters: {'token': token},
    );
  }

  void start() {
    if (_closed) throw StateError('This connection was already closed');
    _open();
  }

  void _open() {
    _reconnect?.cancel();
    try {
      final channel = _connect(_socketUrl);
      _channel = channel;
      // A handshake that fails — no signal, a captive portal, a proxy that
      // refuses — reports it on `ready`, not on the stream. The retry is driven
      // by the stream's onError below, but an error nobody looks at on that
      // future is an unhandled exception in the zone: on a phone with no
      // reception, one per attempt.
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
      return; // A frame we cannot parse is not a reason to drop the connection.
    }

    switch (frame['type']) {
      case 'envelopes':
        final batch = frame['envelopes'] as List<dynamic>? ?? const [];
        if (batch.isNotEmpty) _envelopes.add(batch);
      case 'key-request':
        _keyRequests.add(null);
      case 'error':
        // The server refuses the token: reconnecting with it will not help.
        if (frame['code'] == 'unauthorized') close();
      default:
        break; // pong, and anything added later.
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
