import 'package:flutter/foundation.dart';


@immutable
class Contact {
  const Contact({
    required this.id,
    required this.username,
    required this.displayName,
    this.lastSeenAt,
    this.avatarSeed = 0,
    this.avatarBytes,
  });

  final String id;
  final String username;
  final String displayName;

  /// When the server last heard from them, or null.
  ///
  /// Null is the normal answer, not an error: it is what the server returns
  /// when this person's own last-seen setting does not include the person
  /// asking. Nothing here infers anything from it — a timestamp is what the
  /// server has, and "online" is not.
  final DateTime? lastSeenAt;
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

enum MessageKind {
  text,
  voice,
  photo,
  video,
  file,

  /// What is left after someone took a message back. It keeps its place in the
  /// conversation and carries nothing else.
  deleted,
}

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
    this.mediaToken,
  });

  final String mediaId;
  final String mediaKey;

  /// What the server accepts as permission to download the bytes.
  ///
  /// Kept with the message rather than fetched again, because it is issued once
  /// at upload and the server stores only its hash. Null on anything filed
  /// before this existed, and on an attachment of one's own — the uploader is
  /// always allowed.
  final String? mediaToken;
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
    this.senderAccountId,
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

  /// Who wrote it, for messages that arrived. Null on this account's own, and
  /// on anything filed by a build that predates the field.
  ///
  /// Kept because "delete for everyone" has to be checked against something: a
  /// request may only remove a message its own sender wrote.
  final String? senderAccountId;

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
        senderAccountId: senderAccountId,
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

  final int avatarSeed;

  /// The decrypted profile picture, when this device has it.
  final Uint8List? avatarBytes;
}

// Calls and linked devices used to have models here, shaped for the demo data
// that fed them: a call had a `timestamp` that was the string "Yesterday", and
// a device had a `lastActive` that was the string "Last active: 2h ago". Both
// are gone with the fabricated lists. Devices are described by
// `LinkedDevice` in `core/security_controller.dart`, from what the server
// says; calls will get a model when there are calls.
