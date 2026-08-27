import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A message that is waiting to go out.
///
/// Voice messages make the queue necessary: someone records a reply on a train,
/// the network drops, and the recording has to survive until there is signal
/// again — losing it would be worse than any delay.
///
/// What is queued is the *sealed* recording, never the raw one. The bytes here
/// are already ciphertext under [mediaKey], so the queue can be written to the
/// encrypted archive without a plaintext recording ever reaching storage. The
/// key sits beside them because the archive itself is sealed at rest; that is
/// the same protection the message history already has.
@immutable
class PendingSend {
  const PendingSend({
    required this.clientId,
    required this.conversationId,
    required this.isGroup,
    required this.mediaType,
    required this.sealedBytes,
    required this.mediaKey,
    required this.plainLength,
    required this.durationMs,
    required this.waveform,
    this.username,
    this.groupKey,
    this.mediaId,
    this.expiresInSeconds,
    this.attempts = 0,
  });

  /// The sender's id for this message. Doubles as the send's idempotency key,
  /// so a retry is recognised by the server instead of delivered twice.
  final String clientId;

  final String conversationId;
  final bool isGroup;

  /// Needed to address a direct send; null for a group.
  final String? username;

  /// Carried along so a member who joined by a link still learns the group's
  /// name key from this message.
  final String? groupKey;

  final String mediaType;

  /// Ciphertext. Safe to persist.
  final Uint8List sealedBytes;

  /// Base64. Opens [sealedBytes], and travels inside the sealed payload.
  final String mediaKey;

  final int plainLength;
  final int durationMs;
  final List<double> waveform;

  /// Set once the upload has succeeded, so a retry after a failed *send* does
  /// not upload the same recording a second time.
  final String? mediaId;

  final int? expiresInSeconds;

  /// How many times this has been tried. Only used to back off.
  final int attempts;

  Duration get duration => Duration(milliseconds: durationMs);

  PendingSend copyWith({String? mediaId, int? attempts}) => PendingSend(
        clientId: clientId,
        conversationId: conversationId,
        isGroup: isGroup,
        username: username,
        groupKey: groupKey,
        mediaType: mediaType,
        sealedBytes: sealedBytes,
        mediaKey: mediaKey,
        plainLength: plainLength,
        durationMs: durationMs,
        waveform: waveform,
        mediaId: mediaId ?? this.mediaId,
        expiresInSeconds: expiresInSeconds,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'conversationId': conversationId,
        'isGroup': isGroup,
        if (username != null) 'username': username,
        if (groupKey != null) 'groupKey': groupKey,
        'mediaType': mediaType,
        'sealedBytes': base64Encode(sealedBytes),
        'mediaKey': mediaKey,
        'plainLength': plainLength,
        'durationMs': durationMs,
        'waveform': waveform,
        if (mediaId != null) 'mediaId': mediaId,
        if (expiresInSeconds != null) 'expiresInSeconds': expiresInSeconds,
        'attempts': attempts,
      };

  static PendingSend fromJson(Map<String, dynamic> json) => PendingSend(
        clientId: json['clientId'] as String,
        conversationId: json['conversationId'] as String,
        isGroup: json['isGroup'] as bool? ?? false,
        username: json['username'] as String?,
        groupKey: json['groupKey'] as String?,
        mediaType: json['mediaType'] as String? ?? 'audio/mp4',
        sealedBytes: base64Decode(json['sealedBytes'] as String),
        mediaKey: json['mediaKey'] as String,
        plainLength: json['plainLength'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        waveform: (json['waveform'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList(),
        mediaId: json['mediaId'] as String?,
        expiresInSeconds: json['expiresInSeconds'] as int?,
        attempts: json['attempts'] as int? ?? 0,
      );
}
