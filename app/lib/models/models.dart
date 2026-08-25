import 'package:flutter/foundation.dart';

/// Presence as the UI understands it. The server only ever reports a last-seen
/// timestamp, and only when the other person's privacy setting allows it.
enum Presence { online, recently, hidden }

@immutable
class Contact {
  const Contact({
    required this.id,
    required this.username,
    required this.displayName,
    this.presence = Presence.hidden,
    this.avatarSeed = 0,
  });

  final String id;
  final String username;
  final String displayName;
  final Presence presence;
  final int avatarSeed;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1();
    return '${parts.first.characters1()}${parts.last.characters1()}';
  }
}

extension on String {
  String characters1() => isEmpty ? '' : substring(0, 1).toUpperCase();
}

enum MessageKind { text, voice, photo, video, file }

/// Delivery state of an outgoing message, mirrored in the tick marks.
enum DeliveryState { sending, sent, delivered, read }

@immutable
class Message {
  const Message({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.kind = MessageKind.text,
    this.state = DeliveryState.read,
    this.voiceDuration,
    this.senderName,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final bool isMine;
  final MessageKind kind;
  final DeliveryState state;
  final Duration? voiceDuration;

  /// Only set in groups, where the sender has to be labelled.
  final String? senderName;
}

@immutable
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.timestamp,
    this.unreadCount = 0,
    this.isGroup = false,
    this.pinned = false,
    this.previewKind = MessageKind.text,
    this.presence = Presence.hidden,
    this.avatarSeed = 0,
  });

  final String id;
  final String title;
  final String preview;

  /// Pre-formatted for the list, exactly as the mockups show it ("11:32",
  /// "Yesterday"). Formatting belongs to the data layer so the row stays dumb.
  final String timestamp;
  final int unreadCount;
  final bool isGroup;
  final bool pinned;
  final MessageKind previewKind;
  final Presence presence;
  final int avatarSeed;
}

enum CallDirection { incoming, outgoing, missed }

@immutable
class CallEntry {
  const CallEntry({
    required this.id,
    required this.contactName,
    required this.direction,
    required this.timestamp,
    this.isVideo = false,
    this.avatarSeed = 0,
  });

  final String id;
  final String contactName;
  final CallDirection direction;
  final String timestamp;
  final bool isVideo;
  final int avatarSeed;
}

@immutable
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActive,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final String platform;
  final String lastActive;
  final bool isCurrent;
}
