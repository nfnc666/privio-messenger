import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'call_peer.dart';
import 'call_signal.dart';

/// The media half of a call, on libwebrtc.
///
/// Everything cryptographic here belongs to that library: the media is
/// encrypted with DTLS-SRTP, whose keys are agreed in the DTLS handshake
/// between the two devices. Privio writes none of it. What Privio does is
/// carry the handshake's own setup — the SDP and the candidates — inside the
/// Signal session the two already have, so the addresses in them are not
/// readable by the server that relays them.
class WebRtcCallPeer implements CallPeer {
  /// [iceServers] comes from the server, already shaped for WebRTC. The
  /// build-time list is a fallback for a deployment that offers none.
  WebRtcCallPeer({List<Map<String, dynamic>>? iceServers})
      : _iceServers = (iceServers == null || iceServers.isEmpty)
            ? [
                for (final url in configuredIceServers) {'urls': url},
              ]
            : iceServers;

  /// Where to ask "what is my public address".
  ///
  /// A STUN server relays no media and sees no call content; it answers one
  /// question and hangs up. It is still a third party that learns an IP, so
  /// there is exactly one, it is a build-time setting, and pointing it at your
  /// own is one flag:
  /// `flutter build apk --dart-define=PRIVIO_ICE_SERVERS=stun:stun.example.org:3478`
  ///
  /// Empty is a real answer, and the honest default while Privio runs no STUN
  /// server of its own: the two devices then try only the addresses they can
  /// see for themselves, which works on the same network and behind simple
  /// NATs and fails behind strict ones. A hostname that does not resolve would
  /// fail the same way while looking as though something were configured.
  static const String _configured = String.fromEnvironment('PRIVIO_ICE_SERVERS');

  static List<String> get configuredIceServers => [
        for (final url in _configured.split(','))
          if (url.trim().isNotEmpty) url.trim(),
      ];

  final List<Map<String, dynamic>> _iceServers;

  final _candidates = StreamController<String>.broadcast();
  final _states = StreamController<CallPeerState>.broadcast();

  rtc.RTCPeerConnection? _connection;
  rtc.MediaStream? _local;
  rtc.MediaStream? _remote;
  CallPeerState _state = CallPeerState.idle;

  /// Renderers, built only for a video call and disposed with the connection.
  ///
  /// They belong to the peer rather than to the screen: a renderer outliving
  /// its stream is a black rectangle, and one built per rebuild is a leak of
  /// native textures.
  rtc.RTCVideoRenderer? _localRenderer;
  rtc.RTCVideoRenderer? _remoteRenderer;
  final _videoChanged = StreamController<void>.broadcast();

  @override
  Future<void> open({required CallMedia media}) async {
    try {
      _local = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': media.isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
    } on Object catch (error) {
      throw CallPeerException(
        _failureFrom(error, media),
        media.isVideo
            ? 'Privio could not open the camera or microphone.'
            : 'Privio could not open the microphone.',
      );
    }

    final connection = await rtc.createPeerConnection({
      'iceServers': _iceServers,
      // Trickle ICE: candidates go out as they are found rather than all at
      // once at the end, which is what keeps the wait before a call connects
      // to about a second.
      'sdpSemantics': 'unified-plan',
    });
    _connection = connection;

    for (final track in _local!.getTracks()) {
      await connection.addTrack(track, _local!);
    }

    if (media.isVideo) {
      final local = rtc.RTCVideoRenderer();
      await local.initialize();
      local.srcObject = _local;
      _localRenderer = local;
      _videoChanged.add(null);
    }

    connection.onIceCandidate = (candidate) {
      // An empty candidate is the end-of-gathering marker, not a path.
      if (candidate.candidate == null) return;
      if (_candidates.isClosed) return;
      _candidates.add(
        jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };
    connection.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remote = event.streams.first;
      // A video track can arrive after the connection is up, so the renderer
      // is built when the picture turns up rather than when the call starts.
      if (event.track.kind == 'video') unawaited(_showRemote());
    };
    connection.onConnectionState = (state) => _push(_translate(state));

    _push(CallPeerState.connecting);
  }

  @override
  Future<String> createOffer() async {
    final connection = _require();
    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> answerTo(String remoteSdp) async {
    final connection = _require();
    await connection.setRemoteDescription(rtc.RTCSessionDescription(remoteSdp, 'offer'));
    final answer = await connection.createAnswer();
    await connection.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> acceptAnswer(String remoteSdp) async {
    await _require().setRemoteDescription(rtc.RTCSessionDescription(remoteSdp, 'answer'));
  }

  @override
  Future<void> addRemoteCandidate(String candidate) async {
    final decoded = jsonDecode(candidate) as Map<String, dynamic>;
    await _require().addCandidate(
      rtc.RTCIceCandidate(
        decoded['candidate'] as String?,
        decoded['sdpMid'] as String?,
        decoded['sdpMLineIndex'] as int?,
      ),
    );
  }

  @override
  Stream<String> get localCandidates => _candidates.stream;

  @override
  Stream<CallPeerState> get states => _states.stream;

  @override
  CallPeerState get state => _state;

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setCameraOn(bool on) async {
    for (final track in _local?.getVideoTracks() ?? const <rtc.MediaStreamTrack>[]) {
      track.enabled = on;
    }
  }

  @override
  Future<void> setSpeakerOn(bool on) async {
    // Android and iOS route audio here; on the web the browser owns output
    // routing and there is nothing to set, which the plugin signals by
    // returning nothing at all.
    for (final track in _local?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[]) {
      track.enableSpeakerphone(on);
    }
  }

  @override
  Widget? remoteView() {
    final renderer = _remoteRenderer;
    return renderer == null ? null : rtc.RTCVideoView(renderer, objectFit: _cover);
  }

  @override
  Widget? localView() {
    final renderer = _localRenderer;
    return renderer == null
        ? null
        // Mirrored, because a self-view that is not mirrored looks wrong to
        // the person in it — every video app does this.
        : rtc.RTCVideoView(renderer, objectFit: _cover, mirror: true);
  }

  @override
  Stream<void> get videoChanged => _videoChanged.stream;

  Future<void> _showRemote() async {
    if (_remoteRenderer != null) {
      _remoteRenderer!.srcObject = _remote;
      return;
    }
    final renderer = rtc.RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = _remote;
    _remoteRenderer = renderer;
    if (!_videoChanged.isClosed) _videoChanged.add(null);
  }

  static const rtc.RTCVideoViewObjectFit _cover =
      rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;

  @override
  Future<void> close() async {
    // Order matters: stopping the tracks is what turns the camera light off,
    // and it has to happen even if closing the connection throws.
    for (final track in _local?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
      await track.stop();
    }
    // Renderers first, so nothing is still pointing at a stream being disposed.
    await _localRenderer?.dispose();
    await _remoteRenderer?.dispose();
    _localRenderer = null;
    _remoteRenderer = null;
    await _local?.dispose();
    _local = null;
    _remote = null;
    await _connection?.close();
    _connection = null;
    _push(CallPeerState.closed);
    await _candidates.close();
    await _states.close();
    await _videoChanged.close();
  }

  rtc.RTCPeerConnection _require() {
    final connection = _connection;
    if (connection == null) {
      throw const CallPeerException(
        CallPeerFailure.unavailable,
        'The call was not open.',
      );
    }
    return connection;
  }

  void _push(CallPeerState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  static CallPeerState _translate(rtc.RTCPeerConnectionState state) => switch (state) {
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected => CallPeerState.connected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => CallPeerState.interrupted,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed => CallPeerState.failed,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed => CallPeerState.closed,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting => CallPeerState.connecting,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateNew => CallPeerState.idle,
      };

  /// Tells a refusal apart from a missing device, because the two need
  /// different sentences: one is fixed in settings, the other is not fixable.
  static CallPeerFailure _failureFrom(Object error, CallMedia media) {
    final text = error.toString().toLowerCase();
    if (text.contains('notallowed') || text.contains('permission') || text.contains('denied')) {
      return CallPeerFailure.permissionDenied;
    }
    if (text.contains('notfound') || text.contains('devicesnotfound')) {
      return media.isVideo ? CallPeerFailure.noCamera : CallPeerFailure.noMicrophone;
    }
    return CallPeerFailure.unavailable;
  }
}
