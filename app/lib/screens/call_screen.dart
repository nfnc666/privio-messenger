import 'dart:async';

import 'package:flutter/material.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../theme/privio_colors.dart';

/// The screen a call happens on.
///
/// It shows over everything else, because a ringing phone is not something to
/// go looking for in a tab.
class CallScreen extends StatefulWidget {
  const CallScreen({required this.call, super.key});

  final ActiveCall call;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The only thing on this screen that changes on its own is the clock, and
    // there is only a clock once the two are connected. Ticking while it rings
    // rebuilds the screen once a second to draw the same thing.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.call.state == CallState.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final calls = state.services.calls;
    final call = widget.call;
    final theme = Theme.of(context);
    final ringing = call.state == CallState.ringing;

    final remote = call.isVideo ? calls.remoteVideo : null;
    final local = call.isVideo && call.cameraOn ? calls.localVideo : null;

    return Scaffold(
      backgroundColor: PrivioColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The other person's picture, behind everything. Until it arrives
          // this is the ordinary voice-call screen, which is also what an
          // audio call stays as.
          if (remote != null) Positioned.fill(child: remote),
          if (remote != null)
            // Enough of a scrim that white text stays readable over whatever
            // the camera happens to be pointed at.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Held dark long enough at the top to cover the name, the
                    // timer and the line about encryption, which is the one
                    // claim on this screen that has to stay readable.
                    colors: [
                      Colors.black87,
                      Colors.black54,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: [0, 0.16, 0.42, 1],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                // Over a picture the name sits at the top, under the dark end
                // of the scrim. Centred, it landed in the middle of whatever
                // the other camera was pointed at — white text over a bright
                // frame, which is legible until the moment it is not.
                if (remote != null) const SizedBox(height: PrivioSpacing.lg),
                if (remote == null) ...[
                  const Spacer(flex: 2),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: PrivioColors.surface,
                    child: Text(
                      call.party.username.characters.first.toUpperCase(),
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                  const SizedBox(height: PrivioSpacing.lg),
                ],
                Text(call.party.username, style: theme.textTheme.headlineSmall),
                const SizedBox(height: PrivioSpacing.sm),
                Text(_status(call), style: theme.textTheme.bodyMedium),
                const SizedBox(height: PrivioSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 12,
                      // Tertiary grey disappears into a camera feed. Over a
                      // picture this line is lifted rather than left as
                      // decoration nobody can read.
                      color: remote == null ? PrivioColors.textTertiary : Colors.white70,
                    ),
                    const SizedBox(width: PrivioSpacing.xs),
                    Text(
                      'End-to-end encrypted',
                      style: remote == null
                          ? theme.textTheme.labelSmall
                          : theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                Spacer(flex: remote == null ? 3 : 1),
                if (ringing)
                  _RingingControls(
                    onAccept: calls.accept,
                    onDecline: calls.decline,
                  )
                else
                  _InCallControls(
                    muted: call.muted,
                    speakerOn: call.speakerOn,
                    video: call.isVideo,
                    cameraOn: call.cameraOn,
                    onMute: calls.toggleMute,
                    onSpeaker: calls.toggleSpeaker,
                    onCamera: calls.toggleCamera,
                    onHangUp: calls.hangUp,
                  ),
                const SizedBox(height: PrivioSpacing.xxxl),
              ],
            ),
          ),
          // This device's own camera, small and out of the way.
          if (local != null)
            Positioned(
              right: PrivioSpacing.lg,
              // Below the name when that has moved to the top, so the two do
              // not sit on each other on a narrow screen.
              top: MediaQuery.of(context).padding.top +
                  (remote == null ? PrivioSpacing.lg : 108),
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(PrivioRadius.card),
                child: ColoredBox(color: PrivioColors.surface, child: local),
              ),
            ),
        ],
      ),
    );
  }

  /// What is actually true right now, in as many words as that takes.
  String _status(ActiveCall call) => switch (call.state) {
        CallState.dialling => 'Calling…',
        CallState.ringing => call.isVideo ? 'Incoming video call' : 'Incoming call',
        CallState.connecting => 'Connecting…',
        CallState.connected => _elapsed(call),
        CallState.ended => _ended(call.ending),
      };

  String _elapsed(ActiveCall call) {
    final duration = call.durationAt(DateTime.now()) ?? Duration.zero;
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _ended(CallEnding? ending) => switch (ending) {
        CallEnding.declined => 'Declined',
        CallEnding.busy => 'Busy',
        CallEnding.unanswered => 'No answer',
        CallEnding.failed => 'Could not connect',
        _ => 'Call ended',
      };
}

class _RingingControls extends StatelessWidget {
  const _RingingControls({required this.onAccept, required this.onDecline});

  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: Icons.call_end_rounded,
          label: 'Decline',
          colour: PrivioColors.danger,
          onTap: onDecline,
        ),
        _CallButton(
          icon: Icons.call_rounded,
          label: 'Accept',
          colour: PrivioColors.accent,
          onTap: onAccept,
        ),
      ],
    );
  }
}

class _InCallControls extends StatelessWidget {
  const _InCallControls({
    required this.muted,
    required this.speakerOn,
    required this.video,
    required this.cameraOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onCamera,
    required this.onHangUp,
  });

  final bool muted;
  final bool speakerOn;

  /// Whether this call negotiated a camera at all. A voice call gets no camera
  /// button, because turning one on mid-call is a renegotiation this does not
  /// do yet — and a button that silently does nothing is the thing this app
  /// keeps deleting.
  final bool video;
  final bool cameraOn;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onCamera;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: muted ? 'Unmute' : 'Mute',
          colour: muted ? PrivioColors.accent : PrivioColors.surface,
          onTap: onMute,
        ),
        if (video)
          _CallButton(
            icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: cameraOn ? 'Camera' : 'Camera off',
            colour: cameraOn ? PrivioColors.surface : PrivioColors.accent,
            onTap: onCamera,
          ),
        _CallButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          colour: PrivioColors.danger,
          onTap: onHangUp,
        ),
        _CallButton(
          icon: speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: 'Speaker',
          colour: speakerOn ? PrivioColors.accent : PrivioColors.surface,
          onTap: onSpeaker,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final onColour =
        colour == PrivioColors.surface ? PrivioColors.textPrimary : PrivioColors.background;

    // The label is inside the tap target, not under it. It was outside at
    // first, which made "End" a word that did nothing when pressed — the sort
    // of thing that is only annoying until it is the button someone needs.
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () => unawaited(onTap()),
        borderRadius: const BorderRadius.all(PrivioRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PrivioSpacing.md,
            vertical: PrivioSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                child: Icon(icon, color: onColour, size: 28),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
