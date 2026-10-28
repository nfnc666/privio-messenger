import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../crypto/privio_crypto.dart';
import '../crypto/sealed_sender.dart';

/// How far sealed sender works on this device, as a case. The privacy
/// dashboard turns it into words, and says exactly this much and no more.
enum SealedSenderStatus {
  /// Not started yet: nothing is sealed.
  notStarted,

  /// This build has no native library to seal with.
  unavailableHere,

  /// The server does not offer sealed sender.
  serverOff,

  /// The server answered with a trust root other than the one pinned here.
  /// Refused: nothing is sealed or opened until that is explained.
  trustRootChanged,

  /// Sealed messages can be received, but this device has no certificate to
  /// send with, so it sends the way it always has.
  receiveOnly,

  /// One-to-one messages to people who can receive sealed go sealed.
  on,
}

/// This device's side of sealed sender: the pinned trust root, the sender
/// certificate, and the access key the server compares. The one place that
/// asks the server about any of it. See docs/sealed-sender.md.
class SealedSenderService extends ChangeNotifier {
  SealedSenderService({
    required PrivioApiClient api,
    required PrivioCrypto crypto,
    required SecureStore store,
    String buildPin = const String.fromEnvironment('PRIVIO_SEALED_TRUST_ROOT'),
  })  : _api = api,
        _crypto = crypto,
        _store = store,
        _buildPin = buildPin;

  final PrivioApiClient _api;
  final PrivioCrypto _crypto;
  final SecureStore _store;

  /// A trust root built into the app, when the build was given one. Then it
  /// is the only one accepted, and nothing is learned from the server.
  final String _buildPin;

  Uint8List? _trustRoot;
  SenderCertificate? _certificate;
  String? _accountId;
  SealedSenderStatus _status = SealedSenderStatus.notStarted;

  SealedSenderStatus get status => _status;

  /// True once this device can open sealed messages.
  bool get canOpen => _trustRoot != null && _accountId != null;

  /// Accounts whose access key was refused, and when. Sealing to them is not
  /// tried again for [refusedFor]: their profile key has changed, and the new
  /// one arrives with their next message.
  final Map<String, DateTime> _refused = {};
  static const Duration refusedFor = Duration(hours: 1);

  /// At sign-in: the library, the trust root, this account's access key, and a
  /// certificate. Each step that fails leaves sealed sender off, or receive
  /// only, and says which in [status]; none of them stops the app.
  Future<void> start(String accountId) async {
    _accountId = accountId;
    _trustRoot = null;
    _certificate = null;
    if (!await SealedSender.load()) return _set(SealedSenderStatus.unavailableHere);

    final root = await _resolveTrustRoot();
    if (root == null) return;
    _trustRoot = root;
    try {
      await publishAccessKey();
    } on Object {
      // Offline. Whatever key the server already holds still lets people in,
      // and the next start tries again.
    }
    await certificate();
    _set(_certificate == null ? SealedSenderStatus.receiveOnly : SealedSenderStatus.on);
  }

  Future<Uint8List?> _resolveTrustRoot() async {
    if (_buildPin.isNotEmpty) return base64Decode(_buildPin);
    final stored = await _store.readSealedTrustRoot();
    final String offered;
    try {
      offered = (await _api.sealedSenderTrustRoot())['trustRoot'] as String;
    } on ApiException catch (error) {
      if (error.code == 'sealed_sender_unavailable') {
        _set(SealedSenderStatus.serverOff);
        return null;
      }
      // Any other answer, or none: what was pinned still opens what arrives.
      return stored == null ? null : base64Decode(stored);
    } on Object {
      return stored == null ? null : base64Decode(stored);
    }
    if (stored == null) {
      // Trust on first use, as for a contact's key: the first answer is
      // pinned, and every later one has to match it.
      await _store.writeSealedTrustRoot(offered);
      return base64Decode(offered);
    }
    if (stored != offered) {
      _set(SealedSenderStatus.trustRootChanged);
      return null;
    }
    return base64Decode(stored);
  }

  /// Gives the server this account's access key, derived from the profile key.
  /// Called at start and whenever the profile key changes.
  Future<void> publishAccessKey() async {
    final key = await SealedSender.accessKey(await _crypto.profileKey());
    await _api.setUnidentifiedAccess(base64Encode(key));
  }

  /// A certificate fresh enough to send with, fetched when the one held is
  /// not. Null when the server will not issue one — no license, or offline.
  Future<SenderCertificate?> certificate() async {
    final held = _certificate;
    if (held != null && held.isFreshAt(DateTime.now())) return held;
    try {
      final answer = await _api.senderCertificate();
      _certificate = SenderCertificate.parse(base64Decode(answer['certificate'] as String));
    } on Object {
      return null;
    }
    return _certificate;
  }

  /// What a sealed send to [accountId] needs, or null when it cannot be one:
  /// not set up, no profile key for them, this account itself, refused a
  /// moment ago, or no certificate.
  Future<({Uint8List certificate, String accessKey})?> routeTo(
    String accountId,
    List<int>? profileKey,
  ) async {
    if (_status != SealedSenderStatus.on || profileKey == null || accountId == _accountId) {
      return null;
    }
    final refusedAt = _refused[accountId];
    if (refusedAt != null && DateTime.now().difference(refusedAt) < refusedFor) return null;
    final held = await certificate();
    if (held == null) return null;
    return (
      certificate: held.bytes,
      accessKey: base64Encode(await SealedSender.accessKey(profileKey)),
    );
  }

  /// The server refused the access key for [accountId].
  void refused(String accountId) => _refused[accountId] = DateTime.now();

  /// The server stopped offering sealed sender after all.
  void serverWentOff() => _set(SealedSenderStatus.serverOff);

  /// Opens a sealed envelope. Only once [canOpen].
  Future<SealedOpened> open({required String content, required DateTime sentAt}) =>
      _crypto.openSealed(
        content: content,
        trustRoot: _trustRoot!,
        sentAt: sentAt,
        localAccountId: _accountId!,
        // From this device's own certificate. Without one, nothing this
        // device sent sealed can come back reflected, so there is nothing for
        // the self-send check to catch.
        localDeviceIndex: _certificate?.deviceIndex ?? 0,
      );

  void _set(SealedSenderStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }
}
