import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'crypto_storage.dart';
import 'padding.dart';
import 'privio_signal_store.dart';

/// One sealed copy of a message, addressed to a single recipient device.
class SealedCopy {
  const SealedCopy({
    required this.deviceId,
    required this.registrationId,
    required this.type,
    required this.content,
  });

  /// The server's routing id for the device (a UUID).
  final String deviceId;
  final int registrationId;

  /// `prekey` opens a new session; `ciphertext` continues an existing one.
  final String type;

  /// Base64 ciphertext, exactly as it goes on the wire.
  final String content;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'registrationId': registrationId,
        'type': type,
        'content': content,
      };
}

/// A recipient device, as the server describes it.
class DeviceBundle {
  const DeviceBundle({
    required this.deviceId,
    required this.deviceIndex,
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.preKeyId,
    this.preKey,
  });

  factory DeviceBundle.fromJson(Map<String, dynamic> json) {
    final signed = json['signedPreKey'] as Map<String, dynamic>;
    final oneTime = json['oneTimePreKey'] as Map<String, dynamic>?;
    return DeviceBundle(
      deviceId: json['deviceId'] as String,
      deviceIndex: json['deviceIndex'] as int,
      registrationId: json['registrationId'] as int,
      identityKey: base64Decode(json['identityKey'] as String),
      signedPreKeyId: signed['keyId'] as int,
      signedPreKey: base64Decode(signed['publicKey'] as String),
      signedPreKeySignature: base64Decode(signed['signature'] as String),
      preKeyId: oneTime?['keyId'] as int?,
      preKey: oneTime == null ? null : base64Decode(oneTime['publicKey'] as String),
    );
  }

  final String deviceId;
  final int deviceIndex;
  final int registrationId;
  final Uint8List identityKey;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List signedPreKeySignature;
  final int? preKeyId;
  final Uint8List? preKey;

  PreKeyBundle toPreKeyBundle() => PreKeyBundle(
        registrationId,
        deviceIndex,
        preKeyId,
        preKey == null ? null : Curve.decodePoint(preKey!, 0),
        signedPreKeyId,
        Curve.decodePoint(signedPreKey, 0),
        signedPreKeySignature,
        IdentityKey.fromBytes(identityKey, 0),
      );
}

/// Raised when a peer's identity key has changed since it was first pinned.
///
/// This is what a server swapping in its own key looks like from the client, so
/// it is never handled silently — the user has to accept the new safety number.
class IdentityChangedException implements Exception {
  const IdentityChangedException(this.accountId, this.deviceIndex);

  final String accountId;
  final int deviceIndex;

  @override
  String toString() => 'Identity key changed for $accountId.$deviceIndex';
}

/// The client's end-to-end encryption layer.
///
/// Wraps the Signal Protocol — X3DH to agree a key, the Double Ratchet to move
/// it forward — so the rest of the app only ever handles sealed bytes. Nothing
/// here implements a cryptographic primitive; it composes an implementation of
/// the protocol.
///
/// Note on the implementation: `libsignal_protocol_dart` is a pure-Dart port of
/// libsignal, not the official audited Rust build. That is a real difference and
/// it is recorded in docs/security-model.md — the pre-launch target is the
/// official library behind this same interface, which is why every call site
/// goes through this class rather than touching the port directly.
class PrivioCrypto {
  PrivioCrypto(this._store);

  final PrivioSignalStore _store;

  /// How many one-time prekeys a device publishes, and when it tops up. Signal
  /// uses the same shape: a pool large enough that it never empties between
  /// refreshes, because an empty pool costs forward secrecy on new sessions.
  static const int preKeyBatchSize = 100;
  static const int preKeyLowWaterMark = 20;

  /// Opens this device's existing identity, creating one on first run.
  static Future<PrivioCrypto> open(CryptoStorage storage) async {
    final existing = await PrivioSignalStore.open(storage);
    return PrivioCrypto(existing ?? await PrivioSignalStore.create(storage));
  }

  PrivioSignalStore get store => _store;

  /// Generates this device's published key material and returns the payload the
  /// registration and login endpoints expect. Only public halves are returned;
  /// the private halves stay in the keystore.
  Future<Map<String, dynamic>> buildRegistration({
    required String name,
    required String platform,
    int preKeyCount = preKeyBatchSize,
  }) async {
    final identity = await _store.getIdentityKeyPair();
    final signedPreKey = generateSignedPreKey(identity, 1);
    await _store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    final preKeys = await _generatePreKeys(preKeyCount);

    return {
      'name': name,
      'platform': platform,
      'registrationId': await _store.getLocalRegistrationId(),
      'identityKey': base64Encode(identity.getPublicKey().serialize()),
      'signedPreKey': {
        'keyId': signedPreKey.id,
        'publicKey': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
      'oneTimePreKeys': [
        for (final preKey in preKeys)
          {
            'keyId': preKey.id,
            'publicKey': base64Encode(preKey.getKeyPair().publicKey.serialize()),
          },
      ],
    };
  }

  /// Fresh one-time prekeys to publish when the server's pool runs low.
  Future<List<Map<String, dynamic>>> buildPreKeyTopUp({
    int count = preKeyBatchSize,
  }) async {
    final preKeys = await _generatePreKeys(count);
    return [
      for (final preKey in preKeys)
        {
          'keyId': preKey.id,
          'publicKey': base64Encode(preKey.getKeyPair().publicKey.serialize()),
        },
    ];
  }

  Future<List<PreKeyRecord>> _generatePreKeys(int count) async {
    // Ids continue from the highest already issued, so a top-up can never
    // collide with a prekey still sitting on the server.
    final start = await _store.highestPreKeyId() + 1;
    final preKeys = generatePreKeys(start, count);
    for (final preKey in preKeys) {
      await _store.storePreKey(preKey.id, preKey);
    }
    return preKeys;
  }

  /// Rotates the signed prekey. Clients do this on a schedule so a compromised
  /// signed prekey only exposes a bounded window.
  Future<Map<String, dynamic>> rotateSignedPreKey() async {
    final identity = await _store.getIdentityKeyPair();
    final existing = await _store.loadSignedPreKeys();
    final nextId = existing.fold<int>(0, (max, r) => r.id > max ? r.id : max) + 1;
    final signedPreKey = generateSignedPreKey(identity, nextId);
    await _store.storeSignedPreKey(signedPreKey.id, signedPreKey);
    return {
      'keyId': signedPreKey.id,
      'publicKey': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signature': base64Encode(signedPreKey.signature),
    };
  }

  SignalProtocolAddress _address(String accountId, int deviceIndex) =>
      SignalProtocolAddress(accountId, deviceIndex);

  /// Whether a session already exists with that device.
  ///
  /// Checked before fetching a prekey bundle, because fetching one consumes a
  /// one-time prekey from the other side's pool.
  Future<bool> hasSessionWith(String accountId, int deviceIndex) =>
      _store.containsSession(_address(accountId, deviceIndex));

  /// Opens a session from a server-issued prekey bundle. Safe to call when a
  /// session already exists — it is a no-op then.
  Future<void> ensureSession(String accountId, DeviceBundle bundle) async {
    final address = _address(accountId, bundle.deviceIndex);
    if (await _store.containsSession(address)) return;
    final builder = SessionBuilder.fromSignalStore(_store, address);
    try {
      await builder.processPreKeyBundle(bundle.toPreKeyBundle());
    } on UntrustedIdentityException {
      throw IdentityChangedException(accountId, bundle.deviceIndex);
    }
  }

  /// Seals [plaintext] for one device. The session must already exist.
  Future<SealedCopy> seal({
    required String accountId,
    required String deviceId,
    required int deviceIndex,
    required int registrationId,
    required String plaintext,
  }) async {
    final address = _address(accountId, deviceIndex);
    final cipher = SessionCipher.fromStore(_store, address);
    final CiphertextMessage message;
    try {
      // Padded before sealing, so the ciphertext length says nothing about how
      // much was written.
      message = await cipher.encrypt(MessagePadding.pad(utf8.encode(plaintext)));
    } on UntrustedIdentityException {
      throw IdentityChangedException(accountId, deviceIndex);
    }
    return SealedCopy(
      deviceId: deviceId,
      registrationId: registrationId,
      type: message.getType() == CiphertextMessage.prekeyType ? 'prekey' : 'ciphertext',
      content: base64Encode(message.serialize()),
    );
  }

  /// Seals one copy per recipient device, opening sessions as needed.
  Future<List<SealedCopy>> sealForDevices({
    required String accountId,
    required List<DeviceBundle> devices,
    required String plaintext,
  }) async {
    final sealed = <SealedCopy>[];
    for (final device in devices) {
      await ensureSession(accountId, device);
      sealed.add(
        await seal(
          accountId: accountId,
          deviceId: device.deviceId,
          deviceIndex: device.deviceIndex,
          registrationId: device.registrationId,
          plaintext: plaintext,
        ),
      );
    }
    return sealed;
  }

  /// Decrypts one envelope from the queue.
  ///
  /// A `prekey` envelope also establishes the session and consumes the one-time
  /// prekey it used, which is why the store deletes it rather than keeping it.
  Future<String> openEnvelope({
    required String senderAccountId,
    required int senderDeviceIndex,
    required String type,
    required String content,
  }) async {
    final address = _address(senderAccountId, senderDeviceIndex);
    final cipher = SessionCipher.fromStore(_store, address);
    final bytes = Uint8List.fromList(base64Decode(content));

    final plaintext = switch (type) {
      'prekey' => await cipher.decrypt(PreKeySignalMessage(bytes)),
      'ciphertext' => await cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes)),
      _ => throw ArgumentError.value(type, 'type', 'Not a decryptable envelope'),
    };
    return utf8.decode(MessagePadding.unpad(plaintext));
  }

  /// True when the published pool has run down far enough to warrant a top-up.
  bool needsPreKeyTopUp(int remainingOnServer) => remainingOnServer <= preKeyLowWaterMark;

  /// The key this account's profile picture is sealed with.
  ///
  /// Long-lived and shared with contacts inside end-to-end encrypted messages —
  /// never with the server, which therefore holds an avatar it cannot open.
  /// Generated once, on first use.
  Future<Uint8List> profileKey() async {
    final existing = await _store.readProfileKey();
    if (existing != null) return existing;
    final generated = generateRandomBytes();
    await _store.writeProfileKey(generated);
    return generated;
  }

  /// This device's identity fingerprint, for the safety-number screen.
  Future<String> identityFingerprint() async {
    final identity = await _store.getIdentityKeyPair();
    return base64Encode(identity.getPublicKey().serialize());
  }
}
