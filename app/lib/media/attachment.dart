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
  const MessagePayload.text(this.body, {this.profileKey})
      : mediaId = null,
        mediaKey = null,
        fileName = null,
        mediaType = null,
        byteSize = null;

  const MessagePayload.media({
    required String this.mediaId,
    required String this.mediaKey,
    required String this.mediaType,
    required int this.byteSize,
    this.fileName,
    this.body = '',
    this.profileKey,
  });

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
    if (json['t'] == 'media') {
      return MessagePayload.media(
        mediaId: json['id'] as String,
        mediaKey: json['k'] as String,
        mediaType: json['m'] as String,
        byteSize: json['s'] as int,
        fileName: json['n'] as String?,
        body: json['b'] as String? ?? '',
        profileKey: profileKey,
      );
    }
    return MessagePayload.text(json['b'] as String? ?? '', profileKey: profileKey);
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

  bool get isMedia => mediaId != null;

  String encode() => jsonEncode({
        'v': 1,
        't': isMedia ? 'media' : 'text',
        'b': body,
        if (profileKey != null) 'pk': profileKey,
        if (isMedia) ...{
          'id': mediaId,
          'k': mediaKey,
          'm': mediaType,
          's': byteSize,
          if (fileName != null) 'n': fileName,
        },
      });
}
