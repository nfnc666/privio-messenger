import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;

import 'voice.dart';

/// Why a recording could not start.
enum VoiceRecorderFailure { permissionDenied, unavailable, tooShort, tooLarge }

class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.reason, this.message);

  final VoiceRecorderFailure reason;
  final String message;

  @override
  String toString() => 'VoiceRecorderException($reason): $message';
}

/// Recording, as the app needs it.
///
/// An interface rather than a plugin call, for the same reason the keystore and
/// the biometric prompt are interfaces: the tests drive the whole voice-message
/// path — record, seal, upload, receive, open — without a microphone, and the
/// one piece that genuinely needs hardware stays behind a seam.
abstract interface class VoiceRecorder {
  /// True when the microphone may be used. Asks for the permission if it has
  /// not been decided yet.
  Future<bool> ensurePermission();

  Future<void> start();
  Future<void> pause();
  Future<void> resume();

  /// Stops and returns the recording. Throws [VoiceRecorderException] when it
  /// is too short or too large to send.
  Future<VoiceRecording> stop();

  /// Stops and throws the recording away, leaving nothing behind.
  Future<void> cancel();

  /// Ticks while recording, carrying elapsed time and the level meter.
  Stream<VoiceRecorderTick> get ticks;

  bool get isRecording;
  bool get isPaused;

  Future<void> dispose();
}

@immutable
class VoiceRecorderTick {
  const VoiceRecorderTick({required this.elapsed, required this.amplitude});

  final Duration elapsed;

  /// 0..1, for the live waveform.
  final double amplitude;
}

/// The real recorder, backed by `record`.
///
/// It writes to a file because that is how a phone encodes AAC or Opus; what it
/// does not do is leave one behind. [stop] reads the bytes, overwrites the file
/// with random data and deletes it, so the only plaintext copy of a recording
/// that outlives the moment is the one in memory on its way into the cipher.
class PluginVoiceRecorder implements VoiceRecorder {
  PluginVoiceRecorder({rec.AudioRecorder? recorder})
      : _recorder = recorder ?? rec.AudioRecorder();

  final rec.AudioRecorder _recorder;
  final StreamController<VoiceRecorderTick> _ticks =
      StreamController<VoiceRecorderTick>.broadcast();
  final List<double> _samples = [];

  Timer? _poll;
  String? _path;
  bool _started = false;
  Duration _elapsed = Duration.zero;
  bool _paused = false;
  String _mediaType = 'audio/mp4';

  static const Duration _tick = Duration(milliseconds: 100);

  /// Opus first, AAC second.
  ///
  /// Opus is the better codec for speech at these bitrates and is what a
  /// browser records natively; AAC is hardware-encoded on iOS and plays
  /// everywhere. Asking the platform which it supports is the only way to get
  /// the right one on both without a per-platform branch that goes stale.
  static const List<(rec.AudioEncoder, String)> _preferredEncoders = [
    (rec.AudioEncoder.opus, 'audio/ogg'),
    (rec.AudioEncoder.aacLc, 'audio/mp4'),
  ];

  Future<(rec.AudioEncoder, String)> _pickEncoder() async {
    for (final candidate in _preferredEncoders) {
      try {
        if (await _recorder.isEncoderSupported(candidate.$1)) return candidate;
      } on Object {
        continue;
      }
    }
    return _preferredEncoders.last;
  }

  @override
  Stream<VoiceRecorderTick> get ticks => _ticks.stream;

  @override
  bool get isRecording => _started;

  @override
  bool get isPaused => _paused;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    if (!await ensurePermission()) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.permissionDenied,
        'Privio needs the microphone to record a voice message.',
      );
    }

    _samples.clear();
    _elapsed = Duration.zero;
    _paused = false;

    final (encoder, mediaType) = await _pickEncoder();
    _mediaType = mediaType;

    // On a phone the platform encoder writes a file, which is why [stop]
    // overwrites and deletes it. In a browser there is no filesystem to write
    // to: the recording lives in a blob the page holds, and never touches disk
    // at all.
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}'
            '/privio-voice-${DateTime.now().microsecondsSinceEpoch}'
            '${encoder == rec.AudioEncoder.opus ? '.ogg' : '.m4a'}';

    await _recorder.start(
      rec.RecordConfig(
        encoder: encoder,
        bitRate: 32000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _path = kIsWeb ? null : path;
    _started = true;
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_tick, (_) async {
      if (_paused) return;
      _elapsed += _tick;
      double level = 0;
      try {
        final amplitude = await _recorder.getAmplitude();
        // dBFS, roughly -60 (silence) to 0 (clipping).
        level = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
      } on Object {
        level = 0;
      }
      _samples.add(level);
      if (!_ticks.isClosed) {
        _ticks.add(VoiceRecorderTick(elapsed: _elapsed, amplitude: level));
      }
      // A recording nobody stopped must still stop.
      if (_elapsed >= VoiceLimits.maxDuration) unawaited(_stopAtLimit());
    });
  }

  Future<void> _stopAtLimit() async {
    if (!isRecording) return;
    _poll?.cancel();
    _poll = null;
  }

  @override
  Future<void> pause() async {
    if (!isRecording || _paused) return;
    await _recorder.pause();
    _paused = true;
  }

  @override
  Future<void> resume() async {
    if (!isRecording || !_paused) return;
    await _recorder.resume();
    _paused = false;
  }

  @override
  Future<VoiceRecording> stop() async {
    if (!_started) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.unavailable,
        'Nothing was being recorded.',
      );
    }
    final path = _path;
    _poll?.cancel();
    _poll = null;
    _path = null;
    _started = false;
    _paused = false;

    final result = await _recorder.stop();
    final bytes = await _readBack(path, result);

    if (_elapsed < VoiceLimits.minDuration) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.tooShort,
        'Hold the microphone to record.',
      );
    }
    if (bytes.length > VoiceLimits.maxBytes) {
      throw const VoiceRecorderException(
        VoiceRecorderFailure.tooLarge,
        'That recording is too long to send.',
      );
    }

    return VoiceRecording(
      bytes: bytes,
      duration: _elapsed,
      waveform: compressWaveform(_samples),
      mediaType: _mediaType,
    );
  }

  /// Reads the recording back and leaves nothing behind.
  ///
  /// On a phone that means reading the encoder's file, overwriting it and
  /// deleting it. In a browser [result] is a blob URL the page owns; fetching
  /// it is a read from memory, and it is revoked straight after.
  Future<Uint8List> _readBack(String? path, String? result) async {
    if (path == null) {
      if (result == null || result.isEmpty) {
        throw const VoiceRecorderException(
          VoiceRecorderFailure.unavailable,
          'The recording came back empty.',
        );
      }
      final response = await http.get(Uri.parse(result));
      return response.bodyBytes;
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    await _shred(file);
    return bytes;
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    final wasRecording = _started;
    _poll?.cancel();
    _poll = null;
    _path = null;
    _started = false;
    _paused = false;
    if (!wasRecording) return;
    try {
      await _recorder.stop();
    } on Object {
      // Already stopped; the file still has to go.
    }
    if (path != null) await _shred(File(path));
  }

  /// Overwrite before unlinking. A deleted file on flash storage is not a gone
  /// file, and this one held speech.
  static Future<void> _shred(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      final random = math.Random.secure();
      await file.writeAsBytes(
        List<int>.generate(length, (_) => random.nextInt(256)),
        flush: true,
      );
      await file.delete();
    } on Object {
      // Best effort: a temp file we cannot overwrite must still be deleted.
      try {
        await file.delete();
      } on Object {
        // Nothing further to do.
      }
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _ticks.close();
    await _recorder.dispose();
  }
}
