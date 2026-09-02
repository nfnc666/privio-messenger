import 'call_signal.dart';

/// Who started it.
enum CallDirection { outgoing, incoming }

/// Where a call is, from this device's point of view.
enum CallState {
  /// Outgoing: the offer is sent, nobody has picked up.
  dialling,

  /// Incoming: this device is ringing.
  ringing,

  /// Someone picked up; the media path is still being negotiated.
  connecting,

  /// Media is flowing.
  connected,

  /// Over, for whatever reason.
  ended,
}

/// The other person, as far as a call needs to know them.
class CallParty {
  const CallParty({required this.accountId, required this.username});

  final String accountId;

  /// What to send to, and what to show. One field because Privio has one name
  /// per account and no separate display name to get out of step with it.
  final String username;

  @override
  bool operator ==(Object other) =>
      other is CallParty && other.accountId == accountId && other.username == username;

  @override
  int get hashCode => Object.hash(accountId, username);
}

/// A call in progress, or one just finished.
class ActiveCall {
  ActiveCall({
    required this.id,
    required this.party,
    required this.direction,
    required this.media,
    required this.state,
    required this.startedAt,
    this.connectedAt,
    this.ending,
    this.muted = false,
    this.cameraOn = false,
    this.speakerOn = false,
  });

  /// The caller's id for the call. Both sides use it, which is what lets a
  /// signal be matched to the call it belongs to rather than to whatever is
  /// current.
  final String id;
  final CallParty party;
  final CallDirection direction;
  final CallMedia media;

  CallState state;

  /// When it began — the offer, not the pick-up.
  final DateTime startedAt;

  /// When media started flowing, if it ever did.
  DateTime? connectedAt;

  CallEnding? ending;
  bool muted;
  bool cameraOn;
  bool speakerOn;

  bool get isVideo => media.isVideo;
  bool get isIncoming => direction == CallDirection.incoming;

  /// True while this call is worth showing a screen for.
  bool get isLive => state != CallState.ended;

  /// How long the two were actually connected. Null until they were.
  Duration? durationAt(DateTime now) => connectedAt == null ? null : now.difference(connectedAt!);
}

/// One line in the call history.
///
/// Written when a call ends and never before: an entry for a call that has not
/// happened is the same lie as a chat bubble for a message that was not sent.
class CallRecord {
  const CallRecord({
    required this.id,
    required this.accountId,
    required this.username,
    required this.direction,
    required this.media,
    required this.at,
    required this.duration,
    required this.ending,
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
        id: json['id'] as String? ?? '',
        accountId: json['a'] as String? ?? '',
        username: json['u'] as String? ?? 'unknown',
        direction: json['d'] == 'in' ? CallDirection.incoming : CallDirection.outgoing,
        media: CallMedia.parse(json['m'] as String?),
        at: DateTime.fromMillisecondsSinceEpoch(json['t'] as int? ?? 0),
        duration: Duration(seconds: json['s'] as int? ?? 0),
        ending: CallEnding.parse(json['e'] as String?) ?? CallEnding.hungUp,
      );

  final String id;
  final String accountId;
  final String username;
  final CallDirection direction;
  final CallMedia media;
  final DateTime at;

  /// Zero for a call that never connected.
  final Duration duration;
  final CallEnding ending;

  /// True when the two were actually connected at some point.
  bool get wasAnswered => duration > Duration.zero;

  /// True for an incoming call that was never picked up — the one kind of
  /// history entry that deserves to be red.
  bool get wasMissed =>
      direction == CallDirection.incoming && !wasAnswered && ending != CallEnding.declined;

  Map<String, dynamic> toJson() => {
        'id': id,
        'a': accountId,
        'u': username,
        'd': direction == CallDirection.incoming ? 'in' : 'out',
        'm': media.wireName,
        't': at.millisecondsSinceEpoch,
        's': duration.inSeconds,
        'e': ending.name,
      };
}
