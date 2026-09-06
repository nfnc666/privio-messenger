import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../crypto/privio_crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../data/message_store.dart';
import '../media/attachment.dart';
import '../media/voice.dart';
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

/// What a send of a file yields: the scrub report, and the pointer the sender
/// needs to render its own bubble without asking anyone.
typedef SentAttachment = ({
  ScrubReport report,
  String mediaId,
  String mediaKey,
  String? mediaToken,
  String mediaType,
  int byteSize,
  String? fileName,
});

/// An envelope that could not be decrypted.
///
/// Surfaced rather than swallowed: a message that will not open is a fact the
/// user needs, whether it means a lost session or a tampered envelope.
/// An envelope that arrived and could not be opened.
///
/// Carries where it came from as well as why: a message that cannot be read is
/// still a message somebody sent, and the conversation it belongs to is the one
/// place a hole in the transcript can honestly be shown. The device index is
/// what a session reset needs — the session that broke is with one device, not
/// with an account.
class UndecryptableMessage {
  const UndecryptableMessage(
    this.envelopeId,
    this.senderAccountId,
    this.reason, {
    this.senderDeviceIndex,
    this.groupId,
  });

  final int envelopeId;
  final String? senderAccountId;
  final int? senderDeviceIndex;
  final String? groupId;
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

  /// The highest envelope id this device has already decrypted.
  ///
  /// Envelopes reach the app twice by design: the socket pushes one, and the
  /// fallback poll fetches whatever is still unacknowledged, which includes
  /// the envelope currently being decrypted. The ratchet refuses the second
  /// copy — correctly, it cannot tell a redelivery from a replay — and the
  /// user would be told a message they can plainly read did not decrypt. So
  /// the redelivery is dropped here instead, before it reaches the ratchet.
  int _handledThrough = 0;

  /// Serialises the two delivery paths. Decryption moves the ratchet forward,
  /// so two batches must never be inside it at once, whichever channel they
  /// arrived on.
  Future<void> _decrypting = Future<void>.value();

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
    // The payload's own client id doubles as the send's idempotency key: a
    // retry of the same message is the same message, however it got retried.
    final key = payload.clientId;
    ({int delivered, String accountId}) result;
    try {
      result = await _sealAndSend(username, encoded, idempotencyKey: key);
    } on ApiException catch (error) {
      if (error.code != 'device_mismatch') rethrow;
      result = await _sealAndSend(username, encoded, idempotencyKey: key);
    }

    // Control payloads are machinery, not conversation: a receipt or a typing
    // notice on the other device would be filed as a message that was never
    // written. A deletion is the exception — it has to reach this account's
    // own devices or the message stays on half of them.
    if (!payload.isControl || payload.isDeletion) {
      await _syncToOwnDevices(
        conversationId: result.accountId,
        isGroup: false,
        encoded: encoded,
        idempotencyKey: key,
      );
    }
    return result.delivered;
  }

  /// Sends a file: strips its metadata, pads it, seals it under its own key,
  /// uploads the ciphertext, and sends the key inside the encrypted message.
  ///
  /// Returns what was stripped, so the UI can tell the user rather than leaving
  /// them to assume.
  /// Everything the sender needs to draw its own copy of a file it just sent:
  /// what was stripped, and where the ciphertext ended up.
  ///
  /// Returned rather than kept, because a device that has just uploaded a file
  /// knows more about it than the placeholder it drew a moment ago — and a
  /// bubble that stays empty until the message comes back from somewhere is a
  /// bubble that never fills in, since one's own messages do not come back.
  Future<SentAttachment> sendAttachment(
    String username, {
    required Uint8List file,
    String? fileName,
    String? declaredType,
    String caption = '',
  }) async {
    final sealed = await AttachmentCipher.seal(file, declaredType: declaredType);
    final blob = await _api.uploadMedia(sealed.bytes);

    await sendPayload(
      username,
      MessagePayload.media(
        mediaId: blob.id,
        mediaToken: blob.token,
        mediaKey: base64Encode(sealed.key),
        mediaType: sealed.report.mediaType,
        byteSize: sealed.plainLength,
        fileName: fileName,
        body: caption,
      ),
    );
    return (
      report: sealed.report,
      mediaId: blob.id,
      mediaKey: base64Encode(sealed.key),
      mediaToken: blob.token,
      mediaType: sealed.report.mediaType,
      byteSize: sealed.plainLength,
      fileName: fileName,
    );
  }

  /// Sends a voice message.
  ///
  /// The same pipeline as any attachment — sealed under its own random key,
  /// padded, uploaded as ciphertext — with the duration and waveform carried
  /// inside the sealed payload rather than beside the upload. The server sees a
  /// blob of a bucketed size and cannot tell it from a photo, let alone hear it.
  ///
  /// The recording's bytes are handed in from memory. Nothing on the way to
  /// here wrote them to disk in the clear.
  Future<void> sendVoice({
    required String username,
    required VoiceRecording recording,
    required String clientId,
    int? expiresInSeconds,
  }) async {
    final sealed = await AttachmentCipher.seal(
      recording.bytes,
      declaredType: recording.mediaType,
    );
    final blob = await _api.uploadMedia(sealed.bytes);

    await sendPayload(
      username,
      MessagePayload.media(
        mediaId: blob.id,
        mediaToken: blob.token,
        mediaKey: base64Encode(sealed.key),
        mediaType: recording.mediaType,
        byteSize: sealed.plainLength,
        voiceDurationMs: recording.duration.inMilliseconds,
        waveform: recording.waveform,
        expiresInSeconds: expiresInSeconds,
        clientId: clientId,
      ),
    );
  }

  /// The group form of [sendVoice].
  Future<void> sendVoiceToGroup({
    required String groupId,
    required VoiceRecording recording,
    required String clientId,
    String? groupKey,
    int? expiresInSeconds,
  }) async {
    final sealed = await AttachmentCipher.seal(
      recording.bytes,
      declaredType: recording.mediaType,
    );
    final blob = await _api.uploadMedia(sealed.bytes);

    await sendPayloadToGroup(
      groupId,
      MessagePayload.media(
        mediaId: blob.id,
        mediaToken: blob.token,
        mediaKey: base64Encode(sealed.key),
        mediaType: recording.mediaType,
        byteSize: sealed.plainLength,
        voiceDurationMs: recording.duration.inMilliseconds,
        waveform: recording.waveform,
        groupKey: groupKey,
        expiresInSeconds: expiresInSeconds,
        clientId: clientId,
      ),
    );
  }

  /// Tells [username] that their messages arrived, or were read.
  ///
  /// A receipt is a message like any other as far as the transport is
  /// concerned: sealed per device, opaque to the server. What the server can
  /// see is that *something* was sent — which is why a receipt is not sent at
  /// all when the setting is off, rather than sent and ignored.
  /// [groupId] names the conversation the messages were in, for a receipt about
  /// group messages. It still goes to the author alone — the group does not
  /// need telling who read what — so without it the receiving side would have
  /// no way to know which chat the ids belong to.
  Future<void> sendReceipt({
    required String username,
    required List<String> clientIds,
    required String kind,
    String? groupId,
  }) async {
    if (clientIds.isEmpty) return;
    await sendPayload(
      username,
      MessagePayload.receipt(
        receiptIds: clientIds,
        receiptKind: kind,
        receiptGroupId: groupId,
      ),
    );
  }

  /// "Typing." Cheap, frequent, and worthless a few seconds later, so it
  /// carries the moment it was sent and the reader decides whether that is
  /// still now.
  Future<void> sendTyping(String username) => sendPayload(
        username,
        MessagePayload.typing(DateTime.now().millisecondsSinceEpoch),
      );

  /// Attaches this account's profile key, which is how contacts become able to
  /// open its profile picture without the server ever learning the key.
  Future<MessagePayload> _withProfileKey(MessagePayload payload) async {
    // A key delivery carries no profile key and no body; rebuilding it as text
    // would quietly throw the key away.
    if (payload.isKeyDelivery || payload.profileKey != null) return payload;
    return payload.withProfileKey(base64Encode(await _crypto.profileKey()));
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
    final blob = await _api.uploadMedia(sealed, avatar: true);
    await _api.setAvatar(blob.id);
    return blob.id;
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
    final sealed = await _api.downloadMedia(payload.mediaId!, token: payload.mediaToken);
    return AttachmentCipher.open(
      Uint8List.fromList(sealed),
      base64Decode(payload.mediaKey!),
    );
  }

  /// Seals for every device of [username] and sends. Returns how many copies
  /// were delivered and whose account they went to — the account id is what a
  /// conversation is keyed by, and the caller needs it for the sync copy.
  Future<({int delivered, String accountId})> _sealAndSend(
    String username,
    String plaintext, {
    String? idempotencyKey,
  }) async {
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
    // Nobody to seal for. The only way here is a self-addressed copy on an
    // account with one device: sending an empty list would be a request that
    // asks the server to deliver nothing.
    if (sealed.isEmpty) return (delivered: 0, accountId: accountId);

    final result = await _api.sendMessage(
      username: username,
      idempotencyKey: idempotencyKey,
      messages: [for (final copy in sealed) copy.toJson()],
    );
    return (
      delivered: result['deliveredTo'] as int? ?? sealed.length,
      accountId: accountId,
    );
  }

  /// Who this device is, so it can address its own other devices.
  ///
  /// Set at sign-in rather than looked up per send: a request to find out one's
  /// own name before every message is a request the server does not need.
  String? _selfUsername;

  // ignore: use_setters_to_change_properties
  void identifyAs(String? username) => _selfUsername = username;

  /// Sends a copy of what was just sent to this account's own other devices.
  ///
  /// Awaited rather than fired off, so a send is finished when the copy is —
  /// it costs one more round trip and it means a message is never "sent" on
  /// one device and unknown to the next.
  ///
  /// A failure here does not fail the send. The message reached the person it
  /// was for; a second device that missed the copy shows an incomplete history,
  /// which is bad and is not worth turning into a message that did not go.
  Future<void> _syncToOwnDevices({
    required String conversationId,
    required bool isGroup,
    required String encoded,
    String? idempotencyKey,
  }) async {
    final me = _selfUsername;
    if (me == null) return;
    final envelope = SyncEnvelope(
      conversationId: conversationId,
      isGroup: isGroup,
      payload: encoded,
    );
    try {
      await _sealAndSend(
        me,
        MessagePayload.sync(envelope).encode(),
        // A distinct key from the original send: it is a different message to
        // a different set of devices, and sharing one would have the server
        // treat the second as a retry of the first.
        idempotencyKey: idempotencyKey == null ? null : 'sync:\$idempotencyKey',
      );
    } on ApiException {
      // Swallowed on purpose, and this is the trade: the message reached the
      // person it was for. A second device that missed its copy shows an
      // incomplete history, which is bad; turning that into a send that failed
      // — so the sender retries, and the recipient gets it twice — is worse.
      //
      // 'no_devices' is the ordinary case and not a failure at all: an account
      // with one device has nobody to copy to. The rest are, and the copy is
      // not retried, which is a real limit: a device that was offline for that
      // one send has a gap in its history that nothing fills but a backup.
    }
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
    int? keyEpoch,
  }) =>
      sendPayload(
        username,
        MessagePayload.key(
          keyScope: scope,
          keyScopeId: scopeId,
          deliveredKey: base64Key,
          // Channels only. Without it the receiver cannot tell which version
          // this is, and would file a superseded key over the current one.
          keyEpoch: keyEpoch,
        ),
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

    // Queue behind whatever batch is already in the ratchet, then take the
    // turn. The completer is never completed with an error, so one failed
    // batch cannot wedge the queue.
    final previous = _decrypting;
    final turn = Completer<void>();
    _decrypting = turn.future;
    try {
      await previous;
      return await _decryptBatch(envelopes, more: more);
    } finally {
      turn.complete();
    }
  }

  Future<ReceiveResult> _decryptBatch(
    List<dynamic> envelopes, {
    required bool more,
  }) async {
    final messages = <IncomingMessage>[];
    final failures = <UndecryptableMessage>[];
    var highestHandled = 0;

    for (final raw in envelopes) {
      final envelope = raw as Map<String, dynamic>;
      final envelopeId = envelope['id'] as int;
      final type = envelope['type'] as String;
      final senderAccountId = envelope['senderAccountId'] as String?;
      final senderDeviceIndex = envelope['senderDeviceIndex'] as int?;

      if (envelopeId <= _handledThrough) {
        // Already opened on the other channel. It still counts as handled, so
        // the acknowledgement moves past it rather than asking for it again.
        highestHandled = envelopeId > highestHandled ? envelopeId : highestHandled;
        continue;
      }

      if (type != 'prekey' && type != 'ciphertext') {
        // Receipts, typing and control envelopes are handled elsewhere; they
        // still count as processed so the queue drains.
        highestHandled = envelopeId > highestHandled ? envelopeId : highestHandled;
        continue;
      }

      if (senderAccountId == null || senderDeviceIndex == null) {
        failures.add(
          UndecryptableMessage(
            envelopeId,
            senderAccountId,
            StateError('Envelope has no identifiable sender device'),
            groupId: envelope['groupId'] as String?,
          ),
        );
        highestHandled = envelopeId > highestHandled ? envelopeId : highestHandled;
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
        failures.add(
          UndecryptableMessage(
            envelopeId,
            senderAccountId,
            error,
            senderDeviceIndex: senderDeviceIndex,
            groupId: envelope['groupId'] as String?,
          ),
        );
      }
      highestHandled = envelopeId > highestHandled ? envelopeId : highestHandled;
    }

    if (highestHandled > _handledThrough) _handledThrough = highestHandled;
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
      memberCount: (created['members'] as List<dynamic>?)?.length ?? 0,
      memberIds: [
        for (final member in created['members'] as List<dynamic>)
          (member as Map<String, dynamic>)['id'] as String,
      ],
    );
  }

  /// Everyone in a group, as the server lists them.
  ///
  /// Fetched rather than remembered: membership changes when somebody joins by
  /// a link or is removed, and neither of those sends a message.
  Future<List<GroupMember>> groupMembers(String groupId) async {
    final detail = await _api.group(groupId);
    return [
      for (final raw in detail['members'] as List<dynamic>? ?? const [])
        GroupMember.fromJson(raw as Map<String, dynamic>),
    ];
  }

  /// Renames a group.
  ///
  /// The name is sealed with the group's own key before it goes, exactly as it
  /// was when the group was created, so the server stores a new blob it cannot
  /// read. Every other member opens it with the key they already have; nothing
  /// has to be sent to them.
  Future<void> renameGroup(String groupId, String name, String groupKey) async {
    final sealed = await _sealGroupName(name, base64Decode(groupKey));
    await _api.updateGroupMetadata(groupId, base64Encode(sealed));
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
          // Carried rather than dropped: it is what says whether *everyone* has
          // read a message, which is the only honest reading of a group tick.
          memberCount: (entry['memberCount'] as num?)?.toInt() ?? 0,
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
  /// Asks the other members for a group's key.
  ///
  /// Joining records a request on the server already. This is for the device
  /// that never joined: a second phone signing in to an account that is
  /// already in the group, which has the membership and no key and would
  /// otherwise sit at "waiting for the group key" until somebody happened to
  /// speak.
  Future<void> requestGroupKey(String groupId) => _api.requestGroupKey(groupId);

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

  /// Sends text to a group.
  ///
  /// There is no group-wide message key: every device gets its own Signal
  /// ciphertext, so removing a member removes their ability to read what comes
  /// after, without re-keying anything.
  Future<int> sendToGroup(String groupId, String plaintext, {String? groupKey}) =>
      sendPayloadToGroup(
        groupId,
        MessagePayload.text(plaintext, groupKey: groupKey),
      );

  /// Sends a file to a group.
  ///
  /// The file itself is uploaded once, sealed under its own key; only the
  /// pointer and that key are fanned out per device. So a photo costs one
  /// upload however many members there are, and the server still holds bytes it
  /// cannot open.
  Future<SentAttachment> sendGroupAttachment(
    String groupId, {
    required Uint8List file,
    String? fileName,
    String? declaredType,
    String caption = '',
    String? groupKey,
  }) async {
    final sealed = await AttachmentCipher.seal(file, declaredType: declaredType);
    final blob = await _api.uploadMedia(sealed.bytes);

    await sendPayloadToGroup(
      groupId,
      MessagePayload.media(
        mediaId: blob.id,
        mediaToken: blob.token,
        mediaKey: base64Encode(sealed.key),
        mediaType: sealed.report.mediaType,
        byteSize: sealed.plainLength,
        fileName: fileName,
        body: caption,
        groupKey: groupKey,
      ),
    );
    return (
      report: sealed.report,
      mediaId: blob.id,
      mediaKey: base64Encode(sealed.key),
      mediaToken: blob.token,
      mediaType: sealed.report.mediaType,
      byteSize: sealed.plainLength,
      fileName: fileName,
    );
  }

  /// Seals [payload] once per member device and posts it to the group.
  Future<int> sendPayloadToGroup(String groupId, MessagePayload payload) async {
    final encoded = (await _withProfileKey(payload)).encode();

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

    final result = await _api.sendGroupMessage(
      groupId: groupId,
      idempotencyKey: payload.clientId,
      messages: sealed,
    );
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

  /// Replaces the signed prekey when it has been on offer too long.
  ///
  /// Published before anything is deleted, and the newest is never deleted, so
  /// there is no moment where the server offers a key this device cannot open.
  /// Returns whether a new one went up.
  Future<bool> rotateSignedPreKeyIfDue({DateTime? now}) async {
    final at = now ?? DateTime.now();
    if (!await _crypto.signedPreKeyIsDue(at)) return false;
    await _api.rotateSignedPreKey(await _crypto.rotateSignedPreKey());
    await _crypto.pruneSignedPreKeys(at);
    return true;
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
