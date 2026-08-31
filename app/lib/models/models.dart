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
    this.avatarBytes,
  });

  final String id;
  final String username;
  final String displayName;
  final Presence presence;
  final int avatarSeed;

  /// Set once the picture has been downloaded and decrypted on this device.
  final Uint8List? avatarBytes;

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

/// An attachment a message points at.
///
/// The id addresses ciphertext on the server; the key opens it and exists only
/// here and inside the sealed message that delivered it. The file name is the
/// sender's, and it never travelled outside the encrypted envelope.
@immutable
class Attachment {
  const Attachment({
    required this.mediaId,
    required this.mediaKey,
    required this.mediaType,
    required this.byteSize,
    this.fileName,
  });

  final String mediaId;
  final String mediaKey;
  final String mediaType;
  final int byteSize;
  final String? fileName;

  bool get isImage => mediaType.startsWith('image/');
  bool get isVideo => mediaType.startsWith('video/');

  /// A readable size for the file row.
  String get readableSize {
    if (byteSize < 1024) return '$byteSize B';
    if (byteSize < 1024 * 1024) return '${(byteSize / 1024).toStringAsFixed(0)} KB';
    return '${(byteSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Delivery state of an outgoing message, mirrored in the tick marks.
///
/// [failed] is its own state rather than an absence: a message that did not go
/// out must say so and offer a retry, not sit looking like it is still trying.
/// [queued] is the offline case — nothing is wrong, there is simply no network.
enum DeliveryState { queued, sending, sent, delivered, read, failed }

@immutable
class Message {
  const Message({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.kind = MessageKind.text,
    // Not `read`: the default used to claim every message had been read by the
    // other side, including ones that had only just been typed. A message knows
    // it was sent; anything beyond that has to be told to it.
    this.state = DeliveryState.sent,
    this.voiceDuration,
    this.waveform,
    this.senderName,
    this.attachment,
    this.expiresAt,
    this.clientId,
    this.replyToId,
    this.replyPreview,
    this.replySender,
    this.reactions = const {},
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final bool isMine;
  final MessageKind kind;
  final DeliveryState state;
  final Duration? voiceDuration;

  /// The bars the sender's recorder measured, 0..1. Drawn as the waveform, and
  /// available before the audio itself has been downloaded.
  final List<double>? waveform;

  /// Only set in groups, where the sender has to be labelled.
  final String? senderName;

  /// Set when this message carries a file rather than only text.
  final Attachment? attachment;

  /// When this message disappears, if the chat has a timer running.
  ///
  /// Both sides compute it from the same number carried inside the sealed
  /// payload, so neither has to trust the server's clock or its goodwill.
  final DateTime? expiresAt;

  /// The sender's own id, which survives a retry. Used to recognise the same
  /// message arriving twice.
  final String? clientId;

  /// Set when this message replies to another. The quote travelled with it, so
  /// it renders even if the original is gone from this device.
  final String? replyToId;
  final String? replyPreview;
  final String? replySender;

  /// Who reacted with what: account id to emoji, one each.
  ///
  /// One per person rather than a list, because a reaction is a position and
  /// somebody changing theirs should replace it, not add to it.
  final Map<String, String> reactions;

  bool get isReply => replyToId != null;

  bool get isVoice => kind == MessageKind.voice;

  bool hasExpiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  Message copyWith({
    DeliveryState? state,
    Attachment? attachment,
    DateTime? expiresAt,
    Map<String, String>? reactions,
  }) =>
      Message(
        id: id,
        body: body,
        sentAt: sentAt,
        isMine: isMine,
        kind: kind,
        state: state ?? this.state,
        voiceDuration: voiceDuration,
        waveform: waveform,
        senderName: senderName,
        attachment: attachment ?? this.attachment,
        expiresAt: expiresAt ?? this.expiresAt,
        clientId: clientId,
        replyToId: replyToId,
        replyPreview: replyPreview,
        replySender: replySender,
        reactions: reactions ?? this.reactions,
      );
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
    this.typing = false,
    this.presence = Presence.hidden,
    this.avatarSeed = 0,
    this.avatarBytes,
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

  /// True while the other side is typing, which the row shows in the accent
  /// colour instead of the last message.
  final bool typing;

  final Presence presence;
  final int avatarSeed;

  /// The decrypted profile picture, when this device has it.
  final Uint8List? avatarBytes;
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
