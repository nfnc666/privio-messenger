import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'crypto_storage.dart';
import 'padding.dart';
import 'privio_signal_store.dart';
import 'safety_number.dart';

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

  /// Not final: a wipe replaces it, because the identity it holds is loaded
  /// once and would otherwise outlive the storage it came from.
  PrivioSignalStore _store;

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

  /// How long a signed prekey is the one on offer before a new one replaces it.
  ///
  /// The signed prekey is what a stranger seals their first message to when the
  /// one-time pool is empty, and it is the same key for everyone until it is
  /// replaced. Two days is the window a stolen one buys an attacker.
  static const Duration signedPreKeyLifetime = Duration(hours: 48);

  /// How long a replaced one is kept.
  ///
  /// Deleting it the moment it is replaced would drop every message already
  /// sealed against it and not yet collected — someone who fetched a bundle,
  /// went into a tunnel, and sent it an hour later.
  static const Duration signedPreKeyGrace = Duration(days: 30);

  /// When the newest signed prekey was generated, or null if there is none.
  Future<DateTime?> newestSignedPreKeyAt() async {
    final records = await _store.loadSignedPreKeys();
    if (records.isEmpty) return null;
    final newest = records
        .map((record) => record.timestamp.toInt())
        .reduce((a, b) => a > b ? a : b);
    return DateTime.fromMillisecondsSinceEpoch(newest);
  }

  /// Whether the signed prekey has been on offer for longer than it should be.
  Future<bool> signedPreKeyIsDue(DateTime now) async {
    final newest = await newestSignedPreKeyAt();
    // No signed prekey at all is overdue by definition, not up to date.
    if (newest == null) return true;
    return now.difference(newest) >= signedPreKeyLifetime;
  }

  /// Deletes signed prekeys past the grace period, never the newest one.
  ///
  /// Returns how many went, so a caller can say nothing happened rather than
  /// claiming it did.
  Future<int> pruneSignedPreKeys(DateTime now) async {
    final records = await _store.loadSignedPreKeys();
    if (records.length < 2) return 0;
    final newestId = records
        .reduce((a, b) => a.timestamp.toInt() >= b.timestamp.toInt() ? a : b)
        .id;

    var removed = 0;
    for (final record in records) {
      if (record.id == newestId) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(record.timestamp.toInt());
      if (now.difference(at) < signedPreKeyGrace) continue;
      await _store.removeSignedPreKey(record.id);
      removed++;
    }
    return removed;
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

  /// Destroys this device's identity and every session with it.
  ///
  /// After this the device is a stranger to everyone it had spoken to, and
  /// nothing that was sealed to the old identity will ever open again. Used by
  /// the duress wipe and by deleting an account.
  ///
  /// A fresh identity is created immediately rather than on the next start.
  /// Clearing the storage alone leaves the old identity loaded in memory, and
  /// an account registered before the next restart would publish a key whose
  /// private half is no longer stored anywhere — an account that works until
  /// the app is closed and can never open a message again after that.
  Future<void> wipe() async {
    final storage = _store.storage;
    await storage.wipe();
    _store = await PrivioSignalStore.create(storage);
  }

  SignalProtocolAddress _address(String accountId, int deviceIndex) =>
      SignalProtocolAddress(accountId, deviceIndex);

  /// Whether a session already exists with that device.
  ///
  /// Checked before fetching a prekey bundle, because fetching one consumes a
  /// one-time prekey from the other side's pool.
  Future<bool> hasSessionWith(String accountId, int deviceIndex) =>
      _store.containsSession(_address(accountId, deviceIndex));

  /// Throws away the session with one device, so the next message sent to it
  /// starts a new one from a fresh prekey bundle.
  ///
  /// The repair for a ratchet that has gone out of step — a peer restored from
  /// a backup, reinstalled, or two devices that once shared a session. Nothing
  /// already sent under the old session can be recovered by this; what it buys
  /// is that the *next* message works, instead of every message from that
  /// device failing forever.
  Future<void> resetSession(String accountId, int deviceIndex) =>
      _store.deleteSession(_address(accountId, deviceIndex));

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

  // --- Safety numbers -------------------------------------------------------

  /// Accounts whose key changed under an incoming message, and the device it
  /// was, drained so each change is reported once.
  ///
  /// A send to a changed key is refused; a *receipt* from one is not, so this
  /// is what stands between "someone else's key is now pinned for your friend"
  /// and the user never hearing about it.
  List<({String accountId, int deviceIndex})> takeIdentityReplacements() {
    final taken = [
      for (final address in _store.replacedIdentities)
        (accountId: address.getName(), deviceIndex: address.getDeviceId()),
    ];
    _store.replacedIdentities.clear();
    return taken;
  }

  /// The numbers to compare with [remoteAccountId], one per device of theirs
  /// this device has pinned, and what the user has already made of them.
  ///
  /// Ordered by device index so the list on two screens reads the same way.
  Future<SafetyNumbers> safetyNumbers({
    required String localAccountId,
    required String remoteAccountId,
  }) async {
    final identity = await _store.getIdentityKeyPair();
    final pinned = await _store.pinnedIdentities(remoteAccountId);
    final indices = pinned.keys.toList()..sort();

    final numbers = [
      for (final index in indices)
        SafetyNumber(
          deviceIndex: index,
          digits: SafetyNumberDigits.between(
            localAccountId: localAccountId,
            localIdentity: identity.getPublicKey(),
            remoteAccountId: remoteAccountId,
            remoteIdentity: pinned[index]!,
          ),
          identityKey: base64Encode(pinned[index]!.serialize()),
        ),
    ];

    final checked = await _store.readVerification(remoteAccountId);
    final state = switch (checked) {
      null => VerificationState.unverified,
      _ => mapEquals(checked, {
          for (final number in numbers) '${number.deviceIndex}': number.identityKey,
        })
          ? VerificationState.verified
          : VerificationState.changed,
    };
    return SafetyNumbers(numbers: numbers, state: state);
  }

  /// Accounts whose key changed and whose owner has not been shown the new
  /// number yet.
  Future<Set<String>> keyChangeAlerts() => _store.keyChangeAlerts();

  Future<void> raiseKeyChangeAlert(String accountId) =>
      _store.raiseKeyChangeAlert(accountId);

  /// Called when the user has been shown the number for that account, which is
  /// the only thing that answers the notice.
  Future<void> clearKeyChangeAlert(String accountId) =>
      _store.clearKeyChangeAlert(accountId);

  /// Records that the user compared these numbers and they matched.
  Future<void> markVerified(String remoteAccountId, SafetyNumbers numbers) =>
      _store.writeVerification(remoteAccountId, numbers.snapshot);

  /// Forgets that anything was ever compared. Not the same as a key changing:
  /// this is the user saying they no longer stand behind the check.
  Future<void> clearVerified(String remoteAccountId) =>
      _store.clearVerification(remoteAccountId);

  /// Accepts a changed identity key: unpins it so the next send re-pins
  /// whatever is on the server now, and drops any verification, because what
  /// was verified is by definition no longer what is there.
  ///
  /// Only ever called from a screen the user is looking at. Doing it
  /// automatically would make [IdentityChangedException] a delay rather than a
  /// question, and the question is the entire point of pinning.
  Future<void> acceptIdentityChange(String accountId, int deviceIndex) async {
    await _store.forgetIdentity(_address(accountId, deviceIndex));
    await _store.clearVerification(accountId);
  }
}
