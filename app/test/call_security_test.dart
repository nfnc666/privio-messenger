import 'package:flutter_test/flutter_test.dart';
import 'package:privio/calls/call.dart';
import 'package:privio/calls/call_security.dart';
import 'package:privio/calls/call_signal.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/crypto/safety_number.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/services/call_service.dart';

import 'support/fake_call_peer.dart';
import 'support/fake_sdp.dart';
import 'support/fake_server.dart';

/// The properties this file exists to hold, stated once:
///
/// 1. A call's media is DTLS-SRTP or there is no call. Nothing downgrades.
/// 2. Who is on the far end is decided by the key that opened the envelope,
///    never by the account id the server wrote next to it.
/// 3. Every check that fails ends the call and says which one, in words.
///
/// The first half drives [CallService] with a fake peer, because the rules are
/// about the negotiation and not about the audio. The last group uses real
/// libsignal and performs the actual substitution, because "the relay cannot
/// swap the peer" is a claim about cryptography and deserves to be shown
/// rather than asserted.
void main() {
  late FakeServer server;
  late Participant me;
  late List<FakeCallPeer> peers;

  /// Null in the groups that build their own, which is why it is not `late`.
  CallService? calls;

  const alice = CallParty(accountId: 'account-alice', username: 'alice');
  const aliceKey = 'identity-alice';
  const malloryKey = 'identity-mallory';

  /// The transport is real — a Privio participant on a fake server — so what
  /// leaves the device is a sealed envelope and can be counted and inspected.
  /// Only the media peer is a stand-in, because none of this is about audio.
  CallService build({
    bool requireVerified = false,
    VerificationState verification = VerificationState.unverified,
    String? offers,
    String? answers,
  }) {
    peers = [];
    return CallService(
      messaging: me.messaging,
      peers: (_) {
        final peer = FakeCallPeer(offers: offers, answers: answers);
        peers.add(peer);
        return peer;
      },
      lookUp: (id) async => id == alice.accountId ? alice : null,
      verificationOf: (_) async => verification,
      store: InMemorySecureStore(),
    )..setRequireVerified(requireVerified);
  }

  setUp(() async {
    server = FakeServer();
    me = Participant('me', 'account-me', 1);
    await me.join(server);
    final her = Participant('alice', 'account-alice', 1);
    await her.join(server);
  });

  CallSignal offer({String? sdp, String id = 'call-1'}) =>
      CallSignal(callId: id, action: CallAction.offer, sdp: sdp ?? fakeSdp());

  Future<void> ring({
    String? sdp,
    String identityKey = aliceKey,
    PeerTrust trust = PeerTrust.pinned,
    String from = 'account-alice',
  }) =>
      calls!.handleSignal(
        from,
        offer(sdp: sdp),
        sentAt: DateTime.now(),
        senderIdentityKey: identityKey,
        senderTrust: trust,
      );

  tearDown(() {
    calls?.dispose();
    calls = null;
  });

  group('there is no unencrypted call to fall back to', () {
    test('an offer for plain RTP does not ring, it is refused', () async {
      calls = build();

      await ring(sdp: fakeSdp(proto: 'RTP/AVP'));

      expect(calls!.current, isNull, reason: 'the phone never made a sound');
      expect(calls!.failure?.kind, FailureKind.callMediaNotEncrypted);
    });

    test('an offer carrying the media key in the description is refused', () async {
      calls = build();

      await ring(sdp: fakeSdp(sdes: true));

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callMediaNotEncrypted);
    });

    test('an offer that binds the far end to nothing is refused', () async {
      calls = build();

      await ring(sdp: fakeSdp(omitFingerprint: true));

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callFarEndNotBound);
    });

    test('an offer with no description at all is refused', () async {
      calls = build();

      await calls!.handleSignal(
        'account-alice',
        const CallSignal(callId: 'call-1', action: CallAction.offer),
        sentAt: DateTime.now(),
        senderIdentityKey: aliceKey,
      );

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callFarEndNotBound);
    });

    test('this device will not send a description it would itself refuse', () async {
      // Defence in depth: if our own stack ever produced plain RTP, sending it
      // would be offering the other side the downgrade.
      calls = build(offers: fakeSdp(proto: 'RTP/AVP'));

      await calls!.place(alice);

      expect(calls!.current?.state, CallState.ended);
      expect(calls!.failure?.kind, FailureKind.callMediaNotEncrypted);
      expect(
        server.envelopes.where((e) => e['type'] != 'receipt'),
        isEmpty,
        reason: 'the bad description never left the device',
      );
    });

    test('a refused call is still filed — it happened to the user', () async {
      calls = build();

      await ring(sdp: fakeSdp(proto: 'RTP/AVP'));

      expect(calls!.history, hasLength(1));
      expect(calls!.history.single.ending, CallEnding.failed);
      expect(calls!.history.single.username, 'alice');
    });
  });

  group('the far end is the key, not the label the server wrote', () {
    test('a key replaced under this very envelope does not ring', () async {
      // The substitution, as it reaches the call layer: the account id still
      // says alice and the key underneath it is somebody else's.
      calls = build();

      await ring(identityKey: malloryKey, trust: PeerTrust.replaced);

      expect(calls!.current, isNull, reason: 'the phone never rang as alice');
      expect(calls!.failure?.kind, FailureKind.callIdentityChanged);
      expect(calls!.failure?.detail, 'alice', reason: 'the message names who');
    });

    test('an envelope no session authenticated does not ring', () async {
      calls = build();

      await calls!.handleSignal(
        'account-alice',
        offer(),
        sentAt: DateTime.now(),
      );

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callIdentityChanged);
    });

    test('a number that was confirmed and no longer matches does not ring', () async {
      calls = build(verification: VerificationState.changed);

      await ring();

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callIdentityChanged);
    });

    test('an answer from an account that was not dialled ends the call', () async {
      calls = build();
      await calls!.place(alice);
      expect(calls!.current?.state, CallState.dialling);

      await calls!.handleSignal(
        'account-mallory',
        CallSignal(callId: calls!.current!.id, action: CallAction.answer, sdp: fakeSdp()),
        senderIdentityKey: malloryKey,
      );

      expect(calls!.current?.state, CallState.ended);
      expect(calls!.failure?.kind, FailureKind.callWrongParty);
      expect(peers.single.remoteAnswer, isNull, reason: 'their description never reached the stack');
    });

    test('an answer under a replaced key ends the call', () async {
      // The account matches. The key does not. Checking only the first is the
      // hole this closes.
      calls = build();
      await calls!.place(alice);

      await calls!.handleSignal(
        'account-alice',
        CallSignal(callId: calls!.current!.id, action: CallAction.answer, sdp: fakeSdp()),
        senderIdentityKey: malloryKey,
        senderTrust: PeerTrust.replaced,
      );

      expect(calls!.current?.state, CallState.ended);
      expect(calls!.failure?.kind, FailureKind.callIdentityChanged);
      expect(peers.single.remoteAnswer, isNull);
    });

    test('a replayed offer with the certificate swapped ends the call', () async {
      // The same call id arriving twice is ordinarily a redelivery and is
      // ignored. The same call id with another far end in it is not.
      calls = build();
      await ring();
      expect(calls!.current?.state, CallState.ringing);

      await ring(sdp: fakeSdp(fingerprint: 'sha-256 99:88:77:66:55:44:33:22'));

      expect(calls!.current?.state, CallState.ended);
      expect(calls!.failure?.kind, FailureKind.callCertificateChanged);
    });

    test('a genuine redelivery of the same offer is still ignored', () async {
      calls = build();
      await ring();
      final startedAt = calls!.current!.startedAt;

      await ring();

      expect(calls!.current?.state, CallState.ringing, reason: 'still the same call');
      expect(calls!.current!.startedAt, startedAt, reason: 'and the ring timeout did not restart');
      expect(calls!.failure, isNull);
    });

    test('a stranger cannot hang up somebody else\'s call', () async {
      calls = build();
      await ring();
      await calls!.accept();

      await calls!.handleSignal(
        'account-mallory',
        CallSignal(callId: calls!.current!.id, action: CallAction.hangUp),
        senderIdentityKey: malloryKey,
      );

      expect(calls!.failure?.kind, FailureKind.callWrongParty);
    });

    test('a stranger cannot feed paths into a call that is still dialling', () async {
      // The window before the answer arrives: there is no key to check against
      // yet, only the name that was dialled. DTLS would refuse them the media
      // either way, but they would be steering where it is attempted.
      calls = build();
      await calls!.place(alice);

      await calls!.handleSignal(
        'account-mallory',
        CallSignal(callId: calls!.current!.id, action: CallAction.ice, candidate: '{"c":"1"}'),
        senderIdentityKey: malloryKey,
      );

      expect(peers.single.remoteCandidates, isEmpty);
      expect(calls!.failure?.kind, FailureKind.callWrongParty);
    });

    test('a stranger cannot feed network paths into somebody else\'s call', () async {
      calls = build();
      await ring();
      await calls!.accept();

      await calls!.handleSignal(
        'account-mallory',
        CallSignal(callId: calls!.current!.id, action: CallAction.ice, candidate: '{"c":"1"}'),
        senderIdentityKey: malloryKey,
      );

      expect(
        peers.single.remoteCandidates,
        isEmpty,
        reason: 'a path from a stranger is a path to a stranger',
      );
    });
  });

  group('the padlock says what was checked', () {
    test('a pinned but uncompared key is encrypted, not verified', () async {
      calls = build();

      await ring();

      expect(calls!.current!.security, CallSecurity.encrypted);
    });

    test('a compared key is verified', () async {
      calls = build(verification: VerificationState.verified);

      await ring();

      expect(calls!.current!.security, CallSecurity.verified);
    });

    test('an outgoing call to a compared key is verified too', () async {
      calls = build(verification: VerificationState.verified);

      await calls!.place(alice);

      expect(calls!.current!.security, CallSecurity.verified);
    });
  });

  group('only verified contacts, when that is switched on', () {
    test('an unverified caller is turned away with a reason', () async {
      calls = build(requireVerified: true);

      await ring();

      expect(calls!.current, isNull);
      expect(calls!.failure?.kind, FailureKind.callNotVerified);
      expect(calls!.failure?.detail, 'alice');
    });

    test('a verified caller still gets through', () async {
      calls = build(requireVerified: true, verification: VerificationState.verified);

      await ring();

      expect(calls!.current?.state, CallState.ringing);
      expect(calls!.current!.security, CallSecurity.verified);
    });

    test('placing a call to an unverified contact does not open the microphone', () async {
      calls = build(requireVerified: true);

      await calls!.place(alice);

      expect(calls!.current, isNull);
      expect(peers, isEmpty, reason: 'refused before the microphone was touched');
      expect(calls!.failure?.kind, FailureKind.callNotVerified);
    });

    test('off by default — this is a setting, not the rule', () async {
      calls = build();
      expect(calls!.requireVerified, isFalse);

      await ring();

      expect(calls!.current?.state, CallState.ringing);
    });
  });

  group('a relay with the label in its hands', substitution);

  group('the ordinary call still works', () {
    test('an offer that passes every check rings and connects', () async {
      calls = build();

      await ring();
      expect(calls!.current?.state, CallState.ringing);

      await calls!.accept();

      expect(calls!.current?.state, CallState.connecting);
      expect(peers.single.remoteOffer, contains('a=fingerprint:'));
      expect(calls!.failure, isNull);
      expect(
        server.envelopes,
        isNotEmpty,
        reason: 'the answer went out, sealed, as an ordinary payload',
      );
    });
  });
}

/// The claim the whole feature rests on, shown rather than asserted.
///
/// These use real libsignal and a real relay, and they perform the actual
/// substitution: an envelope the server labels as coming from one account,
/// sealed by another account's key. The label is the only thing a malicious
/// relay controls, and the point is that controlling it is not enough.
void substitution() {
  test('a relay cannot put another key behind a name it already knows', () async {
    final server = FakeServer();
    final bob = Participant('bob', 'account-bob', 1);
    final alice = Participant('alice', 'account-alice', 1);
    final mallory = Participant('mallory', 'account-mallory', 1);
    await bob.join(server);
    await alice.join(server);
    await mallory.join(server);

    // Alice writes to Bob once. Bob's device pins her identity key — this is
    // the ordinary trust-on-first-use the whole app runs on.
    await alice.messaging.sendPayload('bob', const MessagePayload.text('hello'));
    final first = await bob.messaging.receive();
    expect(first.messages.single.senderAccountId, 'account-alice');
    expect(first.messages.single.senderTrust, PeerTrust.firstContact);
    final herKey = first.messages.single.senderIdentityKey;
    expect(herKey, isNotNull);

    // Now the relay tries the swap: Mallory seals a call offer for Bob, and the
    // envelope goes out with Alice's name on it. Nothing else is altered — this
    // is exactly the amount of power a signalling server has.
    await mallory.messaging.sendPayload(
      'bob',
      MessagePayload.callSignal(
        CallSignal(callId: 'call-1', action: CallAction.offer, sdp: fakeSdp()),
      ),
    );
    for (final envelope in server.envelopes) {
      if (envelope['senderAccountId'] == 'account-mallory') {
        envelope['senderAccountId'] = 'account-alice';
      }
    }

    final second = await bob.messaging.receive();
    final swapped = second.messages.single;

    // It decrypts — Mallory sealed it properly, and a prekey message carries
    // its own identity key, so libsignal is content. What it cannot do is look
    // like Alice.
    expect(swapped.senderAccountId, 'account-alice', reason: 'the label is the server\'s');
    expect(
      swapped.senderTrust,
      PeerTrust.replaced,
      reason: 'the key under the name is not the key that was pinned',
    );
    expect(swapped.senderIdentityKey, isNot(herKey));

    // And that is what the call layer refuses on.
    final calls = CallService(
      messaging: bob.messaging,
      peers: (_) => FakeCallPeer(),
      lookUp: (_) async => const CallParty(accountId: 'account-alice', username: 'alice'),
      verificationOf: (_) async => VerificationState.unverified,
      store: InMemorySecureStore(),
    );
    addTearDown(calls.dispose);

    await calls.handleSignal(
      swapped.senderAccountId,
      swapped.payload.call!,
      sentAt: swapped.receivedAt,
      senderIdentityKey: swapped.senderIdentityKey,
      senderTrust: swapped.senderTrust,
    );

    expect(calls.current, isNull, reason: 'Bob\'s phone never rang as Alice');
    expect(calls.failure?.kind, FailureKind.callIdentityChanged);
    expect(calls.failure?.detail, 'alice');
  });

  test('the same envelope under its own name is an ordinary call', () async {
    // The control. Without it the test above would pass just as well if calls
    // were broken outright.
    final server = FakeServer();
    final bob = Participant('bob', 'account-bob', 1);
    final mallory = Participant('mallory', 'account-mallory', 1);
    await bob.join(server);
    await mallory.join(server);

    await mallory.messaging.sendPayload(
      'bob',
      MessagePayload.callSignal(
        CallSignal(callId: 'call-1', action: CallAction.offer, sdp: fakeSdp()),
      ),
    );
    final arrived = (await bob.messaging.receive()).messages.single;
    expect(arrived.senderTrust, PeerTrust.firstContact);

    final calls = CallService(
      messaging: bob.messaging,
      peers: (_) => FakeCallPeer(),
      lookUp: (_) async =>
          const CallParty(accountId: 'account-mallory', username: 'mallory'),
      verificationOf: (_) async => VerificationState.unverified,
      store: InMemorySecureStore(),
    );
    addTearDown(calls.dispose);

    await calls.handleSignal(
      arrived.senderAccountId,
      arrived.payload.call!,
      sentAt: arrived.receivedAt,
      senderIdentityKey: arrived.senderIdentityKey,
      senderTrust: arrived.senderTrust,
    );

    expect(calls.current?.state, CallState.ringing, reason: 'a stranger may still call');
    expect(calls.current!.security, CallSecurity.encrypted, reason: 'but never as verified');
  });
}
