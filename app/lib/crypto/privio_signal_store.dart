import 'package:flutter/foundation.dart';
import 'dart:convert';

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
  static const _verifiedPrefix = 'verified/';
  static const _keyChangePrefix = 'keychange/';
  static const _profileKeyKey = 'profile_key';
  static const _channelKeyPrefix = 'channel_key/';

  Future<Uint8List?> readProfileKey() async {
    final stored = await _storage.readBytes(_profileKeyKey);
    return stored == null ? null : Uint8List.fromList(stored);
  }

  Future<void> writeProfileKey(Uint8List key) => _storage.writeBytes(_profileKeyKey, key);

  /// A channel's key for one version of it. Losing it means those posts stay
  /// sealed; there is no copy on the server to fall back on.
  ///
  /// Kept per epoch rather than per channel, because a member who was here
  /// before a removal holds several: the old ones open the posts they could
  /// always read, and the current one opens what is published now. Dropping the
  /// old ones on rotation would take away history from the people the rotation
  /// was meant to protect.
  Future<Uint8List?> readChannelKey(String channelId, int epoch) async {
    final stored = await _storage.readBytes(_epochKey(channelId, epoch));
    if (stored != null) return Uint8List.fromList(stored);
    // Written before keys were versioned: one key, no epoch in the name. It is
    // epoch 1 by definition — every post that existed then was sealed with it —
    // so it is moved into place rather than lost.
    if (epoch != 1) return null;
    final legacy = await _storage.readBytes('$_channelKeyPrefix$channelId');
    if (legacy == null) return null;
    final key = Uint8List.fromList(legacy);
    await writeChannelKey(channelId, 1, key);
    await _storage.delete('$_channelKeyPrefix$channelId');
    return key;
  }

  Future<void> writeChannelKey(String channelId, int epoch, Uint8List key) =>
      _storage.writeBytes(_epochKey(channelId, epoch), key);

  /// Which versions of this channel's key are on this device, oldest first.
  Future<List<int>> channelKeyEpochs(String channelId, {int upTo = 512}) async {
    final held = <int>[];
    for (var epoch = 1; epoch <= upTo; epoch++) {
      if (await _storage.readBytes(_epochKey(channelId, epoch)) != null) held.add(epoch);
    }
    // The legacy key counts as epoch 1 whether or not it has been moved yet.
    if (!held.contains(1) && await _storage.readBytes('$_channelKeyPrefix$channelId') != null) {
      held.insert(0, 1);
    }
    return held;
  }

  /// Forgets every version. Leaving a channel is not a way to keep reading it.
  Future<void> deleteChannelKey(String channelId, {int upTo = 512}) async {
    await _storage.delete('$_channelKeyPrefix$channelId');
    for (var epoch = 1; epoch <= upTo; epoch++) {
      await _storage.delete(_epochKey(channelId, epoch));
    }
  }

  String _epochKey(String channelId, int epoch) => '$_channelKeyPrefix$channelId/$epoch';

  /// Writes a key the way versions of this app before epochs did.
  ///
  /// Only a test has a reason to create that state deliberately; every real
  /// device that has it got there by being installed before rotation existed,
  /// and the migration in [readChannelKey] is what it meets. The annotation
  /// sits on `ChannelService.writeLegacyKey`, which is the way in.
  Future<void> writeLegacyChannelKey(String channelId, Uint8List key) =>
      _storage.writeBytes('$_channelKeyPrefix$channelId', key);

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
    final replaced = existing != null && existing != identityKey;
    // The protocol calls this from inside decryption and discards the answer,
    // so it is recorded here instead. A replacement on the *receiving* side is
    // accepted — refusing it would let anyone lock a conversation by sending
    // one message — which makes saying so afterwards the only defence there is.
    if (replaced) replacedIdentities.add(address);
    return replaced;
  }

  /// Addresses whose pinned identity key was replaced by an incoming message,
  /// since the last time anything drained this. See [saveIdentity].
  final List<SignalProtocolAddress> replacedIdentities = [];

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

  /// Every device of [accountId] whose identity key this device has pinned,
  /// by device index.
  ///
  /// These are exactly the devices that can open what is sent to that account,
  /// which is what makes them the right list to show on the safety-number
  /// screen: a device missing from here cannot read, and a device here that
  /// the user does not recognise is the thing worth catching.
  Future<Map<int, IdentityKey>> pinnedIdentities(String accountId) async {
    final entries = await _storage.readPrefixed('$_trustedPrefix$accountId.');
    final found = <int, IdentityKey>{};
    for (final entry in entries.entries) {
      final index = int.tryParse(entry.key.split('.').last);
      if (index == null) continue;
      found[index] = IdentityKey.fromBytes(base64Decode(entry.value), 0);
    }
    return found;
  }

  /// What the user compared, the last time they compared anything: device
  /// index to the identity key that was on screen at that moment.
  ///
  /// Stored as the keys themselves rather than a "verified" flag, so the
  /// answer to "is this still the thing I checked?" is a comparison rather
  /// than a promise. A key that changes, or a device that appears, breaks it
  /// without anything having to remember to clear a flag.
  Future<Map<String, String>?> readVerification(String accountId) async {
    final stored = await _storage.read('$_verifiedPrefix$accountId');
    if (stored == null) return null;
    final decoded = jsonDecode(stored);
    if (decoded is! Map<String, dynamic>) return null;
    return {for (final e in decoded.entries) e.key: e.value as String};
  }

  Future<void> writeVerification(String accountId, Map<String, String> keys) =>
      _storage.write('$_verifiedPrefix$accountId', jsonEncode(keys));

  Future<void> clearVerification(String accountId) =>
      _storage.delete('$_verifiedPrefix$accountId');

  /// Accounts with an unread "their key changed" notice.
  ///
  /// Persisted rather than held in memory: a notice the user has not seen yet
  /// must not be lost by closing the app, which is exactly when someone would
  /// miss it.
  Future<Set<String>> keyChangeAlerts() async {
    final entries = await _storage.readPrefixed(_keyChangePrefix);
    return {for (final key in entries.keys) key.substring(_keyChangePrefix.length)};
  }

  Future<void> raiseKeyChangeAlert(String accountId) =>
      _storage.write('$_keyChangePrefix$accountId', DateTime.now().toIso8601String());

  Future<void> clearKeyChangeAlert(String accountId) =>
      _storage.delete('$_keyChangePrefix$accountId');

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
