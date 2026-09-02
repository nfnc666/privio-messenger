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

    return Scaffold(
      backgroundColor: PrivioColors.background,
      body: SafeArea(
        child: Column(
          children: [
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
            Text(call.party.username, style: theme.textTheme.headlineSmall),
            const SizedBox(height: PrivioSpacing.sm),
            Text(_status(call), style: theme.textTheme.bodyMedium),
            const SizedBox(height: PrivioSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 12, color: PrivioColors.textTertiary),
                const SizedBox(width: PrivioSpacing.xs),
                Text(
                  'End-to-end encrypted',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const Spacer(flex: 3),
            if (ringing)
              _RingingControls(
                onAccept: calls.accept,
                onDecline: calls.decline,
              )
            else
              _InCallControls(
                muted: call.muted,
                speakerOn: call.speakerOn,
                onMute: calls.toggleMute,
                onSpeaker: calls.toggleSpeaker,
                onHangUp: calls.hangUp,
              ),
            const SizedBox(height: PrivioSpacing.xxxl),
          ],
        ),
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
    required this.onMute,
    required this.onSpeaker,
    required this.onHangUp,
  });

  final bool muted;
  final bool speakerOn;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
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
