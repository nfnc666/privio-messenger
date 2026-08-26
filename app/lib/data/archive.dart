import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/secure_store.dart';
import '../models/models.dart';
import 'message_store.dart';

/// Where the sealed archive bytes are kept.
///
/// A port, so the encryption above it never depends on a platform API and can
/// be tested without one.
abstract interface class ArchiveStorage {
  Future<Uint8List?> read();
  Future<void> write(Uint8List bytes);
  Future<void> delete();
}

class InMemoryArchiveStorage implements ArchiveStorage {
  Uint8List? _bytes;

  /// Exposed so a test can assert what actually sits at rest.
  Uint8List? get bytes => _bytes;

  @override
  Future<Uint8List?> read() async => _bytes;

  @override
  Future<void> write(Uint8List bytes) async => _bytes = bytes;

  @override
  Future<void> delete() async => _bytes = null;
}

/// Keeps the archive in the platform keystore.
///
/// The blob is already sealed before it gets here, so the keystore is a second
/// layer rather than the only one. It is the right home while histories are
/// small; a long one belongs in a SQLCipher database, which is what this port
/// exists to make swappable.
class KeystoreArchiveStorage implements ArchiveStorage {
  const KeystoreArchiveStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _key = 'privio.archive.blob';
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  @override
  Future<Uint8List?> read() async {
    final stored = await _storage.read(
      key: _key,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    return stored == null ? null : base64Decode(stored);
  }

  @override
  Future<void> write(Uint8List bytes) => _storage.write(
        key: _key,
        value: base64Encode(bytes),
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  @override
  Future<void> delete() => _storage.delete(
        key: _key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
}

/// The decrypted conversation history, at rest.
abstract interface class MessageArchive {
  Future<List<Conversation>> load();
  Future<void> save(List<Conversation> conversations);
  Future<void> clear();
}

/// Does nothing. Used where persistence is not wanted.
class NoArchive implements MessageArchive {
  const NoArchive();

  @override
  Future<List<Conversation>> load() async => const [];

  @override
  Future<void> save(List<Conversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

/// The conversation history sealed with AES-256-GCM under a key that lives in
/// the platform keystore.
///
/// This is the only readable copy of a conversation on the device, so it is
/// never written in the clear. The cipher is `package:cryptography`'s — Privio
/// implements no primitive of its own here either.
class EncryptedMessageArchive implements MessageArchive {
  EncryptedMessageArchive({
    required ArchiveStorage storage,
    required SecureStore keyStore,
    AesGcm? cipher,
  })  : _storage = storage,
        _keyStore = keyStore,
        _cipher = cipher ?? AesGcm.with256bits();

  final ArchiveStorage _storage;
  final SecureStore _keyStore;
  final AesGcm _cipher;

  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _formatVersion = 1;

  SecretKey? _cachedKey;

  /// Loads the archive key, generating one on first use.
  Future<SecretKey> _key() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final stored = await _keyStore.readArchiveKey();
    if (stored != null) {
      return _cachedKey = SecretKey(base64Decode(stored));
    }
    final generated = await _cipher.newSecretKey();
    await _keyStore.writeArchiveKey(base64Encode(await generated.extractBytes()));
    return _cachedKey = generated;
  }

  @override
  Future<List<Conversation>> load() async {
    final sealed = await _storage.read();
    if (sealed == null || sealed.length < 1 + _nonceLength + _macLength) return const [];
    if (sealed.first != _formatVersion) return const [];

    final nonce = sealed.sublist(1, 1 + _nonceLength);
    final mac = sealed.sublist(sealed.length - _macLength);
    final cipherText = sealed.sublist(1 + _nonceLength, sealed.length - _macLength);

    try {
      final plain = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _key(),
      );
      return _decode(jsonDecode(utf8.decode(plain)) as List<dynamic>);
    } on Object {
      // A wrong key or a tampered blob. Returning an empty history is right:
      // guessing at half-decrypted content would be worse than starting clean.
      return const [];
    }
  }

  @override
  Future<void> save(List<Conversation> conversations) async {
    final plain = utf8.encode(jsonEncode(_encode(conversations)));
    final box = await _cipher.encrypt(plain, secretKey: await _key());
    // version | nonce | ciphertext | mac
    await _storage.write(
      Uint8List.fromList([_formatVersion, ...box.nonce, ...box.cipherText, ...box.mac.bytes]),
    );
  }

  @override
  Future<void> clear() async {
    _cachedKey = null;
    await _storage.delete();
  }

  static List<Map<String, dynamic>> _encode(List<Conversation> conversations) => [
        for (final conversation in conversations)
          {
            'accountId': conversation.user.accountId,
            'username': conversation.user.username,
            'displayName': conversation.user.displayName,
            if (conversation.user.avatarMediaId != null)
              'avatarMediaId': conversation.user.avatarMediaId,
            if (conversation.user.profileKey != null)
              'profileKey': conversation.user.profileKey,
            'unreadCount': conversation.unreadCount,
            'messages': [
              for (final message in conversation.messages)
                {
                  'id': message.id,
                  'body': message.body,
                  'sentAt': message.sentAt.toIso8601String(),
                  'isMine': message.isMine,
                  'kind': message.kind.name,
                  'state': message.state.name,
                  if (message.senderName != null) 'senderName': message.senderName,
                  if (message.attachment != null)
                    'attachment': {
                      'mediaId': message.attachment!.mediaId,
                      'mediaKey': message.attachment!.mediaKey,
                      'mediaType': message.attachment!.mediaType,
                      'byteSize': message.attachment!.byteSize,
                      if (message.attachment!.fileName != null)
                        'fileName': message.attachment!.fileName,
                    },
                },
            ],
          },
      ];

  static Attachment? _decodeAttachment(Map<String, dynamic>? raw) => raw == null
      ? null
      : Attachment(
          mediaId: raw['mediaId'] as String,
          mediaKey: raw['mediaKey'] as String,
          mediaType: raw['mediaType'] as String,
          byteSize: raw['byteSize'] as int,
          fileName: raw['fileName'] as String?,
        );

  static List<Conversation> _decode(List<dynamic> raw) => [
        for (final entry in raw.cast<Map<String, dynamic>>())
          Conversation(
            user: KnownUser(
              accountId: entry['accountId'] as String,
              username: entry['username'] as String,
              displayName: entry['displayName'] as String?,
              avatarMediaId: entry['avatarMediaId'] as String?,
              profileKey: entry['profileKey'] as String?,
            ),
            messages: [
              for (final message in (entry['messages'] as List<dynamic>).cast<Map<String, dynamic>>())
                Message(
                  id: message['id'] as String,
                  body: message['body'] as String,
                  sentAt: DateTime.parse(message['sentAt'] as String),
                  isMine: message['isMine'] as bool,
                  kind: MessageKind.values.byName(message['kind'] as String? ?? 'text'),
                  state: DeliveryState.values.byName(message['state'] as String? ?? 'read'),
                  senderName: message['senderName'] as String?,
                  attachment: _decodeAttachment(message['attachment'] as Map<String, dynamic>?),
                ),
            ],
          )..unreadCount = entry['unreadCount'] as int? ?? 0,
      ];
}
