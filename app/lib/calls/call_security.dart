import '../core/failure.dart';
import '../crypto/privio_crypto.dart';
import '../crypto/safety_number.dart';
import 'sdp_policy.dart';

/// What Privio actually checked before it let a call happen.
///
/// There is no third value for "not encrypted". A call that does not reach one
/// of these two states does not connect — see [CallRefusal]. That is what makes
/// the padlock on the call screen a statement rather than decoration.
enum CallSecurity {
  /// The media is DTLS-SRTP and the far end's certificate is committed to
  /// inside a description that was sealed to an identity key this device has
  /// pinned for that account. Nobody has compared safety numbers, so the pin
  /// itself rests on trust-on-first-use.
  encrypted,

  /// The same, and the user has compared the safety number with that account,
  /// so the pinned key is one a person has checked rather than one this device
  /// merely met first.
  verified,
}

/// Why a call was refused. Every one of these ends the call; none of them
/// falls back to anything.
enum CallRefusal {
  /// The description offered a transport that does not end in SRTP, or carried
  /// the media key in the document. Either way it is the unencrypted path.
  mediaNotEncrypted,

  /// Nothing in the description binds the far end to a certificate: no
  /// fingerprint, one over a hash not worth authenticating with, or two
  /// sections naming two different certificates.
  farEndNotBound,

  /// The certificate changed between the offer and the answer. A call has one
  /// far end, and this is what a substitution looks like from in here.
  certificateChanged,

  /// The identity key for that account is not the one that was pinned — it was
  /// replaced by the very envelope this signal arrived in. Somebody else is
  /// answering to that name, or that person reinstalled; either way, not this
  /// call, not before the safety number has been looked at.
  identityChanged,

  /// A signal about this call arrived from an account that is not on it.
  wrongParty,

  /// Strict mode: the safety number for that account has not been confirmed.
  notVerified,
}

/// Rolls an SDP refusal up into the one the user is told about.
CallRefusal refusalFor(SdpRefusal refusal) => switch (refusal) {
      SdpRefusal.insecureTransport ||
      SdpRefusal.sdesKeyInDescription =>
        CallRefusal.mediaNotEncrypted,
      SdpRefusal.noMedia ||
      SdpRefusal.noFingerprint ||
      SdpRefusal.weakFingerprintHash ||
      SdpRefusal.fingerprintMismatch =>
        CallRefusal.farEndNotBound,
    };

/// Who the far end of a call is, cryptographically, and what was checked.
///
/// Built once per call and then held fixed: every later signal is measured
/// against it rather than trusted on its own. The account id in here is the
/// server's label, which is exactly why it is not the only field.
class CallPeerIdentity {
  const CallPeerIdentity({
    required this.accountId,
    required this.identityKey,
    required this.security,
    this.deviceIndex,
  });

  final String accountId;

  /// The key that opened the envelope this call was negotiated in. Not the
  /// server's word for who is calling — the key the session authenticated.
  final String identityKey;

  final int? deviceIndex;
  final CallSecurity security;
}

/// The one place that decides whether a call may go ahead.
///
/// Pure: it takes facts and returns a verdict, so every refusal below is a test
/// that runs without a microphone, a network, or a second machine.
class CallGuard {
  const CallGuard({this.requireVerified = false});

  /// Strict mode. Off by default. On, a call happens only with somebody whose
  /// safety number this device has confirmed.
  final bool requireVerified;

  /// Checks the party a call is being negotiated with.
  ///
  /// [trust] is how the envelope's own key stood: a key that was *replaced*
  /// under this envelope is refused outright, because that is precisely the
  /// shape of a relay substituting a peer. A key seen for the first time is
  /// pinned and the call is allowed but never called verified — the answer the
  /// app gives everywhere else, and a decision that belongs to the user, who
  /// can turn [requireVerified] on.
  ({CallPeerIdentity? identity, CallRefusal? refusal}) admit({
    required String accountId,
    required String? identityKey,
    required PeerTrust trust,
    required VerificationState verification,
    int? deviceIndex,
  }) {
    // No key means nothing authenticated this, whatever the server labelled it.
    if (identityKey == null || trust == PeerTrust.replaced) {
      return (identity: null, refusal: CallRefusal.identityChanged);
    }
    // A number that was confirmed and no longer matches is a change the user
    // has not looked at yet. Strict or not, that one does not ring.
    if (verification == VerificationState.changed) {
      return (identity: null, refusal: CallRefusal.identityChanged);
    }
    if (requireVerified && verification != VerificationState.verified) {
      return (identity: null, refusal: CallRefusal.notVerified);
    }
    return (
      identity: CallPeerIdentity(
        accountId: accountId,
        identityKey: identityKey,
        deviceIndex: deviceIndex,
        security: verification == VerificationState.verified
            ? CallSecurity.verified
            : CallSecurity.encrypted,
      ),
      refusal: null,
    );
  }

  /// Checks a signal that arrived for a call already under way.
  ///
  /// The account *and* the key both have to match what the call was set up
  /// with. Checking only the account would leave the substitution open on the
  /// answer; checking only the key would let one person's second device step
  /// into somebody else's call.
  CallRefusal? admitSignal({
    required CallPeerIdentity expected,
    required String accountId,
    required String? identityKey,
    required PeerTrust trust,
  }) {
    if (accountId != expected.accountId) return CallRefusal.wrongParty;
    if (trust == PeerTrust.replaced) return CallRefusal.identityChanged;
    // A null key here means the signal did not come through a session at all.
    // Nothing in a call is taken on the server's word.
    if (identityKey == null || identityKey != expected.identityKey) {
      return CallRefusal.identityChanged;
    }
    return null;
  }

  /// Checks a session description, and the certificate it commits to.
  ///
  /// [pinned] is the fingerprint this call has already accepted, if any. The
  /// second description of a call has to name the same certificate as the
  /// first: a call has one far end.
  ({String? fingerprint, CallRefusal? refusal}) admitSdp(
    String sdp, {
    String? pinned,
  }) {
    final check = checkSdp(sdp);
    final refusal = check.refusal;
    if (refusal != null) return (fingerprint: null, refusal: refusalFor(refusal));
    if (pinned != null && pinned != check.fingerprint) {
      return (fingerprint: null, refusal: CallRefusal.certificateChanged);
    }
    return (fingerprint: check.fingerprint, refusal: null);
  }
}

/// A refusal as a [Failure], so the screen can say it in the reader's language.
///
/// Lives here rather than in the l10n layer because a service has to be able
/// to end a call without importing anything that knows about words. [who] is
/// the other person's username, passed through untranslated.
Failure callFailure(CallRefusal refusal, {required String who}) => switch (refusal) {
      CallRefusal.mediaNotEncrypted => const Failure(FailureKind.callMediaNotEncrypted),
      CallRefusal.farEndNotBound => const Failure(FailureKind.callFarEndNotBound),
      CallRefusal.certificateChanged => const Failure(FailureKind.callCertificateChanged),
      CallRefusal.identityChanged => Failure(FailureKind.callIdentityChanged, detail: who),
      CallRefusal.wrongParty => const Failure(FailureKind.callWrongParty),
      CallRefusal.notVerified => Failure(FailureKind.callNotVerified, detail: who),
    };
