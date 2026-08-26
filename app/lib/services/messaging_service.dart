import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../crypto/privio_crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../data/message_store.dart';
import '../media/attachment.dart';
import '../media/metadata_scrubber.dart';

/// A decrypted incoming message, with the routing facts that came with it.
class IncomingMessage {
  const IncomingMessage({
    required this.envelopeId,
    required this.senderAccountId,
    required this.payload,
    required this.receivedAt,
    this.groupId,
  });

  final int envelopeId;
  final String senderAccountId;

  /// Text or an attachment pointer — the server cannot tell which.
  final MessagePayload payload;

  final DateTime receivedAt;
  final String? groupId;

  String get body => payload.body;
}

/// An envelope that could not be decrypted.
///
/// Surfaced rather than swallowed: a message that will not open is a fact the
/// user needs, whether it means a lost session or a tampered envelope.
class UndecryptableMessage {
  const UndecryptableMessage(this.envelopeId, this.senderAccountId, this.reason);

  final int envelopeId;
  final String? senderAccountId;
  final Object reason;
}

class ReceiveResult {
  const ReceiveResult(
    this.messages,
    this.failures,
    this.more, {
    this.highestHandled = 0,
  });

  final List<IncomingMessage> messages;
  final List<UndecryptableMessage> failures;

  /// True when the queue held more than one batch.
  final bool more;

  /// The highest envelope id that was processed, acknowledged or not. Zero when
  /// nothing was.
  final int highestHandled;
}

/// Joins the transport to the crypto layer.
///
/// This is the only place that turns text into ciphertext and back, so nothing
/// above it ever holds a key and nothing below it ever sees plaintext.
class MessagingService {
  MessagingService({required PrivioApiClient api, required PrivioCrypto crypto})
      : _api = api,
        _crypto = crypto;

  final PrivioApiClient _api;
  final PrivioCrypto _crypto;

  /// Seals [plaintext] for every device [username] has, and sends it.
  ///
  /// A `device_mismatch` means the recipient added or removed a device between
  /// the bundle fetch and the send. The fix is to fetch again and re-seal —
  /// once. A second mismatch is not a race, it is a bug or an attack, and it
  /// propagates rather than looping.
  Future<int> sendToUser(String username, String plaintext) =>
      sendPayload(username, MessagePayload.text(plaintext));

  Future<int> sendPayload(String username, MessagePayload payload) async {
    final encoded = (await _withProfileKey(payload)).encode();
    try {
      return await _sealAndSend(username, encoded);
    } on ApiException catch (error) {
      if (error.code != 'device_mismatch') rethrow;
      return _sealAndSend(username, encoded);
    }
  }

  /// Sends a file: strips its metadata, pads it, seals it under its own key,
  /// uploads the ciphertext, and sends the key inside the encrypted message.
  ///
  /// Returns what was stripped, so the UI can tell the user rather than leaving
  /// them to assume.
  Future<ScrubReport> sendAttachment(
    String username, {
    required Uint8List file,
    String? fileName,
    String? declaredType,
    String caption = '',
  }) async {
    final sealed = await AttachmentCipher.seal(file, declaredType: declaredType);
    final mediaId = await _api.uploadMedia(sealed.bytes);

    await sendPayload(
      username,
      MessagePayload.media(
        mediaId: mediaId,
        mediaKey: base64Encode(sealed.key),
        mediaType: sealed.report.mediaType,
        byteSize: sealed.plainLength,
        fileName: fileName,
        body: caption,
      ),
    );
    return sealed.report;
  }

  /// Attaches this account's profile key, which is how contacts become able to
  /// open its profile picture without the server ever learning the key.
  Future<MessagePayload> _withProfileKey(MessagePayload payload) async {
    // A key delivery carries no profile key and no body; rebuilding it as text
    // would quietly throw the key away.
    if (payload.isKeyDelivery || payload.profileKey != null) return payload;
    final key = base64Encode(await _crypto.profileKey());
    return payload.isMedia
        ? MessagePayload.media(
            mediaId: payload.mediaId!,
            mediaKey: payload.mediaKey!,
            mediaType: payload.mediaType!,
            byteSize: payload.byteSize!,
            fileName: payload.fileName,
            body: payload.body,
            profileKey: key,
            groupKey: payload.groupKey,
          )
        : MessagePayload.text(payload.body, profileKey: key, groupKey: payload.groupKey);
  }

  /// Seals a profile picture under this account's profile key and uploads it.
  ///
  /// Same pipeline as any attachment, with one difference that matters: the key
  /// is the long-lived profile key rather than a fresh one, because every
  /// contact has to be able to open the same picture.
  Future<String> uploadAvatar(Uint8List image) async {
    final sealed = await AttachmentCipher.sealWithKey(
      image,
      key: await _crypto.profileKey(),
      declaredType: 'image/jpeg',
    );
    final mediaId = await _api.uploadMedia(sealed);
    await _api.setAvatar(mediaId);
    return mediaId;
  }

  /// Opens someone's profile picture, given the profile key they sent.
  Future<Uint8List> openAvatar(String mediaId, Uint8List profileKey) async {
    final sealed = await _api.downloadMedia(mediaId);
    return AttachmentCipher.open(Uint8List.fromList(sealed), profileKey);
  }

  /// Downloads and opens an attachment a message points at.
  Future<Uint8List> openAttachment(MessagePayload payload) async {
    if (!payload.isMedia) {
      throw ArgumentError.value(payload, 'payload', 'Not an attachment');
    }
    final sealed = await _api.downloadMedia(payload.mediaId!);
    return AttachmentCipher.open(
      Uint8List.fromList(sealed),
      base64Decode(payload.mediaKey!),
    );
  }

  Future<int> _sealAndSend(String username, String plaintext) async {
    final response = await _api.preKeyBundles(username);
    final accountId = response['accountId'] as String;
    final devices = [
      for (final device in response['devices'] as List<dynamic>)
        DeviceBundle.fromJson(device as Map<String, dynamic>),
    ];

    final sealed = await _crypto.sealForDevices(
      accountId: accountId,
      devices: devices,
      plaintext: plaintext,
    );
    final result = await _api.sendMessage(
      username: username,
      messages: [for (final copy in sealed) copy.toJson()],
    );
    return result['deliveredTo'] as int? ?? sealed.length;
  }

  /// Hands a channel or group key to everyone's devices for one account.
  ///
  /// The request that prompted this comes from a single device, but the key
  /// belongs to the account's membership, so every device of theirs gets it:
  /// otherwise their phone could read the channel and their laptop could not.
  Future<void> deliverKey({
    required String username,
    required String scope,
    required String scopeId,
    required String base64Key,
  }) =>
      sendPayload(
        username,
        MessagePayload.key(keyScope: scope, keyScopeId: scopeId, deliveredKey: base64Key),
      );

  /// Drains the queue, decrypts, and acknowledges only what was handled.
  ///
  /// The acknowledgement is deliberately last: an envelope stays on the server
  /// until this device has actually opened it, so a crash mid-batch costs a
  /// redelivery rather than a lost message.
  Future<ReceiveResult> receive({int limit = 100}) async {
    final response = await _api.fetchEnvelopes(limit: limit);
    final envelopes = response['envelopes'] as List<dynamic>;
    final result = await decryptEnvelopes(
      envelopes,
      more: response['more'] as bool? ?? false,
    );
    if (result.highestHandled > 0) await _api.acknowledge(result.highestHandled);
    return result;
  }

  /// Decrypts a batch of envelopes without acknowledging them.
  ///
  /// Split out because envelopes arrive two ways — pulled over HTTP, or pushed
  /// down the realtime socket — and only the acknowledgement differs. The
  /// caller acknowledges on whichever channel delivered them, and only after
  /// this has returned.
  Future<ReceiveResult> decryptEnvelopes(
    List<dynamic> envelopes, {
    bool more = false,
  }) async {
    if (envelopes.isEmpty) return const ReceiveResult([], [], false);

    final messages = <IncomingMessage>[];
    final failures = <UndecryptableMessage>[];
    var highestHandled = 0;

    for (final raw in envelopes) {
      final envelope = raw as Map<String, dynamic>;
      final envelopeId = envelope['id'] as int;
      final type = envelope['type'] as String;
      final senderAccountId = envelope['senderAccountId'] as String?;
      final senderDeviceIndex = envelope['senderDeviceIndex'] as int?;

      if (type != 'prekey' && type != 'ciphertext') {
        // Receipts, typing and control envelopes are handled elsewhere; they
        // still count as processed so the queue drains.
        highestHandled = envelopeId;
        continue;
      }

      if (senderAccountId == null || senderDeviceIndex == null) {
        failures.add(
          UndecryptableMessage(
            envelopeId,
            senderAccountId,
            StateError('Envelope has no identifiable sender device'),
          ),
        );
        highestHandled = envelopeId;
        continue;
      }

      try {
        final body = await _crypto.openEnvelope(
          senderAccountId: senderAccountId,
          senderDeviceIndex: senderDeviceIndex,
          type: type,
          content: envelope['content'] as String,
        );
        messages.add(
          IncomingMessage(
            envelopeId: envelopeId,
            senderAccountId: senderAccountId,
            payload: MessagePayload.decode(body),
            receivedAt: DateTime.parse(envelope['createdAt'] as String),
            groupId: envelope['groupId'] as String?,
          ),
        );
      } on Object catch (error) {
        // Retrying will not help — the same bytes will fail the same way — so
        // acknowledge it and report it rather than blocking the queue forever.
        failures.add(UndecryptableMessage(envelopeId, senderAccountId, error));
      }
      highestHandled = envelopeId;
    }

    return ReceiveResult(messages, failures, more, highestHandled: highestHandled);
  }

  // --- Groups ---------------------------------------------------------------

  /// Creates a group with a sealed name.
  ///
  /// The name is encrypted with a fresh group key before it is uploaded, so the
  /// server stores a group it cannot name. The key then reaches members on the
  /// group's messages.
  Future<GroupInfo> createGroup(String name, List<String> memberIds) async {
    final key = await AesGcm.with256bits().newSecretKey();
    final keyBytes = Uint8List.fromList(await key.extractBytes());

    final created = await _api.createGroup(
      memberIds: memberIds,
      encryptedMetadata: base64Encode(await _sealGroupName(name, keyBytes)),
    );

    return GroupInfo(
      groupId: created['id'] as String,
      role: 'admin',
      name: name,
      groupKey: base64Encode(keyBytes),
      inviteCode: created['inviteCode'] as String?,
      memberIds: [
        for (final member in created['members'] as List<dynamic>)
          (member as Map<String, dynamic>)['id'] as String,
      ],
    );
  }

  /// The groups this account belongs to, with names opened where the key for
  /// them is already known.
  Future<List<GroupInfo>> listGroups(MessageStore store) async {
    final response = await _api.groups();
    final groups = <GroupInfo>[];

    // A missing key is not a crash: the network boundary is exactly where a
    // surprise should be absorbed rather than propagated into the UI.
    for (final raw in response['groups'] as List<dynamic>? ?? const []) {
      final entry = raw as Map<String, dynamic>;
      final groupId = entry['id'] as String;
      final knownKey = store.conversationWith(groupId)?.group?.groupKey;
      final sealed = entry['encryptedMetadata'] as String?;

      groups.add(
        GroupInfo(
          groupId: groupId,
          role: entry['role'] as String,
          groupKey: knownKey,
          inviteCode: entry['inviteCode'] as String?,
          name: knownKey == null || sealed == null
              ? null
              : await _openGroupName(sealed, knownKey),
        ),
      );
    }
    return groups;
  }

  /// Joins a group with the code from its link.
  ///
  /// The link carries no key, so the group's name stays sealed until a member
  /// delivers it — the same handshake channels use.
  Future<GroupInfo> joinGroupByCode(String code) async {
    final found = await _api.groupByInvite(code);
    final groupId = found['id'] as String;
    await _api.joinGroup(groupId, code);
    return GroupInfo(groupId: groupId, role: 'member', inviteCode: code);
  }

  /// Answers everyone waiting for a group's name key. Returns how many accounts
  /// were served.
  Future<int> deliverGroupKeys(String groupId, String base64Key) async {
    final response = await _api.groupKeyRequests(groupId);
    final requests = [
      for (final raw in response['requests'] as List<dynamic>? ?? const [])
        raw as Map<String, dynamic>,
    ];
    if (requests.isEmpty) return 0;

    final byUsername = <String, List<String>>{};
    for (final request in requests) {
      byUsername
          .putIfAbsent(request['username'] as String, () => [])
          .add(request['deviceId'] as String);
    }

    var served = 0;
    for (final entry in byUsername.entries) {
      try {
        await deliverKey(
          username: entry.key,
          scope: 'group',
          scopeId: groupId,
          base64Key: base64Key,
        );
        for (final deviceId in entry.value) {
          await _api.clearGroupKeyRequest(groupId, deviceId);
        }
        served++;
      } on Object {
        // Retried on the next refresh rather than blocking the others.
        continue;
      }
    }
    return served;
  }

  /// Seals [plaintext] once per member device and posts it to the group.
  ///
  /// There is no group-wide message key: every device gets its own Signal
  /// ciphertext, so removing a member removes their ability to read what comes
  /// after, without re-keying anything.
  Future<int> sendToGroup(String groupId, String plaintext, {String? groupKey}) async {
    final payload = await _withProfileKey(
      MessagePayload.text(plaintext, groupKey: groupKey),
    );
    final encoded = payload.encode();

    final devices = await _api.groupDevices(groupId);
    final targets = [
      for (final raw in devices['devices'] as List<dynamic>? ?? const [])
        raw as Map<String, dynamic>,
    ];
    if (targets.isEmpty) return 0;

    // Open sessions only where one is missing. Fetching a prekey bundle
    // consumes a one-time prekey, so doing it per send would drain the pool for
    // no reason — most group sends already have a session for every device.
    final needBundles = <String>{};
    for (final device in targets) {
      final hasSession = await _crypto.hasSessionWith(
        device['accountId'] as String,
        device['deviceIndex'] as int,
      );
      if (!hasSession) needBundles.add(device['username'] as String);
    }
    for (final username in needBundles) {
      final response = await _api.preKeyBundles(username);
      final accountId = response['accountId'] as String;
      for (final raw in response['devices'] as List<dynamic>) {
        await _crypto.ensureSession(
          accountId,
          DeviceBundle.fromJson(raw as Map<String, dynamic>),
        );
      }
    }

    final sealed = <Map<String, dynamic>>[];
    for (final device in targets) {
      final copy = await _crypto.seal(
        accountId: device['accountId'] as String,
        deviceId: device['deviceId'] as String,
        deviceIndex: device['deviceIndex'] as int,
        registrationId: device['registrationId'] as int,
        plaintext: encoded,
      );
      sealed.add(copy.toJson());
    }

    final result = await _api.sendGroupMessage(groupId: groupId, messages: sealed);
    return result['deliveredTo'] as int? ?? sealed.length;
  }

  static final AesGcm _groupCipher = AesGcm.with256bits();

  static Future<Uint8List> _sealGroupName(String name, Uint8List key) async {
    final box = await _groupCipher.encrypt(utf8.encode(name), secretKey: SecretKey(key));
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String?> _openGroupName(String sealed, String base64Key) async {
    try {
      final bytes = base64Decode(sealed);
      final macLength = _groupCipher.macAlgorithm.macLength;
      final plain = await _groupCipher.decrypt(
        SecretBox(
          bytes.sublist(12, bytes.length - macLength),
          nonce: bytes.sublist(0, 12),
          mac: Mac(bytes.sublist(bytes.length - macLength)),
        ),
        secretKey: SecretKey(base64Decode(base64Key)),
      );
      return utf8.decode(plain);
    } on Object {
      // A name we cannot open is not a reason to hide the group.
      return null;
    }
  }

  /// Republishes one-time prekeys when the server's pool runs low.
  ///
  /// Left to run down, new conversations fall back to the signed prekey alone,
  /// which costs forward secrecy — so this runs on every app start.
  Future<int> maintainPreKeys() async {
    final remaining = await _api.preKeyCount();
    if (!_crypto.needsPreKeyTopUp(remaining)) return remaining;
    final keys = await _crypto.buildPreKeyTopUp(
      count: PrivioCrypto.preKeyBatchSize - remaining,
    );
    await _api.uploadPreKeys(keys);
    return remaining + keys.length;
  }
}
