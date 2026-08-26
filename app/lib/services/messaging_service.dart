import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../crypto/privio_crypto.dart';
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
    final encoded = payload.encode();
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
