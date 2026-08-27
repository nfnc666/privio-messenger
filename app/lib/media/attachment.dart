import 'dart:convert';
import 'dart:typed_data';

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
class MessagePayload {
  const MessagePayload.text(
    this.body, {
    this.profileKey,
    this.groupKey,
    this.expiresInSeconds,
    this.clientId,
  })  : mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null,
        keyScope = null,
        keyScopeId = null,
        deliveredKey = null,
        voiceDurationMs = null,
        waveform = null;

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
        clientId = null;

  const MessagePayload.media({
    required String this.mediaId,
    required String this.mediaKey,
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
  })  : keyScope = null,
        keyScopeId = null,
        deliveredKey = null;

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
    if (json['t'] == 'key') {
      return MessagePayload.key(
        keyScope: json['ks'] as String,
        keyScopeId: json['ki'] as String,
        deliveredKey: json['kk'] as String,
      );
    }
    if (json['t'] == 'media') {
      return MessagePayload.media(
        mediaId: json['id'] as String,
        mediaKey: json['k'] as String,
        mediaType: json['m'] as String,
        byteSize: json['s'] as int,
        fileName: json['n'] as String?,
        body: json['b'] as String? ?? '',
        profileKey: profileKey,
        groupKey: groupKey,
        voiceDurationMs: json['vd'] as int?,
        waveform: (json['wf'] as List<dynamic>?)
            ?.map((value) => (value as num).toDouble())
            .toList(),
        expiresInSeconds: expiresInSeconds,
        clientId: clientId,
      );
    }
    return MessagePayload.text(
      json['b'] as String? ?? '',
      profileKey: profileKey,
      groupKey: groupKey,
      expiresInSeconds: expiresInSeconds,
      clientId: clientId,
    );
  }

  /// A caption, or the message text.
  final String body;

  final String? mediaId;

  /// Base64. Never leaves the end-to-end encrypted envelope.
  final String? mediaKey;

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

  /// The same payload with a profile key attached.
  ///
  /// A method rather than a rebuild at each call site: this type has grown
  /// fields (voice duration, waveform, expiry, client id) and every one of them
  /// was once quietly dropped by a hand-written copy.
  MessagePayload withProfileKey(String key) {
    if (isKeyDelivery) return this;
    if (isMedia) {
      return MessagePayload.media(
        mediaId: mediaId!,
        mediaKey: mediaKey!,
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
      );
    }
    return MessagePayload.text(
      body,
      profileKey: key,
      groupKey: groupKey,
      expiresInSeconds: expiresInSeconds,
      clientId: clientId,
    );
  }

  bool get isMedia => mediaId != null;

  bool get isVoice => (mediaType ?? '').startsWith('audio/');

  Duration? get voiceDuration =>
      voiceDurationMs == null ? null : Duration(milliseconds: voiceDurationMs!);

  /// True when this payload is a key for someone, not a message to show.
  bool get isKeyDelivery => deliveredKey != null;

  String encode() => jsonEncode({
        'v': 1,
        't': isKeyDelivery
            ? 'key'
            : isMedia
                ? 'media'
                : 'text',
        'b': body,
        if (expiresInSeconds != null) 'ex': expiresInSeconds,
        if (clientId != null) 'ci': clientId,
        if (isKeyDelivery) ...{
          'ks': keyScope,
          'ki': keyScopeId,
          'kk': deliveredKey,
        },
        if (profileKey != null) 'pk': profileKey,
        if (groupKey != null) 'gk': groupKey,
        if (isMedia) ...{
          'id': mediaId,
          'k': mediaKey,
          'm': mediaType,
          's': byteSize,
          if (fileName != null) 'n': fileName,
          if (voiceDurationMs != null) 'vd': voiceDurationMs,
          if (waveform != null) 'wf': [
            // Two decimals is all a 48-bar sparkline can show, and fewer digits
            // is less shape of someone's voice on the wire.
            for (final bar in waveform!) double.parse(bar.toStringAsFixed(2)),
          ],
        },
      });
}
