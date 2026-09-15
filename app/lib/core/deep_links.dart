import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../services/channel_service.dart';

/// Where incoming links come from.
///
/// An interface rather than the plugin, for the same reason push wake-ups are
/// one: the platform belongs at the composition root, and a test that wants to
/// open a link should not have to stand up a method channel.
abstract interface class IncomingLinks {
  /// The link the app was launched by, if it was launched by one. Null when it
  /// was started normally.
  Future<String?> initial();

  /// Links that arrive while the app is already running.
  Stream<String> get stream;
}

/// Nothing arrives. The default, so a build that never wires a source up still
/// works — and so does every widget test.
class NoIncomingLinks implements IncomingLinks {
  const NoIncomingLinks();

  @override
  Future<String?> initial() async => null;

  @override
  Stream<String> get stream => const Stream.empty();
}

/// Holds the channel a link named until the app is in a state to open it.
///
/// The waiting is the point. A link can arrive:
///
///   - while the app is open and unlocked, where it is acted on at once;
///   - while it is locked, where it has to wait for the passcode;
///   - on a cold start, before the keystore has even been read;
///   - on a device with no account, where it waits through signing up, the
///     licence step and everything else.
///
/// All four end in the same place: the target sits here until something takes
/// it. Holding it in a controller rather than in a route is what makes that
/// work — a route would be thrown away by the sign-in flow, and the person who
/// tapped an invitation would arrive in an empty app wondering where it went.
///
/// **Nothing here joins anything.** It resolves what a link names; joining is a
/// button on a screen somebody looked at.
class DeepLinkController extends ChangeNotifier {
  DeepLinkController({IncomingLinks source = const NoIncomingLinks()})
      : _source = source;

  final IncomingLinks _source;
  StreamSubscription<String>? _subscription;

  ChannelLinkTarget? _pending;

  /// What is waiting to be opened, or null.
  ChannelLinkTarget? get pending => _pending;

  /// The link as it arrived, kept for the message shown when it names nothing.
  String? _raw;
  String? get raw => _raw;

  /// True when a link arrived that is not a Privio link at all.
  bool get unreadable => _raw != null && _pending == null;

  /// Starts listening, and picks up the link the app was launched by.
  ///
  /// Safe to call more than once; the second call does nothing.
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = _source.stream.listen(offer);
    final launch = await _source.initial();
    if (launch != null) offer(launch);
  }

  /// Takes a link, from the platform or from somebody pasting one.
  void offer(String link) {
    _raw = link;
    _pending = ChannelService.parseLink(link);
    notifyListeners();
  }

  /// Clears what was waiting, once something has acted on it.
  ///
  /// Called by whoever opened it rather than by the controller itself: a target
  /// cleared on read would be lost if the screen that read it failed to open.
  void taken() {
    if (_pending == null && _raw == null) return;
    _pending = null;
    _raw = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
