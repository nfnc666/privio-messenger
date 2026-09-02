import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:privio/calls/call_peer.dart';
import 'package:privio/calls/call_signal.dart';

/// A peer connection with no media in it.
///
/// It follows the same order the real one does — an offer produces an answer,
/// an answer is accepted, candidates arrive and are handed over — so the call
/// logic can be driven through every path, including the ones that are hard to
/// arrange with two real machines: a candidate that arrives before the callee
/// picked up, a connection that fails, a microphone that is refused.
class FakeCallPeer implements CallPeer {
  FakeCallPeer({this.failsWith});

  /// When set, [open] throws it: a refused microphone, or no camera.
  final CallPeerException? failsWith;

  final _candidates = StreamController<String>.broadcast();
  final _states = StreamController<CallPeerState>.broadcast();

  CallPeerState _state = CallPeerState.idle;
  bool opened = false;
  bool closed = false;
  bool muted = false;
  bool cameraOn = false;
  bool speakerOn = false;
  CallMedia? media;
  String? remoteOffer;
  String? remoteAnswer;
  final List<String> remoteCandidates = [];

  @override
  Future<void> open({required CallMedia media}) async {
    if (failsWith != null) throw failsWith!;
    this.media = media;
    opened = true;
    cameraOn = media.isVideo;
    _push(CallPeerState.connecting);
  }

  @override
  Future<String> createOffer() async => 'sdp-offer';

  @override
  Future<String> answerTo(String remoteSdp) async {
    remoteOffer = remoteSdp;
    return 'sdp-answer';
  }

  @override
  Future<void> acceptAnswer(String remoteSdp) async => remoteAnswer = remoteSdp;

  @override
  Future<void> addRemoteCandidate(String candidate) async => remoteCandidates.add(candidate);

  @override
  Stream<String> get localCandidates => _candidates.stream;

  @override
  Stream<CallPeerState> get states => _states.stream;

  @override
  CallPeerState get state => _state;

  @override
  Future<void> setMuted(bool muted) async => this.muted = muted;

  @override
  Future<void> setCameraOn(bool on) async => cameraOn = on;

  @override
  Future<void> setSpeakerOn(bool on) async => speakerOn = on;

  @override
  Widget? remoteView() => remotePicture ? const SizedBox.shrink(key: Key('remote')) : null;

  @override
  Widget? localView() => cameraOn ? const SizedBox.shrink(key: Key('local')) : null;

  @override
  Stream<void> get videoChanged => _video.stream;

  final _video = StreamController<void>.broadcast();

  /// Whether a picture has arrived from the other side.
  bool remotePicture = false;

  /// Pretends the other side's camera came through.
  void showRemotePicture() {
    remotePicture = true;
    if (!_video.isClosed) _video.add(null);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _video.close();
    _push(CallPeerState.closed);
    await _candidates.close();
    await _states.close();
  }

  /// Pretends the network found a path.
  void connect() => _push(CallPeerState.connected);

  /// Pretends it did not.
  void fail() => _push(CallPeerState.failed);

  /// Pretends this side found a route the other one should try.
  void offerCandidate(String candidate) {
    if (!_candidates.isClosed) _candidates.add(candidate);
  }

  void _push(CallPeerState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
