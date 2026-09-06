import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../calls/call.dart';
import '../calls/ice_servers.dart';
import '../calls/call_peer.dart';
import '../calls/call_signal.dart';
import '../core/secure_store.dart';
import '../media/attachment.dart';
import 'messaging_service.dart';

/// Runs calls: who is ringing, what a late signal means, and when it is over.
///
/// The media itself is libwebrtc's business, behind [CallPeer]. What lives
/// here is the part that goes wrong — a `hangUp` arriving for a call that
/// already ended, an ICE candidate arriving before the callee picked up, two
/// people calling each other at the same second — and all of it is testable
/// without a microphone or a second machine.
///
/// Signalling rides on the ordinary sealed payloads this app already sends, so
/// the SDP, which lists the addresses each device can be reached on, is
/// encrypted to the other device exactly as a sentence is.
class CallService extends ChangeNotifier {
  CallService({
    required MessagingService messaging,
    required CallPeerFactory peers,
    required Future<CallParty?> Function(String accountId) lookUp,
    IceServerCache? ice,
    SecureStore? store,
    Duration ringTimeout = const Duration(seconds: 45),
    DateTime Function() now = DateTime.now,
    Random? random,
  })  : _messaging = messaging,
        _peers = peers,
        _lookUp = lookUp,
        _ice = ice,
        _store = store,
        _ringTimeout = ringTimeout,
        _now = now,
        _random = random ?? Random.secure();

  final MessagingService _messaging;
  final CallPeerFactory _peers;
  final Future<CallParty?> Function(String accountId) _lookUp;
  final IceServerCache? _ice;
  final SecureStore? _store;
  final Duration _ringTimeout;
  final DateTime Function() _now;
  final Random _random;

  ActiveCall? _call;
  CallPeer? _peer;
  Timer? _ringing;
  StreamSubscription<String>? _candidates;
  StreamSubscription<CallPeerState>? _peerStates;
  StreamSubscription<void>? _video;

  /// The offer this device has been sent and not yet answered.
  String? _pendingOffer;

  /// Calls that are over, newest last.
  ///
  /// A call ends once. Everything after that — a `hangUp` the other side sent
  /// twice, an envelope redelivered because the acknowledgement was lost, an
  /// offer this device is only now draining from a queue it could not reach
  /// while it was asleep — is about a call that is finished, and the phone
  /// must not ring for any of it.
  ///
  /// Bounded, because it is unbounded state on a long-running app otherwise,
  /// and a call from far enough back that it has fallen out of here would have
  /// been refused by [_isStale] long before.
  final List<String> _settled = [];

  /// Serialises outgoing signals; see [_send].
  Future<void> _sending = Future<void>.value();

  /// Candidates that arrived before there was a connection to give them to.
  ///
  /// The other side starts sending paths the moment it has any, which is
  /// routinely before the callee has picked up. Dropping them is not fatal —
  /// WebRTC will find another path or time out — but it costs seconds on every
  /// call, and on a restrictive network it is the difference between connecting
  /// and not.
  final List<String> _earlyCandidates = [];

  List<CallRecord> _history = const [];
  String? _error;

  ActiveCall? get current => _call;

  /// The call's own video surfaces, or null when there is nothing to show.
  ///
  /// Exposed rather than the peer itself, so the screen can draw the picture
  /// without being handed the connection to poke at.
  Widget? get remoteVideo => _peer?.remoteView();
  Widget? get localVideo => _peer?.localView();
  List<CallRecord> get history => List.unmodifiable(_history);
  String? get error => _error;

  /// True when a new call cannot be started because one is already up.
  bool get isBusy => _call?.isLive ?? false;

  /// Reads the call log written by earlier runs.
  Future<void> load() async {
    final raw = await _store?.readCallLog();
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _history = [
        for (final entry in decoded) CallRecord.fromJson(entry as Map<String, dynamic>),
      ];
      notifyListeners();
    } on FormatException {
      // A log we cannot read is a log we drop. It is history, not a message,
      // and refusing to start over it would lock someone out of the screen.
      _history = const [];
    }
  }

  /// Places a call.
  ///
  /// Opens the microphone first: being told "Privio cannot use your
  /// microphone" before anyone's phone rings is better than after.
  Future<void> place(CallParty party, {CallMedia media = CallMedia.audio}) async {
    if (isBusy) return;
    _error = null;
    final call = ActiveCall(
      id: _newCallId(),
      party: party,
      direction: CallDirection.outgoing,
      media: media,
      state: CallState.dialling,
      startedAt: _now(),
      cameraOn: media.isVideo,
    );
    _call = call;
    notifyListeners();

    final peer = await _openPeer(media);
    if (peer == null) return;

    final offer = await peer.createOffer();
    await _send(
      party.username,
      CallSignal(
        callId: call.id,
        action: CallAction.offer,
        media: media,
        sdp: offer,
      ),
    );
    _startRingTimeout();
  }

  /// Picks up the call that is ringing.
  Future<void> accept() async {
    final call = _call;
    final offer = _pendingOffer;
    if (call == null || call.state != CallState.ringing || offer == null) return;
    _cancelRingTimeout();

    final peer = await _openPeer(call.media);
    if (peer == null) return;

    final answer = await peer.answerTo(offer);
    _pendingOffer = null;
    call.state = CallState.connecting;
    notifyListeners();
    await _send(
      call.party.username,
      CallSignal(
        callId: call.id,
        action: CallAction.answer,
        sdp: answer,
      ),
    );
    await _flushEarlyCandidates(peer);
  }

  /// Refuses the call that is ringing.
  Future<void> decline() => _finish(CallEnding.declined, tell: CallAction.decline);

  /// Ends the call that is up, or gives up on one that is still ringing.
  Future<void> hangUp() => _finish(CallEnding.hungUp, tell: CallAction.hangUp);

  Future<void> toggleMute() async {
    final call = _call;
    if (call == null || _peer == null) return;
    call.muted = !call.muted;
    await _peer!.setMuted(call.muted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final call = _call;
    if (call == null || _peer == null) return;
    call.cameraOn = !call.cameraOn;
    await _peer!.setCameraOn(call.cameraOn);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    final call = _call;
    if (call == null || _peer == null) return;
    call.speakerOn = !call.speakerOn;
    await _peer!.setSpeakerOn(call.speakerOn);
    notifyListeners();
  }

  /// Forgets the call history on this device.
  Future<void> clearHistory() async {
    _history = const [];
    await _store?.writeCallLog(null);
    notifyListeners();
  }

  /// Handles one signal that arrived over the sealed channel.
  ///
  /// Everything that can arrive at the wrong moment arrives here, so this is
  /// where the rules about *which* call a signal belongs to live.
  /// [sentAt] is when the server stored the envelope this signal arrived in.
  /// It is what tells a call that is happening now from one that was over
  /// before this device woke up, so it is worth threading through from the
  /// envelope rather than reading the clock here.
  Future<void> handleSignal(
    String senderAccountId,
    CallSignal signal, {
    DateTime? sentAt,
  }) async {
    // A call that has already ended is not started again by anything that
    // arrives afterwards, whichever path it arrives on. This is the one check
    // that has to come before every other: the redelivered offer is the case
    // where everything below would otherwise do exactly the wrong thing.
    if (_settled.contains(signal.callId)) return;

    final call = _call;

    // An offer for the call that is already ringing, arriving a second time.
    // Rebuilding the call from it would restart the ring timeout, which is how
    // a duplicate delivery turns a missed call into one that rings forever.
    if (signal.action == CallAction.offer && call != null && call.id == signal.callId) {
      return;
    }

    // An offer that was already too old to answer when it got here. The device
    // was asleep, or off the network, and the caller has long since given up:
    // ringing now would be a phone going off for a call nobody is on the other
    // end of. It is filed as the missed call it is, and the caller is told
    // nothing, because there is nobody left listening.
    if (signal.action == CallAction.offer && _isStale(sentAt)) {
      await _missed(senderAccountId, signal, sentAt!);
      return;
    }

    // A signal about some other call. The common case is a `hangUp` for a call
    // that already ended on this side, which is not an error and must not
    // touch the call that is up now.
    if (call != null && call.isLive && signal.callId != call.id) {
      if (signal.action == CallAction.offer) {
        await _tellBusy(senderAccountId, signal.callId);
      }
      return;
    }

    switch (signal.action) {
      case CallAction.offer:
        await _ring(senderAccountId, signal);
      case CallAction.answer:
        await _answered(signal);
      case CallAction.ice:
        await _candidate(signal);
      case CallAction.decline:
        await _remoteEnded(CallEnding.declined);
      case CallAction.busy:
        await _remoteEnded(CallEnding.busy);
      case CallAction.hangUp:
        await _remoteEnded(signal.ending ?? CallEnding.hungUp);
    }
  }

  Future<void> _ring(String senderAccountId, CallSignal signal) async {
    if (isBusy) {
      await _tellBusy(senderAccountId, signal.callId);
      return;
    }
    final party = await _lookUp(senderAccountId) ??
        CallParty(accountId: senderAccountId, username: 'unknown');
    _pendingOffer = signal.sdp;
    _earlyCandidates.clear();
    _call = ActiveCall(
      id: signal.callId,
      party: party,
      direction: CallDirection.incoming,
      media: signal.media,
      state: CallState.ringing,
      startedAt: _now(),
    );
    _startRingTimeout();
    notifyListeners();
  }

  /// Whether an offer stored at [sentAt] is older than anyone would still wait.
  ///
  /// The timestamp is the server's and the comparison is against this device's
  /// clock, so the two can disagree. A device running behind produces a
  /// negative age, which is read as "just now" rather than as a reason to
  /// throw the call away — the failure that matters is refusing a live call,
  /// not ringing for a stale one a moment longer than needed.
  bool _isStale(DateTime? sentAt) {
    if (sentAt == null) return false;
    final age = _now().difference(sentAt);
    return age > _ringTimeout;
  }

  /// Files an offer that arrived too late as the missed call it already was.
  Future<void> _missed(String senderAccountId, CallSignal signal, DateTime sentAt) async {
    _markSettled(signal.callId);
    final party = await _lookUp(senderAccountId) ??
        CallParty(accountId: senderAccountId, username: 'unknown');
    await _remember(
      CallRecord(
        id: signal.callId,
        accountId: party.accountId,
        username: party.username,
        direction: CallDirection.incoming,
        media: signal.media,
        // When they called, not when this device found out.
        at: sentAt,
        duration: Duration.zero,
        ending: CallEnding.unanswered,
      ),
    );
    notifyListeners();
  }

  void _markSettled(String callId) {
    if (_settled.contains(callId)) return;
    _settled.add(callId);
    if (_settled.length > _settledLimit) _settled.removeAt(0);
  }

  Future<void> _answered(CallSignal signal) async {
    final call = _call;
    final peer = _peer;
    final sdp = signal.sdp;
    if (call == null || peer == null || sdp == null) return;
    if (call.state != CallState.dialling) return;
    _cancelRingTimeout();
    call.state = CallState.connecting;
    notifyListeners();
    await peer.acceptAnswer(sdp);
    await _flushEarlyCandidates(peer);
  }

  Future<void> _candidate(CallSignal signal) async {
    final candidate = signal.candidate;
    if (candidate == null) return;
    final peer = _peer;
    // Before there is a connection — the callee has not picked up yet — the
    // candidate is kept rather than dropped.
    if (peer == null) {
      _earlyCandidates.add(candidate);
      return;
    }
    await peer.addRemoteCandidate(candidate);
  }

  Future<void> _flushEarlyCandidates(CallPeer peer) async {
    final queued = List<String>.from(_earlyCandidates);
    _earlyCandidates.clear();
    for (final candidate in queued) {
      await peer.addRemoteCandidate(candidate);
    }
  }

  Future<void> _remoteEnded(CallEnding ending) => _finish(ending, tell: null);

  Future<void> _tellBusy(String senderAccountId, String callId) async {
    final party = await _lookUp(senderAccountId);
    if (party == null) return;
    await _send(
      party.username,
      CallSignal(callId: callId, action: CallAction.busy, ending: CallEnding.busy),
    );
    // Their call never rang here, but it happened: it belongs in the log as a
    // call that was not taken, not as nothing at all.
    await _remember(
      CallRecord(
        id: callId,
        accountId: party.accountId,
        username: party.username,
        direction: CallDirection.incoming,
        media: CallMedia.audio,
        at: _now(),
        duration: Duration.zero,
        ending: CallEnding.busy,
      ),
    );
  }

  /// The single way a call ends, whoever ended it and for whatever reason.
  ///
  /// One path rather than one per reason: every early return that skipped
  /// closing the peer would leave the microphone on after the call.
  Future<void> _finish(CallEnding ending, {required CallAction? tell}) async {
    final call = _call;
    if (call == null || !call.isLive) return;
    _cancelRingTimeout();
    call.state = CallState.ended;
    call.ending = ending;

    if (tell != null) {
      // Best effort: the other side may already be gone, and a call that
      // cannot be waved goodbye to still has to end here.
      unawaited(
        _send(call.party.username, CallSignal(callId: call.id, action: tell, ending: ending))
            .catchError((Object _) {}),
      );
    }

    await _closePeer();
    await _remember(
      CallRecord(
        id: call.id,
        accountId: call.party.accountId,
        username: call.party.username,
        direction: call.direction,
        media: call.media,
        at: call.startedAt,
        duration: call.connectedAt == null ? Duration.zero : _now().difference(call.connectedAt!),
        ending: ending,
      ),
    );
    _pendingOffer = null;
    _earlyCandidates.clear();
    _markSettled(call.id);
    notifyListeners();
  }

  Future<CallPeer?> _openPeer(CallMedia media) async {
    // Whatever was already fetched. Deliberately not a fresh request: asking
    // the server for relay details the moment a call starts would tell it a
    // call is starting, and the signalling is sealed precisely so it cannot
    // know that.
    final peer = _peers(_ice?.current.servers ?? const []);
    try {
      await peer.open(media: media);
    } on CallPeerException catch (failure) {
      _error = failure.message;
      await peer.close();
      await _finish(CallEnding.failed, tell: CallAction.hangUp);
      return null;
    }
    _peer = peer;
    _candidates = peer.localCandidates.listen(_sendCandidate);
    _peerStates = peer.states.listen(_onPeerState);
    // A picture turning up is a reason to redraw and nothing else, so it is
    // simply forwarded as a change.
    _video = peer.videoChanged.listen((_) => notifyListeners());
    return peer;
  }

  void _sendCandidate(String candidate) {
    final call = _call;
    if (call == null || !call.isLive) return;
    unawaited(
      _send(
        call.party.username,
        CallSignal(callId: call.id, action: CallAction.ice, candidate: candidate),
      ).catchError((Object _) {}),
    );
  }

  void _onPeerState(CallPeerState state) {
    final call = _call;
    if (call == null || !call.isLive) return;
    switch (state) {
      case CallPeerState.connected:
        call.connectedAt ??= _now();
        call.state = CallState.connected;
        notifyListeners();
      case CallPeerState.failed:
        unawaited(_finish(CallEnding.failed, tell: CallAction.hangUp));
      case CallPeerState.interrupted:
      case CallPeerState.connecting:
      case CallPeerState.idle:
      case CallPeerState.closed:
        break;
    }
  }

  Future<void> _closePeer() async {
    await _candidates?.cancel();
    await _peerStates?.cancel();
    await _video?.cancel();
    _candidates = null;
    _peerStates = null;
    _video = null;
    await _peer?.close();
    _peer = null;
  }

  /// Nobody picked up. Ends it the same way a person would.
  void _startRingTimeout() {
    _cancelRingTimeout();
    _ringing = Timer(_ringTimeout, () {
      unawaited(_finish(CallEnding.unanswered, tell: CallAction.hangUp));
    });
  }

  void _cancelRingTimeout() {
    _ringing?.cancel();
    _ringing = null;
  }

  /// Signals leave in the order they were made.
  ///
  /// They are sealed to a Signal session, which is a ratchet with a state:
  /// starting a second seal before the first has finished is asking one
  /// stateful thing to do two things at once. It also put candidates on the
  /// wire in whatever order the seals happened to finish, and `hangUp` could
  /// overtake the `answer` it was ending.
  Future<void> _send(String username, CallSignal signal) {
    final next =
        _sending.then((_) => _messaging.sendPayload(username, MessagePayload.callSignal(signal)));
    // The chain must survive a failed send: one unreachable candidate cannot be
    // allowed to block every signal after it, including the goodbye.
    _sending = next.then((_) {}).catchError((Object _) {});
    return next;
  }

  Future<void> _remember(CallRecord record) async {
    // Newest first, and capped: a call log is a record of who someone talks to,
    // so keeping it forever is keeping a target on the device forever.
    _history = [record, ..._history].take(_historyLimit).toList(growable: false);
    await _store?.writeCallLog(jsonEncode([for (final r in _history) r.toJson()]));
  }

  String _newCallId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static const int _historyLimit = 200;

  /// How many finished calls are remembered for the sake of refusing late
  /// signals about them. Generous: the entries are a hex string each.
  static const int _settledLimit = 100;

  @override
  void dispose() {
    _cancelRingTimeout();
    unawaited(_closePeer());
    super.dispose();
  }
}
