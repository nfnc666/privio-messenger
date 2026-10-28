import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:libsignal/libsignal.dart' as rs;

/// Sealed sender's pieces that are not a session: loading the native library,
/// the access key, and reading a certificate. See docs/sealed-sender.md.
///
/// Every cryptographic step here is Signal's libsignal, built from source by
/// `app/scripts/build_libsignal.sh`, or HKDF from the `cryptography` package.
/// Nothing is written by hand.
abstract final class SealedSender {
  static Future<bool>? _loading;

  /// Loads the native library once. False where it is not there — the web
  /// build, or a build whose library failed to load — and then nothing is
  /// sealed and the app sends the way it always has.
  static Future<bool> load() => _loading ??= _load();

  static Future<bool> _load() async {
    if (kIsWeb) return false;
    try {
      await rs.LibSignal.init();
      return true;
    } on Object {
      return false;
    }
  }

  /// How many bytes an access key has. The server compares exactly this many.
  static const int accessKeyLength = 16;

  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: accessKeyLength);

  /// Says what the derived bytes are for, so the same profile key used for
  /// anything else can never produce the same output.
  static final List<int> _accessInfo = utf8.encode('Privio unidentified access key');

  /// The key that lets somebody send this account sealed messages, derived
  /// from the profile key with HKDF-SHA256.
  ///
  /// The owner derives it from their own profile key and gives it to the
  /// server; everybody the owner has written to holds the same profile key
  /// and derives the same bytes. So "may send me sealed" means "has been
  /// written to by me", which the owner decided by writing, not the server.
  static Future<Uint8List> accessKey(List<int> profileKey) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(profileKey),
      nonce: const [],
      info: _accessInfo,
    );
    return Uint8List.fromList(await key.extractBytes());
  }
}

/// A sender certificate this device was issued: who it vouches for, and until
/// when. Read from the certificate itself, through the library.
@immutable
class SenderCertificate {
  const SenderCertificate({
    required this.bytes,
    required this.accountId,
    required this.deviceIndex,
    required this.expiresAt,
  });

  factory SenderCertificate.parse(Uint8List bytes) => SenderCertificate(
        bytes: bytes,
        accountId: rs.senderCertificateGetSenderName(certificate: bytes),
        deviceIndex: rs.senderCertificateGetSenderDeviceId(certificate: bytes),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          rs.senderCertificateGetExpiration(certificate: bytes).toInt(),
        ),
      );

  final Uint8List bytes;
  final String accountId;
  final int deviceIndex;
  final DateTime expiresAt;

  /// Usable for a send that starts at [now]: fetched again an hour before it
  /// runs out, so no message leaves with a certificate that expires on the way.
  bool isFreshAt(DateTime now) => expiresAt.difference(now) > const Duration(hours: 1);
}
