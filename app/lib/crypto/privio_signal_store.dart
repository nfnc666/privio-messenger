import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'crypto_storage.dart';

/// The Signal protocol's persistent state, backed by [CryptoStorage].
///
/// Holds this device's identity key pair, its prekeys, the ratchet state of
/// every session, and the identity keys of everyone talked to. Losing it means
/// losing the ability to read anything already received; leaking it is
/// equivalent to leaking the conversations, which is why it lives in the
/// platform keystore.
class PrivioSignalStore extends SignalProtocolStore {
  PrivioSignalStore(this._storage, this._identity, this._registrationId);

  /// Loads an existing identity, or returns null when this device has none yet.
  static Future<PrivioSignalStore?> open(CryptoStorage storage) async {
    final serialised = await storage.readBytes(_identityKey);
    final registrationId = await storage.read(_registrationIdKey);
    if (serialised == null || registrationId == null) return null;
    return PrivioSignalStore(
      storage,
      IdentityKeyPair.fromSerialized(Uint8List.fromList(serialised)),
      int.parse(registrationId),
    );
  }

  /// Creates and persists a brand-new device identity.
  static Future<PrivioSignalStore> create(CryptoStorage storage) async {
    final identity = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    await storage.writeBytes(_identityKey, identity.serialize());
    await storage.write(_registrationIdKey, '$registrationId');
    return PrivioSignalStore(storage, identity, registrationId);
  }

  /// The backing store, so a wipe can reach it. Nothing else should read
  /// through this: the point of the store is that key material has one home.
  CryptoStorage get storage => _storage;

  final CryptoStorage _storage;
  final IdentityKeyPair _identity;
  final int _registrationId;

  static const _identityKey = 'identity';
  static const _registrationIdKey = 'registration_id';
  static const _sessionPrefix = 'session/';
  static const _preKeyPrefix = 'prekey/';
  static const _signedPreKeyPrefix = 'signed_prekey/';
  static const _trustedPrefix = 'trusted/';
  static const _profileKeyKey = 'profile_key';
  static const _channelKeyPrefix = 'channel_key/';

  Future<Uint8List?> readProfileKey() async {
    final stored = await _storage.readBytes(_profileKeyKey);
    return stored == null ? null : Uint8List.fromList(stored);
  }

  Future<void> writeProfileKey(Uint8List key) => _storage.writeBytes(_profileKeyKey, key);

  /// A channel's key, kept per channel. Losing it means the posts stay sealed;
  /// there is no copy on the server to fall back on.
  Future<Uint8List?> readChannelKey(String channelId) async {
    final stored = await _storage.readBytes('$_channelKeyPrefix$channelId');
    return stored == null ? null : Uint8List.fromList(stored);
  }

  Future<void> writeChannelKey(String channelId, Uint8List key) =>
      _storage.writeBytes('$_channelKeyPrefix$channelId', key);

  Future<void> deleteChannelKey(String channelId) =>
      _storage.delete('$_channelKeyPrefix$channelId');

  String _addressKey(String prefix, SignalProtocolAddress address) =>
      '$prefix${address.getName()}.${address.getDeviceId()}';

  // --- Identity -------------------------------------------------------------

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identity;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final stored = await _storage.readBytes(_addressKey(_trustedPrefix, address));
    return stored == null ? null : IdentityKey.fromBytes(Uint8List.fromList(stored), 0);
  }

  /// Returns true when this replaces a *different* key that was already
  /// trusted — the caller surfaces that as a safety-number change.
  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    final existing = await getIdentity(address);
    await _storage.writeBytes(_addressKey(_trustedPrefix, address), identityKey.serialize());
    return existing != null && existing != identityKey;
  }

  /// Trust on first use, then pinned.
  ///
  /// A key that changes after first contact is rejected on send, so a server
  /// that swaps in its own key cannot silently read the conversation: the user
  /// has to accept the change first. Incoming messages are accepted so a peer
  /// who reinstalled can still reach you, and the UI raises the change.
  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    final known = await getIdentity(address);
    if (known == null) return true;
    if (known == identityKey) return true;
    return direction == Direction.receiving;
  }

  /// Drops a pinned identity so the next message re-pins it. Call this only
  /// after the user has accepted the change.
  Future<void> forgetIdentity(SignalProtocolAddress address) =>
      _storage.delete(_addressKey(_trustedPrefix, address));

  // --- Sessions -------------------------------------------------------------

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final stored = await _storage.readBytes(_addressKey(_sessionPrefix, address));
    // A missing session is not an error: it is a conversation that has not
    // started yet, and the builder fills it in.
    return stored == null
        ? SessionRecord()
        : SessionRecord.fromSerialized(Uint8List.fromList(stored));
  }

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) =>
      _storage.writeBytes(_addressKey(_sessionPrefix, address), record.serialize());

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _storage.read(_addressKey(_sessionPrefix, address)) != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _storage.delete(_addressKey(_sessionPrefix, address));

  @override
  Future<void> deleteAllSessions(String name) async {
    final sessions = await _storage.readPrefixed('$_sessionPrefix$name.');
    for (final key in sessions.keys) {
      await _storage.delete(key);
    }
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final sessions = await _storage.readPrefixed('$_sessionPrefix$name.');
    return [
      for (final key in sessions.keys)
        if (int.tryParse(key.split('.').last) case final int deviceId) deviceId,
    ];
  }

  // --- One-time prekeys -----------------------------------------------------

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final stored = await _storage.readBytes('$_preKeyPrefix$preKeyId');
    if (stored == null) throw InvalidKeyIdException('No prekey $preKeyId');
    return PreKeyRecord.fromBuffer(Uint8List.fromList(stored));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _storage.writeBytes('$_preKeyPrefix$preKeyId', record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      await _storage.read('$_preKeyPrefix$preKeyId') != null;

  /// Called once the prekey has been used. Reusing one would break forward
  /// secrecy for that session, so this deletion is not optional.
  @override
  Future<void> removePreKey(int preKeyId) => _storage.delete('$_preKeyPrefix$preKeyId');

  Future<int> countPreKeys() async =>
      (await _storage.readPrefixed(_preKeyPrefix)).length;

  /// The highest prekey id issued so far, so a top-up never reuses an id.
  Future<int> highestPreKeyId() async {
    final keys = await _storage.readPrefixed(_preKeyPrefix);
    var highest = 0;
    for (final key in keys.keys) {
      final id = int.tryParse(key.substring(_preKeyPrefix.length)) ?? 0;
      if (id > highest) highest = id;
    }
    return highest;
  }

  // --- Signed prekey --------------------------------------------------------

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final stored = await _storage.readBytes('$_signedPreKeyPrefix$signedPreKeyId');
    if (stored == null) throw InvalidKeyIdException('No signed prekey $signedPreKeyId');
    return SignedPreKeyRecord.fromSerialized(Uint8List.fromList(stored));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final stored = await _storage.readPrefixed(_signedPreKeyPrefix);
    return [
      for (final value in stored.values)
        SignedPreKeyRecord.fromSerialized(Uint8List.fromList(base64Decode(value))),
    ];
  }

  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) =>
      _storage.writeBytes('$_signedPreKeyPrefix$signedPreKeyId', record.serialize());

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      await _storage.read('$_signedPreKeyPrefix$signedPreKeyId') != null;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) =>
      _storage.delete('$_signedPreKeyPrefix$signedPreKeyId');
}
