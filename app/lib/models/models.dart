import '../media/attachment.dart' show CustomEmojiRef;
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

  /// A sticker: a picture sent on its own, drawn without a bubble.
  ///
  /// Its own kind rather than a photo, because the two are not the same thing
  /// to look at or to handle — a sticker has no caption, no bubble, no download
  /// and no save, and it is the pack it came from that a tap should open.
  sticker,

  /// What is left after someone took a message back. It keeps its place in the
  /// conversation and carries nothing else.
  deleted,

  /// A line the app writes itself, to record something that changed about the
  /// conversation rather than something somebody said — today, only the
  /// disappearing-message timer.
  ///
  /// It is never sent anywhere: both sides write their own from the same fact,
  /// which is also why it carries no sender and no client id.
  notice,

  /// Something arrived and could not be read.
  ///
  /// Its own kind rather than a [notice], because it is not housekeeping: a
  /// message was sent to this person and they will never see it. The one thing
  /// worse than saying so is not saying so — a conversation with a silent hole
  /// in it reads as a conversation where nobody answered.
  undelivered,
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

/// What a system notice is about, as a fact rather than a sentence.
///
/// The sentence used to be all there was: `_noteTimerChange` wrote "Anna set
/// disappearing messages to 1 hour" into `body` and that string was the record.
/// It cannot be, once the app has five languages — the notice was written in
/// whatever the *writer's* app was set to at the time, and it would still say
/// that years later to a reader who has since switched, because a stored
/// sentence has no way to change its mind.
///
/// So what is stored is the event and its parameters, and the sentence is built
/// at the moment it is drawn, in the language of whoever is looking.
enum NoticeKind {
  /// A disappearing-messages timer was set. Carries [SystemNotice.duration].
  timerSet,

  /// A disappearing-messages timer was turned off.
  timerOff,

  /// Messages arrived that this device has no key for. Carries
  /// [SystemNotice.count].
  unreadable,
}

/// One system notice: what happened, and the few things the sentence needs.
///
/// Deliberately small and typed rather than a free map. Every parameter here
/// is something a translation has to be able to place — a name, a count, a
/// duration — and anything that is not one of those belongs in the event kind
/// instead.
@immutable
class SystemNotice {
  const SystemNotice(this.kind, {this.who, this.duration, this.count});

  final NoticeKind kind;

  /// Who did it, as a label to show. **Null means this account**, which every
  /// language renders as its own word for "you" — the name is not stored for
  /// the reader's own actions because there is no name that reads right in
  /// every language.
  final String? who;

  /// The timer that was set, for [NoticeKind.timerSet].
  final Duration? duration;

  /// How many messages, for [NoticeKind.unreadable].
  final int? count;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (who != null) 'who': who,
        if (duration != null) 'durationSeconds': duration!.inSeconds,
        if (count != null) 'count': count,
      };

  /// Null for anything this build does not recognise, which is the honest
  /// answer: an archive written by a newer version may hold a notice kind that
  /// did not exist here, and the stored `body` is still a readable sentence.
  static SystemNotice? fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final name = raw['kind'] as String?;
    NoticeKind? kind;
    for (final value in NoticeKind.values) {
      if (value.name == name) kind = value;
    }
    if (kind == null) return null;
    final seconds = raw['durationSeconds'] as int?;
    return SystemNotice(
      kind,
      who: raw['who'] as String?,
      duration: seconds == null ? null : Duration(seconds: seconds),
      count: raw['count'] as int?,
    );
  }
}

/// Which sticker a message is, and where its picture comes from.
///
/// All three ids together, because each answers a different question and the
/// message has to go on answering all of them after the pack has changed:
/// [itemId] is what a reaction or a favourite points at, [packId] is what a tap
/// offers, and [mediaId] is what draws it. A pack that has been deleted leaves
/// the first two naming nothing — and the message still renders, from the
/// third, or from the fallback character in its body.
@immutable
class StickerRef {
  const StickerRef({
    required this.itemId,
    required this.packId,
    required this.mediaId,
  });

  static StickerRef? fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final itemId = raw['itemId'] as String?;
    final mediaId = raw['mediaId'] as String?;
    if (itemId == null || mediaId == null) return null;
    return StickerRef(
      itemId: itemId,
      packId: raw['packId'] as String? ?? '',
      mediaId: mediaId,
    );
  }

  final String itemId;
  final String packId;
  final String mediaId;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'packId': packId,
        'mediaId': mediaId,
      };

  @override
  bool operator ==(Object other) =>
      other is StickerRef &&
      other.itemId == itemId &&
      other.packId == packId &&
      other.mediaId == mediaId;

  @override
  int get hashCode => Object.hash(itemId, packId, mediaId);
}

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
    this.receipts = const {},
    this.notice,
    this.sticker,
    this.customEmoji,
    this.reactionStickers = const {},
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

  /// Set when this message *is* a sticker.
  ///
  /// [body] still holds the character it stands for, so a message whose picture
  /// cannot be fetched — a pack deleted, a device offline — is still something
  /// rather than a grey square.
  final StickerRef? sticker;

  /// Custom emoji to draw over spans of [body], if the reader has the packs.
  ///
  /// An overlay: [body] already reads correctly without it. See
  /// [CustomEmojiRef].
  final List<CustomEmojiRef>? customEmoji;

  /// For the reactions that were made with a custom emoji: who used which item.
  ///
  /// Keyed by account id, like [reactions], and always a *subset* of it — the
  /// character in `reactions` is what a reader without the pack sees, and this
  /// says which ones can be drawn as pictures instead. Kept apart rather than
  /// making `reactions` a richer type, so every existing reader of `reactions`
  /// goes on working and an unknown pack degrades by simply not being here.
  final Map<String, StickerRef> reactionStickers;

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

  /// In a group, how far each member has got with this message: their account
  /// id to the furthest state they have reported.
  ///
  /// A group has no single answer to "did it arrive", and [state] cannot hold
  /// one honestly — two ticks that light up because one of seven people opened
  /// the app say something that is not true. So the per-member answers are kept
  /// and [state] moves only when everybody has. Empty on a direct message,
  /// where the two are the same thing.
  final Map<String, DeliveryState> receipts;

  /// How many members have at least received it.
  int get deliveredCount => receipts.length;

  /// How many have read it.
  int get readCount =>
      receipts.values.where((state) => state == DeliveryState.read).length;

  bool get isReply => replyToId != null;

  bool get isVoice => kind == MessageKind.voice;

  /// What this notice is about, for a notice written by a build that records
  /// it. Null on everything else, and on notices filed before this existed —
  /// those still have their sentence in [body], in whatever language it was
  /// written in, and that is the best that can be done for them.
  final SystemNotice? notice;

  /// A line about the conversation rather than in it. Not a bubble, not unread,
  /// not something to reply to, react to, search or take back.
  bool get isNotice => kind == MessageKind.notice || kind == MessageKind.undelivered;

  bool hasExpiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  Message copyWith({
    DeliveryState? state,
    Attachment? attachment,
    DateTime? expiresAt,
    Map<String, String>? reactions,
    Map<String, DeliveryState>? receipts,
    Map<String, StickerRef>? reactionStickers,
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
        receipts: receipts ?? this.receipts,
        reactionStickers: reactionStickers ?? this.reactionStickers,
        notice: notice,
        sticker: sticker,
        customEmoji: customEmoji,
      );
}

/// What the last line of a chat row says, as a case.
///
/// The controller cannot write it: "Photo" is a word, and which word depends on
/// the reader. [text] is the one part that is never translated — a message
/// somebody wrote, or the name they gave a file.
enum ChatPreviewKind { empty, typing, deleted, body, notice, photo, video, voice, file }

@immutable
class ChatPreview {
  const ChatPreview(this.kind, {this.text, this.notice});

  static const ChatPreview empty = ChatPreview(ChatPreviewKind.empty);

  final ChatPreviewKind kind;

  /// Written by a person: a message body or a file name. Shown as it was typed.
  final String? text;

  /// Set when [kind] is [ChatPreviewKind.notice] — the stored event, said in
  /// the reader's language at the moment the row is drawn.
  final SystemNotice? notice;
}

/// When the last message arrived, as a case rather than a formatted string.
///
/// "Yesterday" is a word, and 04.09. is one language's idea of a date. Both
/// belong to the screen.
enum ChatStampKind { none, time, yesterday, date }

@immutable
class ChatStamp {
  const ChatStamp(this.kind, {this.at});

  static const ChatStamp none = ChatStamp(ChatStampKind.none);

  final ChatStampKind kind;
  final DateTime? at;
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
  final ChatPreview preview;

  /// When, as a case. The row formats it for the locale it is drawn in — the
  /// same message reads "11:32" and "Gestern" on two phones in one chat.
  final ChatStamp timestamp;
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
