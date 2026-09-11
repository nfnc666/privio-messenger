import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../calls/call_signal.dart';

import 'package:cryptography/cryptography.dart';

import '../crypto/padding.dart';
import 'metadata_scrubber.dart';

/// An attachment prepared for sending: scrubbed, padded, sealed.
class SealedAttachment {
  const SealedAttachment({
    required this.bytes,
    required this.key,
    required this.report,
    required this.plainLength,
  });

  /// What gets uploaded. The server stores exactly this and can read none of it.
  final Uint8List bytes;

  /// The key, which travels inside the end-to-end encrypted message, never
  /// alongside the upload.
  final Uint8List key;

  final ScrubReport report;

  /// Length before padding, needed to trim the file back on the other side.
  final int plainLength;
}

/// Prepares files for sending and opens the ones that arrive.
///
/// Three things happen on the way out, in this order and always:
///
/// 1. **Metadata is stripped.** A photo carries GPS, device model and serial
///    number; encryption does not remove any of that, it just delivers it
///    intact to the recipient.
/// 2. **The size is padded.** File length is visible to the server and is a
///    strong fingerprint — it can identify a specific known file outright.
/// 3. **It is sealed with its own random key**, which only ever travels inside
///    the end-to-end encrypted message.
abstract final class AttachmentCipher {
  static final AesGcm _cipher = AesGcm.with256bits();

  static const int _nonceLength = 12;
  static const int _formatVersion = 1;

  static Future<SealedAttachment> seal(
    Uint8List file, {
    String? declaredType,
  }) async {
    final scrubbed = MetadataScrubber.scrub(file, declaredType: declaredType);
    final key = await _cipher.newSecretKey();
    return SealedAttachment(
      bytes: await _sealScrubbed(scrubbed.bytes, key),
      key: Uint8List.fromList(await key.extractBytes()),
      report: scrubbed.report,
      plainLength: scrubbed.bytes.length,
    );
  }

  /// Seals under a caller-supplied key.
  ///
  /// Used for profile pictures, where every contact must be able to open the
  /// same file and so a fresh per-file key would defeat the purpose.
  static Future<Uint8List> sealWithKey(
    Uint8List file, {
    required Uint8List key,
    String? declaredType,
  }) async {
    final scrubbed = MetadataScrubber.scrub(file, declaredType: declaredType);
    return _sealScrubbed(scrubbed.bytes, SecretKey(key));
  }

  static Future<Uint8List> _sealScrubbed(Uint8List scrubbed, SecretKey key) async {
    final box = await _cipher.encrypt(MessagePadding.pad(scrubbed), secretKey: key);
    return Uint8List.fromList(
      [_formatVersion, ...box.nonce, ...box.cipherText, ...box.mac.bytes],
    );
  }

  /// Opens a downloaded attachment. Throws when the bytes were altered — a
  /// modified file must fail loudly rather than be shown as if it were genuine.
  static Future<Uint8List> open(Uint8List sealed, Uint8List key) async {
    final macLength = _cipher.macAlgorithm.macLength;
    if (sealed.length < 1 + _nonceLength + macLength) {
      throw const FormatException('Attachment is too short to be valid');
    }
    if (sealed.first != _formatVersion) {
      throw const FormatException('Unknown attachment format');
    }

    final plain = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(1 + _nonceLength, sealed.length - macLength),
        nonce: sealed.sublist(1, 1 + _nonceLength),
        mac: Mac(sealed.sublist(sealed.length - macLength)),
      ),
      secretKey: SecretKey(key),
    );
    return MessagePadding.unpad(plain);
  }
}

/// What a message carries: text, or a pointer to an attachment.
///
/// Serialised, padded and sealed as one unit, so the server cannot tell a photo
/// from a sentence — only that something was sent.
/// A copy of something this account sent, addressed to its own other devices.
///
/// Without it a second device only ever sees the other side of a conversation:
/// what arrives is fanned out to every device, but what you send from your
/// phone is known only to your phone. The two views drift apart from the first
/// message, and the one on the laptop is not a shorter history — it is a wrong
/// one, showing a conversation in which you never answered.
///
/// It is a wrapper rather than a flag on the message, because the receiving
/// device has to file it as *outgoing* in a named conversation, which is a
/// different act from receiving a message from somebody.
@immutable
class SyncEnvelope {
  const SyncEnvelope({
    required this.conversationId,
    required this.isGroup,
    required this.payload,
  });

  factory SyncEnvelope.fromJson(Map<String, dynamic> json) => SyncEnvelope(
        conversationId: json['c'] as String? ?? '',
        isGroup: json['g'] as bool? ?? false,
        payload: json['p'] as String? ?? '',
      );

  /// Where it was sent: the recipient's account id, or the group's id.
  final String conversationId;
  final bool isGroup;

  /// The original payload, exactly as the recipient received it.
  final String payload;

  /// What was sent, unwrapped.
  MessagePayload get inner => MessagePayload.decode(payload);

  Map<String, dynamic> toJson() => {'c': conversationId, 'g': isGroup, 'p': payload};
}

class MessagePayload {
  const MessagePayload.text(
    this.body, {
    this.profileKey,
    this.groupKey,
    this.expiresInSeconds,
    this.clientId,
    this.replyToId,
    this.replyPreview,
    this.replySender,
  })  : mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        mediaToken = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// A key handed to one device, sealed inside an ordinary message.
  ///
  /// This is how a join link can be public: the link carries only the code, and
  /// the key that opens the channel's posts (or a group's sealed name) travels
  /// afterwards over the Signal session between the two devices. The server
  /// relays these bytes exactly as it relays a sentence, and can read neither.
  const MessagePayload.key({
    required String this.keyScopeId,
    required String this.keyScope,
    required String this.deliveredKey,
    this.keyEpoch,
  })  : body = '',
        mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        mediaToken = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// A reaction to one message.
  ///
  /// Control, not conversation: it changes a message that is already there
  /// rather than adding one. Removing a reaction is the same payload with an
  /// empty emoji, so there is one shape to send, receive and reason about.
  const MessagePayload.reaction({
    required String this.reactionTo,
    required String this.reactionEmoji,
  })  : body = '',
        deleteTo = null,
        mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        mediaToken = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// A request to take a message back.
  ///
  /// Control, never conversation: it names a message the sender wants gone and
  /// carries nothing else. Whether it is honoured is the receiving device's
  /// business — which is the honest shape for this. Privio can ask the app on
  /// the other phone to forget something; it cannot reach into a screenshot,
  /// somebody's memory, or a copy already restored from a backup, and the
  /// screen that offers this says so rather than implying an undo.
  const MessagePayload.deletion(String this.deleteTo)
      : body = '',
        mediaId = null,
        mediaKey = null,
        mediaToken = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// "Start again — I cannot read what you are sending."
  ///
  /// Sent by the side whose session broke, after it has deleted that session
  /// locally. It carries nothing: the repair is the *act* of sending it. With
  /// no session left, this goes out as a prekey message built from a fresh
  /// bundle, and the Signal library archives the old state on the other side
  /// the moment it arrives — so one payload puts both directions back on a
  /// working ratchet. Nothing about it is shown to either person.
  const MessagePayload.sessionReset()
      : sessionReset = true,
        timerChange = false,
        receiptGroupId = null,
        body = '',
        mediaId = null,
        mediaKey = null,
        mediaToken = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        sync = null,
        call = null;

  /// A receipt for messages that arrived, or were read.
  ///
  /// Its own payload kind rather than a field on a message, because a receipt
  /// is not a message: it must never appear in a conversation, and it carries
  /// no body to appear with.
  const MessagePayload.receipt({
    required List<String> this.receiptIds,
    required String this.receiptKind,
    this.receiptGroupId,
  })  : body = '',
        mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        mediaToken = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false;

  /// "Still typing." Carries a timestamp rather than a duration so a stale one
  /// — delivered late, or after the app was closed — can be recognised as stale
  /// and ignored instead of showing someone typing who stopped an hour ago.
  const MessagePayload.typing(int this.typingAt)
      : body = '',
        mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        mediaToken = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  const MessagePayload.media({
    required String this.mediaId,
    required String this.mediaKey,
    this.mediaToken,
    required String this.mediaType,
    required int this.byteSize,
    this.fileName,
    this.body = '',
    this.profileKey,
    this.groupKey,
    this.voiceDurationMs,
    this.waveform,
    this.expiresInSeconds,
    this.clientId,
    this.replyToId,
    this.replyPreview,
    this.replySender,
  })  : keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        reactionEmoji = null,
        deleteTo = null,
        sync = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// One step in setting up, or tearing down, a call.
  ///
  /// Control, never conversation: it must not appear in a chat, and it carries
  /// no body to appear with. It rides here rather than on its own endpoint so
  /// that the SDP — which lists the addresses this device can be reached on —
  /// is sealed to the other device exactly as a sentence is. A server that
  /// could read it would learn where both people are.
  const MessagePayload.callSignal(CallSignal this.call)
      : body = '',
        sync = null,
        mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        mediaToken = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// A copy of something this account sent, for its own other devices.
  ///
  /// Control, never conversation: it is filed as an outgoing message in the
  /// conversation it names, and must never appear as one somebody sent to you.
  const MessagePayload.sync(SyncEnvelope this.sync)
      : body = '',
        mediaId = null,
        mediaKey = null,
        mediaToken = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        expiresInSeconds = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        call = null,
        sessionReset = false,
        timerChange = false,
        receiptGroupId = null;

  /// "This chat now deletes itself after N seconds" — or, with null, "it no
  /// longer does".
  ///
  /// Control, never conversation: it changes a setting rather than saying
  /// anything, so it must not become a bubble on the other side. The notice
  /// each device writes about it is the device's own, composed locally.
  ///
  /// It exists because the timer used to travel only on the back of the next
  /// real message. That is fine when there is one, and wrong when there is
  /// not: someone turns disappearing messages on, says nothing further, and
  /// the other side keeps writing into a chat it believes is permanent. The
  /// number is the same one [MessagePayload.text] carries; null means off, and
  /// is the reason this needs a tag of its own rather than an absent field.
  ///
  /// What the server learns from it is what it learns from any message: that
  /// one went to this conversation at this moment. The value is inside the
  /// ciphertext.
  const MessagePayload.timerChange(this.expiresInSeconds)
      : timerChange = true,
        body = '',
        sessionReset = false,
        receiptGroupId = null,
        mediaId = null,
        mediaKey = null,
        mediaToken = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        profileKey = null,
        groupKey = null,
        keyScope = null,
        keyScopeId = null,
        keyEpoch = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null,
        clientId = null,
        receiptIds = null,
        receiptKind = null,
        typingAt = null,
        reactionTo = null,
        deleteTo = null,
        reactionEmoji = null,
        replyToId = null,
        replyPreview = null,
        replySender = null,
        sync = null,
        call = null;

  factory MessagePayload.decode(String raw) {
    // Anything that is not our JSON is a plain message from an older build.
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }
    if (json == null || json['v'] != 1) return MessagePayload.text(raw);

    final profileKey = json['pk'] as String?;
    final groupKey = json['gk'] as String?;
    final expiresInSeconds = json['ex'] as int?;
    final clientId = json['ci'] as String?;
    final quote = (
      id: json['qi'] as String?,
      preview: json['qp'] as String?,
      sender: json['qs'] as String?,
    );
    if (json['t'] == 'sync') {
      return MessagePayload.sync(
        SyncEnvelope.fromJson((json['sy'] as Map<String, dynamic>?) ?? const {}),
      );
    }
    if (json['t'] == 'call') {
      return MessagePayload.callSignal(
        CallSignal.fromJson((json['cl'] as Map<String, dynamic>?) ?? const {}),
      );
    }
    if (json['t'] == 'reset') {
      return const MessagePayload.sessionReset();
    }
    if (json['t'] == 'timer') {
      // `ex` absent means off, which is why this is read here rather than
      // inferred from a missing field further down.
      return MessagePayload.timerChange(expiresInSeconds);
    }
    if (json['t'] == 'delete') {
      return MessagePayload.deletion(json['dt'] as String? ?? '');
    }
    if (json['t'] == 'reaction') {
      return MessagePayload.reaction(
        reactionTo: json['rt'] as String,
        reactionEmoji: json['re'] as String? ?? '',
      );
    }
    if (json['t'] == 'receipt') {
      return MessagePayload.receipt(
        receiptIds: (json['ri'] as List<dynamic>? ?? const []).cast<String>(),
        receiptKind: json['rk'] as String? ?? 'delivered',
        receiptGroupId: json['rg'] as String?,
      );
    }
    if (json['t'] == 'typing') {
      return MessagePayload.typing(json['ta'] as int? ?? 0);
    }
    if (json['t'] == 'key') {
      return MessagePayload.key(
        keyScope: json['ks'] as String,
        keyScopeId: json['ki'] as String,
        keyEpoch: (json['ke'] as num?)?.toInt(),
        deliveredKey: json['kk'] as String,
      );
    }
    if (json['t'] == 'media') {
      return MessagePayload.media(
        mediaId: json['id'] as String,
        mediaKey: json['k'] as String,
        mediaToken: json['tk'] as String?,
        mediaType: json['m'] as String,
        byteSize: json['s'] as int,
        fileName: json['n'] as String?,
        body: json['b'] as String? ?? '',
        profileKey: profileKey,
        groupKey: groupKey,
        voiceDurationMs: json['vd'] as int?,
        waveform:
            (json['wf'] as List<dynamic>?)?.map((value) => (value as num).toDouble()).toList(),
        expiresInSeconds: expiresInSeconds,
        clientId: clientId,
        replyToId: quote.id,
        replyPreview: quote.preview,
        replySender: quote.sender,
      );
    }
    return MessagePayload.text(
      json['b'] as String? ?? '',
      profileKey: profileKey,
      groupKey: groupKey,
      expiresInSeconds: expiresInSeconds,
      clientId: clientId,
      replyToId: quote.id,
      replyPreview: quote.preview,
      replySender: quote.sender,
    );
  }

  /// A caption, or the message text.
  final String body;

  final String? mediaId;

  /// Base64. Never leaves the end-to-end encrypted envelope.
  final String? mediaKey;

  /// What the server will accept as permission to download this blob.
  ///
  /// Handed out once at upload and never stored server-side, so it travels
  /// here — sealed, beside the key that opens what it fetches. Whoever can
  /// read the message can fetch the file, and nobody else, without the server
  /// ever being told who that is.
  final String? mediaToken;

  /// The name the sender chose. It rides inside the encrypted payload, so the
  /// server never sees "passport_scan.pdf".
  final String? fileName;
  final String? mediaType;
  final int? byteSize;

  /// The sender's profile key, base64, attached to every message they send.
  ///
  /// This is how a contact comes to be able to open your profile picture: it
  /// rides inside the sealed payload, so the server never learns it and only
  /// people you have actually written to can use it.
  final String? profileKey;

  /// The key that opens a group's sealed name, attached to group messages so a
  /// member learns it without the server ever holding it.
  final String? groupKey;

  /// 'channel' or 'group' on a key delivery; null on anything else.
  final String? keyScope;

  /// Which channel or group the delivered key belongs to.
  final String? keyScopeId;

  /// Which version of a channel's key this is.
  ///
  /// Null for a group, which has one key, and null from a client that predates
  /// versioning — read as epoch 1, which is what such a client holds. A channel
  /// key without its epoch is a key nobody can place: it would either be filed
  /// over the current one or ignored, and both are wrong.
  final int? keyEpoch;

  /// Base64 of the key itself. Only ever inside a sealed envelope.
  final String? deliveredKey;

  /// Length of a voice message, in milliseconds.
  ///
  /// Inside the payload rather than derived from the file, so the bubble can
  /// show "0:14" before anything has been downloaded — and so the server, which
  /// sees only a padded blob, learns nothing about how long anyone spoke.
  final int? voiceDurationMs;

  /// The bars the recorder measured while recording, 0..1.
  final List<double>? waveform;

  /// How long after delivery this message should disappear, in seconds.
  ///
  /// The sender's setting, carried end to end so both sides agree. The server
  /// is not asked and is not trusted with it: it deletes envelopes on its own
  /// schedule, which is a different thing from a message expiring.
  final int? expiresInSeconds;

  /// The sender's own id for this message.
  ///
  /// Survives a retry, which is what stops a resend after a dropped connection
  /// from arriving as a second voice message.
  final String? clientId;

  /// On a receipt: the client ids being acknowledged.
  final List<String>? receiptIds;

  /// `delivered` or `read`.
  final String? receiptKind;

  /// On a typing notice: when the sender was typing, in milliseconds since the
  /// epoch. A notice that arrives long after that is stale and ignored.
  final int? typingAt;

  /// On a reaction: the client id of the message being reacted to.
  final String? reactionTo;

  /// The emoji, or empty to take a reaction back.
  final String? reactionEmoji;

  /// On a deletion: the client id of the message to take back.
  final String? deleteTo;

  /// On a reply: the client id of the message being replied to.
  final String? replyToId;

  /// A short quote of that message, carried with the reply.
  ///
  /// Sent rather than looked up, because the other side may have deleted the
  /// original, or it may have disappeared on their timer — and a reply that
  /// quotes nothing is a reply to nothing.
  final String? replyPreview;

  /// Who wrote the quoted message, as the sender labels them.
  final String? replySender;

  /// The call signal this payload carries, if it carries one.
  final CallSignal? call;

  /// True on the payload that asks the other side to start a new session.
  final bool sessionReset;

  /// True on the payload whose whole job is to change the chat's timer.
  ///
  /// A flag rather than "expiresInSeconds is set", because the change that
  /// matters most — turning the timer off — carries no number at all.
  final bool timerChange;

  /// On a receipt for group messages: which group they were in.
  ///
  /// The receipt itself is addressed to the author, not to the group — who read
  /// what is nobody else's business, and fanning it out would cost a copy per
  /// device to say so. Which means it has to name the conversation, because the
  /// envelope it rides in says only who sent it.
  final String? receiptGroupId;

  /// A copy of an outgoing message, for this account's own other devices.
  final SyncEnvelope? sync;

  /// The same payload with a profile key attached.
  ///
  /// A method rather than a rebuild at each call site: this type has grown
  /// fields (voice duration, waveform, expiry, client id) and every one of them
  /// was once quietly dropped by a hand-written copy.
  MessagePayload withProfileKey(String key) {
    // Control payloads carry no profile key: a receipt is not a place to attach
    // anything about who sent it beyond what the envelope already says.
    if (isControl) return this;
    if (isMedia) {
      return MessagePayload.media(
        mediaId: mediaId!,
        mediaKey: mediaKey!,
        mediaToken: mediaToken,
        mediaType: mediaType!,
        byteSize: byteSize!,
        fileName: fileName,
        body: body,
        profileKey: key,
        groupKey: groupKey,
        voiceDurationMs: voiceDurationMs,
        waveform: waveform,
        expiresInSeconds: expiresInSeconds,
        clientId: clientId,
        replyToId: replyToId,
        replyPreview: replyPreview,
        replySender: replySender,
      );
    }
    return MessagePayload.text(
      body,
      profileKey: key,
      groupKey: groupKey,
      expiresInSeconds: expiresInSeconds,
      clientId: clientId,
      replyToId: replyToId,
      replyPreview: replyPreview,
      replySender: replySender,
    );
  }

  bool get isMedia => mediaId != null;

  bool get isCall => call != null;
  bool get isSync => sync != null;
  bool get isDeletion => deleteTo != null;
  bool get isReceipt => receiptKind != null;
  bool get isTyping => typingAt != null;
  bool get isReaction => reactionTo != null;
  bool get isSessionReset => sessionReset;

  /// Whether this payload's only purpose is to move the chat's timer.
  bool get isTimerChange => timerChange;

  /// True when the reaction takes one back rather than adding one.
  bool get clearsReaction => isReaction && (reactionEmoji ?? '').isEmpty;

  /// True for anything that is machinery rather than conversation, and so must
  /// never end up in a chat.
  bool get isControl =>
      isReceipt ||
      isTyping ||
      isReaction ||
      isKeyDelivery ||
      isCall ||
      isSync ||
      isSessionReset ||
      isTimerChange ||
      isDeletion;

  bool get isVoice => (mediaType ?? '').startsWith('audio/');

  Duration? get voiceDuration =>
      voiceDurationMs == null ? null : Duration(milliseconds: voiceDurationMs!);

  /// True when this payload is a key for someone, not a message to show.
  bool get isKeyDelivery => deliveredKey != null;

  /// The one word that tells the other side how to read the rest.
  ///
  /// A getter rather than a ternary inside [encode]: it was a six-deep nested
  /// conditional, and each new payload kind made it harder to see that exactly
  /// one branch can win.
  String get _typeTag {
    if (isSessionReset) return 'reset';
    if (isTimerChange) return 'timer';
    if (isSync) return 'sync';
    if (isCall) return 'call';
    if (isDeletion) return 'delete';
    if (isReaction) return 'reaction';
    if (isReceipt) return 'receipt';
    if (isTyping) return 'typing';
    if (isKeyDelivery) return 'key';
    if (isMedia) return 'media';
    return 'text';
  }

  String encode() => jsonEncode({
        'v': 1,
        't': _typeTag,
        'b': body,
        if (expiresInSeconds != null) 'ex': expiresInSeconds,
        if (clientId != null) 'ci': clientId,
        if (isSync) 'sy': sync!.toJson(),
        if (isCall) 'cl': call!.toJson(),
        if (isReceipt) ...{
          'ri': receiptIds,
          'rk': receiptKind,
          if (receiptGroupId != null) 'rg': receiptGroupId,
        },
        if (isTyping) 'ta': typingAt,
        if (isDeletion) 'dt': deleteTo,
        if (isReaction) ...{'rt': reactionTo, 're': reactionEmoji},
        if (replyToId != null) ...{
          'qi': replyToId,
          if (replyPreview != null) 'qp': replyPreview,
          if (replySender != null) 'qs': replySender,
        },
        if (isKeyDelivery) ...{
          'ks': keyScope,
          'ki': keyScopeId,
          if (keyEpoch != null) 'ke': keyEpoch,
          'kk': deliveredKey,
        },
        if (profileKey != null) 'pk': profileKey,
        if (groupKey != null) 'gk': groupKey,
        if (isMedia) ...{
          'id': mediaId,
          'k': mediaKey,
          if (mediaToken != null) 'tk': mediaToken,
          'm': mediaType,
          's': byteSize,
          if (fileName != null) 'n': fileName,
          if (voiceDurationMs != null) 'vd': voiceDurationMs,
          if (waveform != null)
            'wf': [
              // Two decimals is all a 48-bar sparkline can show, and fewer digits
              // is less shape of someone's voice on the wire.
              for (final bar in waveform!) double.parse(bar.toStringAsFixed(2)),
            ],
        },
      });
}
