import 'package:flutter_test/flutter_test.dart';
import 'package:privio/calls/sdp_policy.dart';

/// A description shaped like the ones libwebrtc actually produces, with the
/// one line under test swapped out. Written out rather than generated so a
/// reader can see exactly what is being accepted.
String sdp({
  String proto = 'UDP/TLS/RTP/SAVPF',
  String? sessionFingerprint = 'sha-256 AA:BB:CC:DD:EE:FF:00:11',
  String? audioFingerprint,
  String? videoFingerprint,
  bool video = false,
  bool sdes = false,
}) {
  final lines = <String>[
    'v=0',
    'o=- 4611731400430051336 2 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'a=group:BUNDLE 0',
    if (sessionFingerprint != null) 'a=fingerprint:$sessionFingerprint',
    'm=audio 9 $proto 111',
    'c=IN IP4 0.0.0.0',
    'a=mid:0',
    'a=setup:actpass',
    if (audioFingerprint != null) 'a=fingerprint:$audioFingerprint',
    if (sdes) 'a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:abcdefghijklmnop',
    'a=rtpmap:111 opus/48000/2',
    if (video) ...[
      'm=video 9 $proto 96',
      'c=IN IP4 0.0.0.0',
      'a=mid:1',
      'a=setup:actpass',
      if (videoFingerprint != null) 'a=fingerprint:$videoFingerprint',
      'a=rtpmap:96 VP8/90000',
    ],
  ];
  return '${lines.join('\r\n')}\r\n';
}

void main() {
  group('a description that can only end in encrypted media', () {
    test('passes, and hands back the certificate it commits to', () {
      final check = checkSdp(sdp());
      expect(check.isOk, isTrue);
      expect(check.fingerprint, 'sha-256 AA:BB:CC:DD:EE:FF:00:11');
    });

    test('a video call carries the same certificate on both sections', () {
      final check = checkSdp(sdp(video: true));
      expect(check.isOk, isTrue);
      expect(check.fingerprint, 'sha-256 AA:BB:CC:DD:EE:FF:00:11');
    });

    test('a per-section fingerprint is allowed when both agree', () {
      final check = checkSdp(
        sdp(
          sessionFingerprint: null,
          audioFingerprint: 'sha-384 11:22:33:44',
          videoFingerprint: 'sha-384 11:22:33:44',
          video: true,
        ),
      );
      expect(check.isOk, isTrue);
      expect(check.fingerprint, 'sha-384 11:22:33:44');
    });

    test('the hash name is read case-insensitively, the digits normalised', () {
      final check = checkSdp(sdp(sessionFingerprint: 'SHA-256 aa:bb:cc:dd'));
      expect(check.isOk, isTrue);
      expect(check.fingerprint, 'sha-256 AA:BB:CC:DD');
    });
  });

  group('the unencrypted fallback, refused', () {
    test('plain RTP is not negotiated, whatever else the description says', () {
      // The one that matters most: legal SDP, and audio in the clear.
      final check = checkSdp(sdp(proto: 'RTP/AVP'));
      expect(check.isOk, isFalse);
      expect(check.refusal, SdpRefusal.insecureTransport);
    });

    test('RTP/AVPF is refused too — feedback does not make it secure', () {
      expect(checkSdp(sdp(proto: 'RTP/AVPF')).refusal, SdpRefusal.insecureTransport);
    });

    test('a profile nobody recognises is refused rather than assumed', () {
      expect(checkSdp(sdp(proto: 'RTP/SOMETHING')).refusal, SdpRefusal.insecureTransport);
    });

    test('only the video section going plain is still a refusal', () {
      final mixed = sdp(video: true).replaceFirst(
        'm=video 9 UDP/TLS/RTP/SAVPF 96',
        'm=video 9 RTP/AVP 96',
      );
      expect(checkSdp(mixed).refusal, SdpRefusal.insecureTransport);
    });
  });

  group('keys in the document, refused', () {
    test('a=crypto is refused even alongside a valid fingerprint', () {
      // SDES next to DTLS is how a handshake gets traded for a shared secret
      // sitting in a document.
      final check = checkSdp(sdp(sdes: true));
      expect(check.isOk, isFalse);
      expect(check.refusal, SdpRefusal.sdesKeyInDescription);
    });
  });

  group('nothing binding the far end, refused', () {
    test('no fingerprint anywhere', () {
      final check = checkSdp(sdp(sessionFingerprint: null));
      expect(check.isOk, isFalse);
      expect(check.refusal, SdpRefusal.noFingerprint);
    });

    test('a section with no fingerprint and no session one to inherit', () {
      final check = checkSdp(
        sdp(sessionFingerprint: null, audioFingerprint: 'sha-256 AA:BB', video: true),
      );
      expect(check.refusal, SdpRefusal.noFingerprint);
    });

    test('sha-1 is not something to authenticate a call with', () {
      final check = checkSdp(sdp(sessionFingerprint: 'sha-1 AA:BB:CC:DD'));
      expect(check.isOk, isFalse);
      expect(check.refusal, SdpRefusal.weakFingerprintHash);
    });

    test('md5 likewise', () {
      expect(
        checkSdp(sdp(sessionFingerprint: 'md5 AA:BB:CC:DD')).refusal,
        SdpRefusal.weakFingerprintHash,
      );
    });

    test('a fingerprint that is not hex pairs is not a fingerprint', () {
      expect(
        checkSdp(sdp(sessionFingerprint: 'sha-256 not-a-fingerprint')).refusal,
        SdpRefusal.weakFingerprintHash,
      );
    });

    test('two sections naming two certificates is not one call', () {
      // One stream to one place and one to another.
      final check = checkSdp(
        sdp(
          sessionFingerprint: null,
          audioFingerprint: 'sha-256 AA:BB',
          videoFingerprint: 'sha-256 CC:DD',
          video: true,
        ),
      );
      expect(check.isOk, isFalse);
      expect(check.refusal, SdpRefusal.fingerprintMismatch);
    });

    test('a section overriding the session certificate is a mismatch', () {
      final check = checkSdp(
        sdp(audioFingerprint: 'sha-256 99:88:77:66', video: true),
      );
      expect(check.refusal, SdpRefusal.fingerprintMismatch);
    });
  });

  group('nothing to secure', () {
    test('a description with no media at all', () {
      expect(checkSdp('v=0\r\ns=-\r\nt=0 0\r\n').refusal, SdpRefusal.noMedia);
    });

    test('an empty string is not a description', () {
      expect(checkSdp('').refusal, SdpRefusal.noMedia);
    });
  });
}
