import 'dart:async';

import 'package:flutter/material.dart';

import '../media/voice.dart';
import '../media/voice_recorder.dart';
import '../theme/privio_colors.dart';
import 'waveform.dart';

/// Where a recording is in its life.
enum VoiceComposerStage { idle, recording, paused, preview }

/// The recording strip, shown inside the composer row while a voice message is
/// being made.
///
/// It deliberately renders *only the middle* of that row, not the row itself.
/// The microphone button that started the hold has to stay mounted for the
/// release to arrive — a gesture whose owner is swapped out mid-press is a
/// gesture that never ends.
///
/// The gesture is the one people already know: hold the microphone, slide left
/// to throw it away, let go to stop. Everything that gesture cannot express —
/// pausing, listening back, changing your mind after the fact — is a button,
/// because a hidden gesture is not a feature.
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    required this.recorder,
    required this.onSend,
    required this.onPermissionDenied,
    required this.onFailure,
    super.key,
    this.preview,
  });

  final VoiceRecorder recorder;

  /// Called with a finished recording the user chose to send.
  final void Function(VoiceRecording recording) onSend;

  final VoidCallback onPermissionDenied;
  final void Function(String message) onFailure;

  /// Plays a recording back before it is sent. Null disables the preview
  /// player's play button rather than hiding the preview.
  final Future<void> Function(VoiceRecording recording)? preview;

  @override
  State<VoiceComposer> createState() => VoiceComposerState();
}

class VoiceComposerState extends State<VoiceComposer> {
  StreamSubscription<VoiceRecorderTick>? _ticks;

  VoiceComposerStage _stage = VoiceComposerStage.idle;
  Duration _elapsed = Duration.zero;
  final List<double> _live = [];
  VoiceRecording? _recorded;
  double _slide = 0;

  VoiceComposerStage get stage => _stage;
  bool get isBusy => _stage != VoiceComposerStage.idle;
  bool get isPreviewing => _stage == VoiceComposerStage.preview;

  /// Sends the previewed recording. Called by the row's send button.
  void send() => _send();

  /// How far left the finger has to travel before the recording is dropped.
  static const double _cancelDistance = 96;

  @override
  void dispose() {
    unawaited(_ticks?.cancel());
    super.dispose();
  }

  // --- Recording ------------------------------------------------------------

  Future<void> start() async {
    if (_stage != VoiceComposerStage.idle) return;
    try {
      await widget.recorder.start();
    } on VoiceRecorderException catch (failure) {
      if (failure.reason == VoiceRecorderFailure.permissionDenied) {
        widget.onPermissionDenied();
      } else {
        widget.onFailure(failure.message);
      }
      return;
    } on Object {
      widget.onFailure('The microphone is not available right now.');
      return;
    }

    setState(() {
      _stage = VoiceComposerStage.recording;
      _elapsed = Duration.zero;
      _slide = 0;
      _live.clear();
      _recorded = null;
    });

    _ticks = widget.recorder.ticks.listen((tick) {
      if (!mounted) return;
      setState(() {
        _elapsed = tick.elapsed;
        _live.add(tick.amplitude);
        if (_live.length > 240) _live.removeAt(0);
      });
      // A recording nobody stopped stops itself, and lands in the preview
      // rather than being sent behind the user's back.
      if (tick.elapsed >= VoiceLimits.maxDuration) unawaited(stopForPreview());
    });
  }

  Future<void> pause() async {
    if (_stage != VoiceComposerStage.recording) return;
    await widget.recorder.pause();
    if (mounted) setState(() => _stage = VoiceComposerStage.paused);
  }

  Future<void> resume() async {
    if (_stage != VoiceComposerStage.paused) return;
    await widget.recorder.resume();
    if (mounted) setState(() => _stage = VoiceComposerStage.recording);
  }

  /// Stops and shows the preview, so nothing is sent without being seen.
  Future<void> stopForPreview() async {
    if (_stage == VoiceComposerStage.idle || _stage == VoiceComposerStage.preview) return;
    await _ticks?.cancel();
    _ticks = null;
    try {
      final recording = await widget.recorder.stop();
      if (!mounted) return;
      setState(() {
        _recorded = recording;
        _stage = VoiceComposerStage.preview;
      });
    } on VoiceRecorderException catch (failure) {
      if (mounted) setState(() => _stage = VoiceComposerStage.idle);
      widget.onFailure(failure.message);
    } on Object {
      if (mounted) setState(() => _stage = VoiceComposerStage.idle);
      widget.onFailure('That recording could not be saved.');
    }
  }

  /// Throws the recording away. The recorder overwrites and deletes its working
  /// file; nothing of it is left.
  Future<void> cancel() async {
    await _ticks?.cancel();
    _ticks = null;
    await widget.recorder.cancel();
    if (!mounted) return;
    setState(() {
      _stage = VoiceComposerStage.idle;
      _recorded = null;
      _live.clear();
      _elapsed = Duration.zero;
      _slide = 0;
    });
  }

  void _send() {
    final recording = _recorded;
    if (recording == null) return;
    widget.onSend(recording);
    setState(() {
      _stage = VoiceComposerStage.idle;
      _recorded = null;
      _live.clear();
      _elapsed = Duration.zero;
    });
  }

  // --- The hold gesture -----------------------------------------------------

  void onDragUpdate(double dx) {
    if (_stage != VoiceComposerStage.recording) return;
    setState(() => _slide = (_slide - dx).clamp(0, _cancelDistance * 1.5));
    if (_slide >= _cancelDistance) unawaited(cancel());
  }

  Future<void> onHoldReleased() async {
    if (_stage == VoiceComposerStage.recording) await stopForPreview();
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
        VoiceComposerStage.idle => const SizedBox.shrink(),
        VoiceComposerStage.recording || VoiceComposerStage.paused => _RecordingStrip(
            elapsed: _elapsed,
            bars: _live,
            paused: _stage == VoiceComposerStage.paused,
            slideProgress: (_slide / _cancelDistance).clamp(0.0, 1.0),
            onCancel: cancel,
            onPauseResume: _stage == VoiceComposerStage.paused ? resume : pause,
            onStop: stopForPreview,
          ),
        VoiceComposerStage.preview => _PreviewStrip(
            recording: _recorded!,
            onDelete: cancel,
            onPlay: widget.preview == null
                ? null
                : () => unawaited(widget.preview!(_recorded!)),
          ),
      };
}

class _RecordingStrip extends StatelessWidget {
  const _RecordingStrip({
    required this.elapsed,
    required this.bars,
    required this.paused,
    required this.slideProgress,
    required this.onCancel,
    required this.onPauseResume,
    required this.onStop,
  });

  final Duration elapsed;
  final List<double> bars;
  final bool paused;
  final double slideProgress;
  final VoidCallback onCancel;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = VoiceLimits.maxDuration - elapsed;

    return Row(
      key: const Key('voice-recording-strip'),
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.delete_outline_rounded, color: PrivioColors.danger),
            tooltip: 'Cancel',
          ),
          _RecordingDot(paused: paused),
          const SizedBox(width: PrivioSpacing.sm),
          SizedBox(
            width: 46,
            child: Text(
              formatVoiceDuration(elapsed),
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Opacity(
              // Fades as the finger slides left, so "let go now and it is gone"
              // is visible rather than a rule to remember.
              opacity: 1 - slideProgress * 0.75,
              child: slideProgress > 0.05
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          size: 14,
                          color: PrivioColors.textTertiary,
                        ),
                        const SizedBox(width: PrivioSpacing.xs),
                        Text('Slide to cancel', style: theme.textTheme.bodySmall),
                      ],
                    )
                  : Waveform(bars: bars, progress: 1, playedColor: PrivioColors.accent),
            ),
          ),
          const SizedBox(width: PrivioSpacing.sm),
          if (remaining <= const Duration(seconds: 30))
            Padding(
              padding: const EdgeInsets.only(right: PrivioSpacing.sm),
              child: Text(
                '-${formatVoiceDuration(remaining.isNegative ? Duration.zero : remaining)}',
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.warning),
              ),
            ),
          IconButton(
            onPressed: onPauseResume,
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            tooltip: paused ? 'Resume' : 'Pause',
          ),
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, color: PrivioColors.accent),
            tooltip: 'Stop',
          ),
      ],
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.paused});

  final bool paused;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.paused
          ? const AlwaysStoppedAnimation<double>(0.35)
          : Tween<double>(begin: 0.35, end: 1).animate(_pulse),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: PrivioColors.danger, shape: BoxShape.circle),
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.recording,
    required this.onDelete,
    required this.onPlay,
  });

  final VoiceRecording recording;
  final VoidCallback onDelete;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('voice-preview-strip'),
        children: [
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: PrivioColors.danger),
            tooltip: 'Delete recording',
          ),
          IconButton(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: 'Listen back',
          ),
          Expanded(child: Waveform(bars: recording.waveform)),
          const SizedBox(width: PrivioSpacing.sm),
          Text(
            formatVoiceDuration(recording.duration),
            style: theme.textTheme.labelLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
