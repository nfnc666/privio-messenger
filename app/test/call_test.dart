import 'package:flutter_test/flutter_test.dart';
import 'package:privio/calls/call.dart';
import 'package:privio/calls/call_peer.dart';
import 'package:privio/calls/call_signal.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/services/call_service.dart';

import 'support/fake_call_peer.dart';
import 'support/fake_server.dart';

/// One side of a call: the crypto and transport of a real participant, plus the
/// call machinery on top of it.
class CallEnd {
  CallEnd(this.who, this.peers);

  final Participant who;

  /// The connections handed out, newest last, so a test can drive the one the
  /// service is actually using.
  final List<FakeCallPeer> peers;

  late final CallService calls;

  FakeCallPeer get peer => peers.last;
}

void main() {
  late FakeServer server;
  late CallEnd alice;
  late CallEnd bob;
  late InMemorySecureStore aliceStore;

  /// Everyone whose account id might turn up in an envelope.
  final directory = <String, CallParty>{};

  CallEnd build(
    Participant who, {
    required SecureStore store,
    CallPeerException? peerFails,
    Duration ringTimeout = const Duration(seconds: 45),
  }) {
    final peers = <FakeCallPeer>[];
    final end = CallEnd(who, peers);
    end.calls = CallService(
      messaging: who.messaging,
      peers: () {
        final peer = FakeCallPeer(failsWith: peerFails);
        peers.add(peer);
        return peer;
      },
      lookUp: (accountId) async => directory[accountId],
      store: store,
      ringTimeout: ringTimeout,
    );
    return end;
  }

  /// Moves whatever is queued to whoever it is for, and lets each side's call
  /// service see the signals addressed to it.
  Future<void> settle() async {
    var quiet = 0;
    for (var round = 0; round < 20 && quiet < 2; round++) {
      // Some signals are sent without being waited on — a goodbye has to leave
      // even when the network is gone — so the loop gives them a turn to reach
      // the server before it looks.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      var moved = false;
      for (final end in [alice, bob]) {
        final received = await end.who.messaging.receive();
        for (final incoming in received.messages) {
          final signal = incoming.payload.call;
          if (signal == null) continue;
          moved = true;
          await end.calls.handleSignal(incoming.senderAccountId, signal);
        }
      }
      quiet = moved ? 0 : quiet + 1;
    }
  }

  setUp(() async {
    server = FakeServer();
    final aliceWho = Participant('alice', 'account-alice', 1);
    final bobWho = Participant('bob', 'account-bob', 1);
    await aliceWho.join(server);
    await bobWho.join(server);
    directory
      ..clear()
      ..['account-alice'] = const CallParty(accountId: 'account-alice', username: 'alice')
      ..['account-bob'] = const CallParty(accountId: 'account-bob', username: 'bob');
    aliceStore = InMemorySecureStore();
    alice = build(aliceWho, store: aliceStore);
    bob = build(bobWho, store: InMemorySecureStore());
  });

  tearDown(() {
    alice.calls.dispose();
    bob.calls.dispose();
  });

  const bobParty = CallParty(accountId: 'account-bob', username: 'bob');

  test('the signalling never leaves the device in the clear', () async {
    await alice.calls.place(bobParty);

    expect(server.envelopes, isNotEmpty);
    final onTheWire = server.envelopes.map((envelope) => envelope['content'] as String).join();
    expect(
      onTheWire,
      isNot(contains('sdp-offer')),
      reason: 'an SDP lists the addresses this device can be reached on',
    );
    expect(onTheWire, isNot(contains('offer')));
  });

  test('a call rings, is answered, connects and ends', () async {
    await alice.calls.place(bobParty);
    expect(alice.calls.current!.state, CallState.dialling);

    await settle();
    expect(bob.calls.current, isNotNull);
    expect(bob.calls.current!.state, CallState.ringing);
    expect(bob.calls.current!.party.username, 'alice');
    expect(bob.calls.current!.id, alice.calls.current!.id, reason: 'one call, one id');

    await bob.calls.accept();
    await settle();
    expect(alice.calls.current!.state, CallState.connecting);

    // The media path comes up on both sides.
    alice.peer.connect();
    bob.peer.connect();
    await Future<void>.delayed(Duration.zero);
    expect(alice.calls.current!.state, CallState.connected);
    expect(bob.calls.current!.state, CallState.connected);

    await alice.calls.hangUp();
    await settle();
    expect(alice.calls.current!.state, CallState.ended);
    expect(bob.calls.current!.state, CallState.ended);
    expect(alice.peer.closed, isTrue, reason: 'the microphone is released');
    expect(bob.peer.closed, isTrue);
  });

  test('a declined call is declined on both sides, and logged as such', () async {
    await alice.calls.place(bobParty);
    await settle();

    await bob.calls.decline();
    await settle();

    expect(alice.calls.current!.ending, CallEnding.declined);
    expect(alice.calls.history.single.ending, CallEnding.declined);
    expect(alice.calls.history.single.direction, CallDirection.outgoing);
    expect(bob.calls.history.single.direction, CallDirection.incoming);
    expect(
      bob.calls.history.single.wasMissed,
      isFalse,
      reason: 'a call you turned down is not one you missed',
    );
  });

  test('candidates that arrive before the pick-up are kept, not dropped', () async {
    await alice.calls.place(bobParty);
    await settle();
    expect(bob.calls.current!.state, CallState.ringing);

    // Exactly what the real stack does: the caller starts publishing paths the
    // moment it has any, which is long before anyone picks up.
    alice.peer.offerCandidate('candidate:one');
    alice.peer.offerCandidate('candidate:two');
    await settle();

    await bob.calls.accept();
    await settle();
    expect(
      bob.peer.remoteCandidates,
      ['candidate:one', 'candidate:two'],
      reason: 'dropping these costs seconds on every call',
    );
  });

  test('a second caller is told the line is busy and does not disturb the call', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.accept();
    await settle();
    final ongoing = bob.calls.current!.id;

    final carol = Participant('carol', 'account-carol', 1);
    await carol.join(server);
    directory['account-carol'] = const CallParty(accountId: 'account-carol', username: 'carol');
    final carolEnd = build(carol, store: InMemorySecureStore());
    addTearDown(carolEnd.calls.dispose);

    await carolEnd.calls.place(const CallParty(accountId: 'account-bob', username: 'bob'));
    // Bob sees Carol's offer; Carol sees whatever Bob answers.
    for (final end in [bob, carolEnd, bob, carolEnd]) {
      final received = await end.who.messaging.receive();
      for (final incoming in received.messages) {
        final signal = incoming.payload.call;
        if (signal != null) await end.calls.handleSignal(incoming.senderAccountId, signal);
      }
    }

    expect(bob.calls.current!.id, ongoing, reason: 'the call in progress is untouched');
    expect(bob.calls.current!.state, isNot(CallState.ended));
    expect(carolEnd.calls.current!.ending, CallEnding.busy);
  });

  test('a hang-up for a call that already ended is ignored', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.accept();
    await settle();
    await alice.calls.hangUp();
    await settle();

    // A new call, and then the late goodbye from the old one turns up.
    await alice.calls.place(bobParty);
    await settle();
    final fresh = bob.calls.current!.id;

    await bob.calls.handleSignal(
      'account-alice',
      const CallSignal(callId: 'a-call-from-last-week', action: CallAction.hangUp),
    );
    expect(bob.calls.current!.id, fresh);
    expect(bob.calls.current!.state, CallState.ringing, reason: 'still ringing');
  });

  test('nobody picking up ends the call as unanswered on both sides', () async {
    final patient = Participant('dana', 'account-dana', 1);
    await patient.join(server);
    directory['account-dana'] = const CallParty(accountId: 'account-dana', username: 'dana');
    final impatient = build(
      alice.who,
      store: InMemorySecureStore(),
      ringTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(impatient.calls.dispose);

    await impatient.calls.place(const CallParty(accountId: 'account-dana', username: 'dana'));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(impatient.calls.current!.ending, CallEnding.unanswered);
    expect(impatient.calls.history.single.wasAnswered, isFalse);
    expect(impatient.peer.closed, isTrue);
  });

  test('a refused microphone ends the call instead of ringing silently', () async {
    final refused = build(
      alice.who,
      store: InMemorySecureStore(),
      peerFails: const CallPeerException(
        CallPeerFailure.permissionDenied,
        'Privio cannot use the microphone.',
      ),
    );
    addTearDown(refused.calls.dispose);

    await refused.calls.place(bobParty);

    expect(refused.calls.current!.state, CallState.ended);
    expect(refused.calls.current!.ending, CallEnding.failed);
    expect(refused.calls.error, contains('microphone'));
    await settle();
    expect(bob.calls.current, isNull, reason: 'nobody was ever rung');
  });

  test('a media path that never comes up ends the call rather than hanging', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.accept();
    await settle();

    alice.peer.fail();
    await Future<void>.delayed(Duration.zero);

    expect(alice.calls.current!.state, CallState.ended);
    expect(alice.calls.current!.ending, CallEnding.failed);
  });

  test('the call log survives a relaunch and can be erased', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.decline();
    await settle();
    expect(alice.calls.history, hasLength(1));

    final relaunched = build(alice.who, store: aliceStore);
    addTearDown(relaunched.calls.dispose);
    await relaunched.calls.load();
    expect(relaunched.calls.history.single.username, 'bob');
    expect(relaunched.calls.history.single.ending, CallEnding.declined);

    await relaunched.calls.clearHistory();
    final afterErase = build(alice.who, store: aliceStore);
    addTearDown(afterErase.calls.dispose);
    await afterErase.calls.load();
    expect(afterErase.calls.history, isEmpty);
  });

  test('mute and speaker reach the connection rather than only the screen', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.accept();
    await settle();

    await alice.calls.toggleMute();
    expect(alice.peer.muted, isTrue);
    expect(alice.calls.current!.muted, isTrue);

    await alice.calls.toggleSpeaker();
    expect(alice.peer.speakerOn, isTrue);

    await alice.calls.toggleMute();
    expect(alice.peer.muted, isFalse);
  });

  test('a video call asks for the camera; a voice call does not', () async {
    await alice.calls.place(bobParty, media: CallMedia.video);
    expect(alice.peer.media, CallMedia.video);
    await settle();
    expect(bob.calls.current!.media, CallMedia.video, reason: 'the callee is told what kind');

    await bob.calls.accept();
    expect(bob.peer.media, CallMedia.video);
  });

  test('the picture is offered only once it has arrived', () async {
    await alice.calls.place(bobParty, media: CallMedia.video);
    await settle();
    await bob.calls.accept();
    await settle();

    expect(
      alice.calls.remoteVideo,
      isNull,
      reason: 'a video call connects before any frame does',
    );
    expect(alice.calls.localVideo, isNotNull, reason: 'but this camera is already on');

    alice.peer.showRemotePicture();
    await Future<void>.delayed(Duration.zero);
    expect(alice.calls.remoteVideo, isNotNull);
  });

  test('a voice call never offers a picture', () async {
    await alice.calls.place(bobParty);
    await settle();
    await bob.calls.accept();
    await settle();

    expect(alice.calls.localVideo, isNull);
    expect(alice.calls.remoteVideo, isNull);
  });

  test('the camera can be turned off mid-call, and the picture goes with it', () async {
    await alice.calls.place(bobParty, media: CallMedia.video);
    await settle();
    await bob.calls.accept();
    await settle();
    expect(alice.calls.localVideo, isNotNull);

    await alice.calls.toggleCamera();
    expect(alice.peer.cameraOn, isFalse, reason: 'the track is disabled, not just the icon');
    expect(alice.calls.localVideo, isNull);
    expect(alice.calls.current!.cameraOn, isFalse);
  });

  test('a call that ended offers nothing to draw', () async {
    await alice.calls.place(bobParty, media: CallMedia.video);
    await settle();
    await bob.calls.accept();
    await settle();
    alice.peer.showRemotePicture();
    await Future<void>.delayed(Duration.zero);
    expect(alice.calls.remoteVideo, isNotNull);

    await alice.calls.hangUp();
    expect(
      alice.calls.remoteVideo,
      isNull,
      reason: 'a renderer outliving its stream is a black rectangle',
    );
    expect(alice.calls.localVideo, isNull);
  });

  test('a call signal never shows up as a message', () async {
    await alice.calls.place(bobParty);
    final received = await bob.who.messaging.receive();
    expect(received.messages.single.payload.isControl, isTrue);
    expect(received.messages.single.payload.body, isEmpty);
  });

  test('an unknown caller is rung as unknown rather than not at all', () async {
    directory.remove('account-alice');
    await alice.calls.place(bobParty);
    await settle();

    expect(bob.calls.current, isNotNull);
    expect(bob.calls.current!.party.username, 'unknown');
  });
}
