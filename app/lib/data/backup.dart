import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'archive.dart';
import 'message_store.dart';
import 'recovery_key.dart';

/// What a backup holds, once opened.
class BackupContents {
  const BackupContents({required this.conversations, required this.createdAt});

  final List<Conversation> conversations;
  final DateTime createdAt;
}

/// Seals and opens a backup.
///
/// The recovery key is 256 bits of entropy already, so this does not stretch it
/// — there is no password to protect. It runs it through HKDF instead, for
/// domain separation: the key that opens a backup is not the key anything else
/// would derive from the same secret.
///
/// What a backup deliberately does **not** contain is key material: no identity
/// key, no ratchet state, no session. Restoring gives you your history on a new
/// device, and that device then registers its own identity. Copying ratchet
/// state to a second device would break both of them, and quietly.
abstract final class BackupCodec {
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const int _formatVersion = 1;
  static const int _nonceLength = 12;
  static const List<int> _info = [
    // "privio-backup-v1"
    112, 114, 105, 118, 105, 111, 45, 98, 97, 99, 107, 117, 112, 45, 118, 49,
  ];

  static Future<SecretKey> _deriveKey(RecoveryKey recovery) => _hkdf.deriveKey(
        secretKey: SecretKey(recovery.bytes),
        // No salt: the recovery key is already random and used once, so a salt
        // would add a field to carry and nothing else.
        nonce: const [],
        info: _info,
      );

  static Future<Uint8List> seal(
    List<Conversation> conversations, {
    required RecoveryKey recovery,
    DateTime? createdAt,
  }) async {
    final plain = utf8.encode(
      jsonEncode({
        'v': _formatVersion,
        'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        'conversations': ArchiveCodec.encode(conversations),
      }),
    );
    final box = await _cipher.encrypt(plain, secretKey: await _deriveKey(recovery));
    return Uint8List.fromList(
      [_formatVersion, ...box.nonce, ...box.cipherText, ...box.mac.bytes],
    );
  }

  /// Opens a backup, or throws.
  ///
  /// Throwing is right: a backup that will not open with the key given is
  /// almost always the wrong key, and silently restoring nothing would look
  /// exactly like a backup that was empty.
  static Future<BackupContents> open(Uint8List sealed, RecoveryKey recovery) async {
    final macLength = _cipher.macAlgorithm.macLength;
    if (sealed.length < 1 + _nonceLength + macLength) {
      throw const FormatException('That backup file is too short to be one');
    }
    if (sealed.first != _formatVersion) {
      throw const FormatException('That backup was written by a newer Privio');
    }

    final plain = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(1 + _nonceLength, sealed.length - macLength),
        nonce: sealed.sublist(1, 1 + _nonceLength),
        mac: Mac(sealed.sublist(sealed.length - macLength)),
      ),
      secretKey: await _deriveKey(recovery),
    );

    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContents(
      conversations: ArchiveCodec.decode(json['conversations'] as List<dynamic>),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
