import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../media/voice_player.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import 'waveform.dart';

/// A voice message in the conversation.
///
/// The waveform and the duration come from the sealed payload, so the bubble is
/// complete before anything is downloaded — tapping play is what fetches the
/// ciphertext, decrypts it in memory and hands the bytes to the player. No
/// decrypted audio is written to disk at any point.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({required this.message, required this.mine, super.key});

  final Message message;
  final bool mine;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  static const List<double> _speeds = [1.0, 1.5, 2.0];

  StreamSubscription<VoicePlaybackState>? _states;
  VoicePlayer? _player;

  double _speed = 1;
  double _progress = 0;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  void _listen(VoicePlayer player) {
    if (_player == player) return;
    _player = player;
    unawaited(_states?.cancel());
    _states = player.states.listen((state) {
      if (!mounted || state.messageId != widget.message.id) return;
      setState(() {
        _playing = state.playing;
        _progress = state.completed ? 0 : state.progress;
      });
    });
  }

  Future<void> _toggle() async {
    final state = PrivioScope.of(context);
    final player = state.services.player;
    _listen(player);

    if (_playing) {
      await player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (_progress > 0) {
      await player.resume();
      if (mounted) setState(() => _playing = true);
      return;
    }

    final attachment = widget.message.attachment;
    if (attachment == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final Uint8List? bytes = await state.conversations.attachmentBytes(attachment);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _loading = false;
        _error = 'Could not open this recording.';
      });
      return;
    }

    try {
      await player.setSpeed(_speed);
      await player.play(widget.message.id, bytes, mediaType: attachment.mediaType);
      if (mounted) setState(() => _loading = false);
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'This device cannot play that recording.';
        });
      }
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    await _player?.setSpeed(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final duration = message.voiceDuration ?? Duration.zero;
    final elapsed = Duration(
      milliseconds: (duration.inMilliseconds * _progress).round(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton.filled(
                      key: const Key('voice-play'),
                      onPressed: message.attachment == null ? null : _toggle,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: PrivioColors.accent,
                        disabledBackgroundColor: PrivioColors.surfaceHigh,
                      ),
                      icon: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 18,
                        color: PrivioColors.background,
                      ),
                      tooltip: _playing ? 'Pause' : 'Play',
                    ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            SizedBox(
              width: 132,
              child: Waveform(
                bars: message.waveform ?? const [],
                progress: _progress,
                pendingColor: widget.mine
                    ? PrivioColors.textSecondary
                    : PrivioColors.textTertiary,
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            Text(
              formatVoiceDuration(_progress > 0 ? elapsed : duration),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: PrivioSpacing.xs),
            _SpeedChip(speed: _speed, onTap: _cycleSpeed),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: PrivioSpacing.xs),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
            ),
          ),
      ],
    );
  }
}

/// 1x / 1.5x / 2x, cycled by tapping. A menu for three values is a menu too
/// many; the label always says what the next tap gives you.
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.speed, required this.onTap});

  final double speed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = speed == 1 ? '1x' : '${speed.toString().replaceAll('.0', '')}x';
    return GestureDetector(
      key: const Key('voice-speed'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceHigh,
          borderRadius: BorderRadius.all(PrivioRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: speed == 1 ? PrivioColors.textSecondary : PrivioColors.accentBright,
              ),
        ),
      ),
    );
  }
}
