/// What a session description has to prove before Privio will hand it to the
/// media stack.
///
/// This writes no cryptography. The encryption of a call is DTLS-SRTP, which
/// libwebrtc implements and this app does not touch. What lives here is the
/// *policy* question that libwebrtc does not answer for us: is the document we
/// are about to negotiate from one that can only end in encrypted media, and
/// which key is it going to authenticate the far end with.
///
/// It matters because an SDP is a negotiation, and a negotiation has losing
/// positions. RFC 4566 can describe plain RTP; RFC 4568 can carry SRTP keys in
/// the SDP itself (`a=crypto`, "SDES"), which puts the media key in the
/// document rather than in a handshake. Both are legal SDP. Neither is
/// acceptable here, so both are refused before they reach the stack rather
/// than left to whatever the stack happens to have been built to allow.
library;

/// Why a session description was refused.
enum SdpRefusal {
  /// No media at all — nothing to secure, and nothing to talk about.
  noMedia,

  /// A media section offered plain RTP. That is the unencrypted fallback, and
  /// there is no version of this app that takes it.
  insecureTransport,

  /// `a=crypto`: SRTP keys carried in the description. Even where the
  /// description is sealed, this trades a handshake for a shared secret in a
  /// document, and it is how a DTLS negotiation gets downgraded.
  sdesKeyInDescription,

  /// No `a=fingerprint`. Without it there is nothing binding the DTLS
  /// certificate at the far end to the description that was sealed to us, and
  /// the far end could be anyone.
  noFingerprint,

  /// A fingerprint over a hash nobody should still be authenticating with.
  weakFingerprintHash,

  /// Media sections that do not agree on one certificate. One stream to one
  /// place and one to another is not a call between two people.
  fingerprintMismatch,
}

/// A description that passed, and the certificate it commits the far end to.
class SdpCheck {
  const SdpCheck.ok(this.fingerprint) : refusal = null;
  const SdpCheck.refused(this.refusal) : fingerprint = null;

  /// The `a=fingerprint` value, normalised: `sha-256 AB:CD:...`.
  ///
  /// Held for the length of the call. The far end's DTLS certificate is
  /// checked against this by libwebrtc during the handshake, and a *second*
  /// description arriving mid-call with a different one is a substitution
  /// attempt, not a renegotiation Privio needs.
  final String? fingerprint;

  final SdpRefusal? refusal;

  bool get isOk => refusal == null;
}

/// Reads [sdp] and decides whether it can only end in encrypted media.
///
/// Deliberately strict and deliberately dumb: it refuses anything it does not
/// understand rather than assuming the stack will. A description this returns
/// [SdpCheck.ok] for is one where every media section is DTLS-protected and
/// every one of them authenticates the same certificate.
SdpCheck checkSdp(String sdp) {
  String? sessionFingerprint;
  final mediaFingerprints = <String?>[];
  var inMedia = false;
  var sawMedia = false;

  for (final raw in sdp.split(RegExp(r'\r\n|\r|\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('m=')) {
      inMedia = true;
      sawMedia = true;
      mediaFingerprints.add(null);
      final refusal = _checkTransport(line);
      if (refusal != null) return SdpCheck.refused(refusal);
      continue;
    }

    // SDES anywhere — session level or in one section — refuses the whole
    // description. A single section carrying keys in the document is enough.
    if (line.startsWith('a=crypto:')) {
      return const SdpCheck.refused(SdpRefusal.sdesKeyInDescription);
    }

    if (line.startsWith('a=fingerprint:')) {
      final value = _normaliseFingerprint(line.substring('a=fingerprint:'.length));
      if (value == null) {
        return const SdpCheck.refused(SdpRefusal.weakFingerprintHash);
      }
      if (inMedia) {
        mediaFingerprints[mediaFingerprints.length - 1] = value;
      } else {
        sessionFingerprint = value;
      }
    }
  }

  if (!sawMedia) return const SdpCheck.refused(SdpRefusal.noMedia);

  // A media section inherits the session-level fingerprint when it carries
  // none of its own. That is ordinary SDP, not a shortcut: one certificate for
  // the whole session is the common shape.
  String? agreed;
  for (final perSection in mediaFingerprints) {
    final effective = perSection ?? sessionFingerprint;
    if (effective == null) return const SdpCheck.refused(SdpRefusal.noFingerprint);
    if (agreed == null) {
      agreed = effective;
    } else if (agreed != effective) {
      return const SdpCheck.refused(SdpRefusal.fingerprintMismatch);
    }
  }

  return SdpCheck.ok(agreed!);
}

/// Whether an `m=` line names a transport that ends in SRTP.
///
/// An allow-list, not a deny-list: a profile this does not recognise is
/// refused. Guessing in the other direction is how "we did not think of that
/// one" becomes plaintext audio.
SdpRefusal? _checkTransport(String mLine) {
  // m=<media> <port> <proto> <fmt ...>
  final parts = mLine.substring(2).split(' ');
  if (parts.length < 3) return SdpRefusal.insecureTransport;
  final proto = parts[2].toUpperCase();

  const allowed = {
    'UDP/TLS/RTP/SAVPF',
    'UDP/TLS/RTP/SAVP',
    'TCP/TLS/RTP/SAVPF',
    'TCP/TLS/RTP/SAVP',
    'UDP/DTLS/SCTP',
    'TCP/DTLS/SCTP',
    // What some stacks still write for a DTLS-SRTP section. Accepted only
    // because the fingerprint check below is what actually decides: a section
    // on this profile with no fingerprint is refused like any other.
    'RTP/SAVPF',
    'RTP/SAVP',
  };

  return allowed.contains(proto) ? null : SdpRefusal.insecureTransport;
}

/// `sha-256 AB:CD:...` if the hash is one worth authenticating with, else null.
///
/// SHA-1 is refused. It is still what some stacks offer by default, and it is
/// exactly the wrong place to be lenient: the fingerprint is the *only* thing
/// tying the sealed description to the certificate at the far end.
String? _normaliseFingerprint(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final hash = parts[0].toLowerCase();
  const strong = {'sha-256', 'sha-384', 'sha-512'};
  if (!strong.contains(hash)) return null;
  final digits = parts[1].toUpperCase();
  if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2})+$').hasMatch(digits)) return null;
  return '$hash $digits';
}
