/// Session descriptions shaped like the ones libwebrtc produces.
///
/// The fake peer emits these rather than a placeholder string, so every call
/// test drives the real SDP policy instead of stepping around it. A test that
/// wants a description Privio must refuse builds one here too — the refusals
/// and the happy path come from the same generator, which is what stops the
/// "valid" one quietly drifting into something the policy would reject.
String fakeSdp({
  String kind = 'offer',
  String fingerprint = 'sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
  String proto = 'UDP/TLS/RTP/SAVPF',
  bool video = false,
  bool sdes = false,
  bool omitFingerprint = false,
}) {
  final lines = <String>[
    'v=0',
    'o=- 1 2 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'a=$kind',
    if (!omitFingerprint) 'a=fingerprint:$fingerprint',
    'a=setup:actpass',
    'm=audio 9 $proto 111',
    'c=IN IP4 0.0.0.0',
    'a=mid:0',
    if (sdes) 'a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:abcdefghijklmnopqrst',
    'a=rtpmap:111 opus/48000/2',
    if (video) ...[
      'm=video 9 $proto 96',
      'c=IN IP4 0.0.0.0',
      'a=mid:1',
      'a=rtpmap:96 VP8/90000',
    ],
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// The certificate [fakeSdp] commits to by default, normalised the way the
/// policy normalises it.
const String fakeFingerprint = 'sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
