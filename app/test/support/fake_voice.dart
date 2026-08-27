import 'dart:async';
import 'dart:typed_data';

import 'package:privio/media/voice.dart';
import 'package:privio/media/voice_player.dart';
import 'package:privio/media/voice_recorder.dart';

/// A recorder with no microphone behind it.
///
/// It runs the same state machine the real one does — start, pause, resume,
/// stop, cancel, limits, permission — so the tests exercise the lifecycle the
/// UI drives, without hardware. The one thing it cannot stand in for is the
/// platform encoder, which is why the plugin adapter stays a thin file.
class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder({
    this.permitted = true,
    this.bytes,
    this.duration = const Duration(seconds: 3),
  });

  bool permitted;
  Uint8List? bytes;
  Duration duration;

  final StreamController<VoiceRecorderTick> _ticks =
      StreamController<VoiceRecorderTick>.broadcast();

  bool _recording = false;
  bool _paused = false;
  bool disposed = false;

  /// Set when the recording was thrown away rather than kept — the fake's
  /// stand-in for "the working file was overwritten and deleted".
  bool discarded = false;

  @override
  Stream<VoiceRecorderTick> get ticks => _ticks.stream;

  @override
  bool get isRecording => _recording;

  @override
  bool get isPaused => _paused;

  @override
  Future<bool> ensurePermission() async => permitted;

  @override
  Future<void> start() async {
    if (!permitted) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.permissionDenied,
        'no microphone',
      );
    }
    _recording = true;
    _paused = false;
    discarded = false;
  }

  /// Pushes a tick, as the real recorder does every 100 ms.
  void tick(Duration elapsed, double amplitude) =>
      _ticks.add(VoiceRecorderTick(elapsed: elapsed, amplitude: amplitude));

  @override
  Future<void> pause() async => _paused = true;

  @override
  Future<void> resume() async => _paused = false;

  @override
  Future<VoiceRecording> stop() async {
    if (!_recording) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.unavailable,
        'not recording',
      );
    }
    _recording = false;
    _paused = false;
    if (duration < VoiceLimits.minDuration) {
      throw const VoiceRecorderException(VoiceRecorderFailure.tooShort, 'too short');
    }
    final data = bytes ?? Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    if (data.length > VoiceLimits.maxBytes) {
      throw const VoiceRecorderException(VoiceRecorderFailure.tooLarge, 'too large');
    }
    return VoiceRecording(
      bytes: data,
      duration: duration,
      waveform: compressWaveform(List<double>.generate(120, (i) => (i % 10) / 10)),
      mediaType: 'audio/mp4',
    );
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    _paused = false;
    discarded = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _ticks.close();
  }
}

/// A player that records what it was asked to do.
class FakeVoicePlayer implements VoicePlayer {
  final List<Uint8List> played = [];
  final List<double> speeds = [];
  bool paused = false;
  bool stopped = false;

  final StreamController<VoicePlaybackState> _states =
      StreamController<VoicePlaybackState>.broadcast();

  @override
  Stream<VoicePlaybackState> get states => _states.stream;

  @override
  Future<void> play(String messageId, Uint8List bytes, {required String mediaType}) async {
    played.add(bytes);
    paused = false;
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> dispose() async => _states.close();
}
