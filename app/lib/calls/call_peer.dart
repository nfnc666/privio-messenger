import 'dart:async';

import 'package:flutter/widgets.dart';

import 'call_signal.dart';

/// Where a peer connection is in its life.
enum CallPeerState {
  /// Built, but no media path attempted yet.
  idle,

  /// Gathering candidates and trying paths.
  connecting,

  /// Media is flowing.
  connected,

  /// It came up and went away again. WebRTC may still recover it.
  interrupted,

  /// It will not come up. Nothing further will happen on this connection.
  failed,

  /// Closed by us.
  closed,
}

/// Why a peer connection could not be opened.
enum CallPeerFailure { permissionDenied, noMicrophone, noCamera, unavailable }

class CallPeerException implements Exception {
  const CallPeerException(this.reason, this.message);

  final CallPeerFailure reason;
  final String message;

  @override
  String toString() => 'CallPeerException($reason): $message';
}

/// The media half of a call, as the app needs it.
///
/// An interface for the same reason the microphone and the keystore are
/// interfaces: the call logic — who is ringing, what a late signal means, when
/// a call is over — is the part with the bugs in it, and it should be testable
/// without two real machines and a network between them. What is behind this
/// seam is `flutter_webrtc`, i.e. libwebrtc: the encryption of the media
/// itself is DTLS-SRTP as that library implements it, and nothing here writes
/// a cipher of its own.
abstract interface class CallPeer {
  /// Opens the microphone (and camera, for video) and builds the connection.
  ///
  /// Throws [CallPeerException] when the device says no.
  Future<void> open({required CallMedia media});

  /// The SDP this side offers, as the caller.
  Future<String> createOffer();

  /// Takes the caller's offer and produces the answer to send back.
  Future<String> answerTo(String remoteSdp);

  /// Takes the callee's answer, as the caller.
  Future<void> acceptAnswer(String remoteSdp);

  /// One network path the other side told us about.
  Future<void> addRemoteCandidate(String candidate);

  /// The paths this side found, to be sent to the other one as they appear.
  Stream<String> get localCandidates;

  Stream<CallPeerState> get states;
  CallPeerState get state;

  /// Stops sending our own audio. The other side is not told; it simply hears
  /// nothing, which is what muting means.
  Future<void> setMuted(bool muted);

  /// Sends the camera's picture, or stops.
  Future<void> setCameraOn(bool on);

  /// Routes to the loudspeaker rather than the earpiece.
  Future<void> setSpeakerOn(bool on);

  /// A view of the picture arriving from the other side, or null while there
  /// is none — an audio call, or a video one that has not started flowing yet.
  ///
  /// A widget rather than a stream of frames, because rendering video is the
  /// one part of a call the platform has to do for itself: on the phones it is
  /// a native texture, on the web an element the browser composites. Handing
  /// out frames would mean copying every one of them through Dart for nothing.
  Widget? remoteView();

  /// A view of what this device's camera is sending, for the small window.
  Widget? localView();

  /// Fires when a view appears or goes away, so the screen can rebuild. The
  /// remote picture arrives some time after the connection does.
  Stream<void> get videoChanged;

  /// Releases the microphone, the camera and the connection.
  Future<void> close();
}

/// Builds a peer connection per call.
///
/// A factory rather than one long-lived object: a connection belongs to one
/// call, and reusing one across calls is how state from a finished call leaks
/// into the next.
typedef CallPeerFactory = CallPeer Function();
