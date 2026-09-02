import 'dart:convert';

/// What one call signal is asking the other side to do.
///
/// Signalling is the part of a call that decides *how* the two devices will
/// reach each other, and it is the part that leaks if it is done in the open:
/// an SDP offer lists the caller's local and public addresses. So these travel
/// as ordinary sealed payloads over the Signal session the two already have —
/// the server relays them exactly as it relays a sentence, and can read
/// neither.
enum CallAction {
  /// "I would like to call you", carrying the caller's SDP offer.
  offer,

  /// "I picked up", carrying the callee's SDP answer.
  answer,

  /// One network path the sender can be reached on. Several per call.
  ice,

  /// "I am not taking this call."
  decline,

  /// "I am on another call."
  busy,

  /// "This call is over" — from either side, at any point.
  hangUp;

  static CallAction? parse(String? raw) {
    for (final action in CallAction.values) {
      if (action.wireName == raw) return action;
    }
    return null;
  }

  /// Short, stable names. The enum may be reordered; the wire may not.
  String get wireName => switch (this) {
        CallAction.offer => 'offer',
        CallAction.answer => 'answer',
        CallAction.ice => 'ice',
        CallAction.decline => 'decline',
        CallAction.busy => 'busy',
        CallAction.hangUp => 'bye',
      };
}

/// Voice, or voice and picture.
enum CallMedia {
  audio,
  video;

  static CallMedia parse(String? raw) => raw == 'video' ? CallMedia.video : CallMedia.audio;

  String get wireName => this == CallMedia.video ? 'video' : 'audio';

  bool get isVideo => this == CallMedia.video;
}

/// Why a call ended, as the other side described it.
enum CallEnding {
  /// Someone hung up.
  hungUp,

  /// The callee refused it.
  declined,

  /// The callee was already on a call.
  busy,

  /// Nobody picked up in time.
  unanswered,

  /// The media path never came up, or dropped.
  failed;

  static CallEnding? parse(String? raw) {
    for (final ending in CallEnding.values) {
      if (ending.name == raw) return ending;
    }
    return null;
  }
}

/// One message in the negotiation of a call.
///
/// Deliberately one value type rather than five fields on [MessagePayload]:
/// the payload union already carries twenty, and a call signal is a thing in
/// its own right — it is encoded, sent, received and matched to a call as a
/// unit.
class CallSignal {
  const CallSignal({
    required this.callId,
    required this.action,
    this.media = CallMedia.audio,
    this.sdp,
    this.candidate,
    this.ending,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) => CallSignal(
        callId: json['id'] as String? ?? '',
        action: CallAction.parse(json['a'] as String?) ?? CallAction.hangUp,
        media: CallMedia.parse(json['m'] as String?),
        sdp: json['s'] as String?,
        candidate: json['c'] as String?,
        ending: CallEnding.parse(json['e'] as String?),
      );

  /// The caller's id for this call. Every signal about the same call carries
  /// it, which is what lets a device tell a late `hangUp` for a call it already
  /// forgot from one for the call it is on.
  final String callId;

  final CallAction action;
  final CallMedia media;

  /// The session description, on an offer or an answer.
  final String? sdp;

  /// One ICE candidate, JSON-encoded as the WebRTC stack produced it.
  final String? candidate;

  /// Why it ended, on a signal that ends it.
  final CallEnding? ending;

  Map<String, dynamic> toJson() => {
        'id': callId,
        'a': action.wireName,
        if (action == CallAction.offer) 'm': media.wireName,
        if (sdp != null) 's': sdp,
        if (candidate != null) 'c': candidate,
        if (ending != null) 'e': ending!.name,
      };

  String encode() => jsonEncode(toJson());

  /// True for the signals that end a call rather than advance one.
  bool get isFinal =>
      action == CallAction.hangUp || action == CallAction.decline || action == CallAction.busy;

  @override
  String toString() => 'CallSignal(${action.wireName}, $callId)';
}
