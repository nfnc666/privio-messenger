import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart' as ja;

/// Playing a decrypted voice message.
///
/// The bytes never reach the filesystem: [play] takes them in memory and serves
/// them to the audio engine from there. A decrypted recording sitting in a cache
/// directory would undo most of what encrypting it bought.
abstract interface class VoicePlayer {
  /// Starts (or restarts) playback of [bytes].
  Future<void> play(String messageId, Uint8List bytes, {required String mediaType});

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// 1.0, 1.5 or 2.0.
  Future<void> setSpeed(double speed);

  /// Position within the message currently loaded.
  Stream<VoicePlaybackState> get states;

  Future<void> dispose();
}

class VoicePlaybackState {
  const VoicePlaybackState({
    required this.messageId,
    required this.position,
    required this.duration,
    required this.playing,
    this.completed = false,
  });

  final String messageId;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool completed;

  double get progress => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}

/// Serves decrypted bytes to just_audio without touching the disk.
///
/// `StreamAudioSource` is marked experimental upstream. It is used anyway,
/// deliberately: the alternative APIs all take a file path or a URL, and
/// writing a decrypted recording to a cache directory would undo most of what
/// encrypting it bought. If it is ever removed, this class is the one place
/// that has to change.
// ignore: experimental_member_use
class _MemorySource extends ja.StreamAudioSource {
  _MemorySource(this._bytes, this._contentType);

  final Uint8List _bytes;
  final String _contentType;

  @override
  // ignore: experimental_member_use
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? _bytes.length;
    // ignore: experimental_member_use
    return ja.StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(_bytes.sublist(from, to)),
      contentType: _contentType,
    );
  }
}

class JustAudioVoicePlayer implements VoicePlayer {
  JustAudioVoicePlayer({ja.AudioPlayer? player}) : _player = player ?? ja.AudioPlayer() {
    _player.positionStream.listen((_) => _emit());
    _player.playerStateStream.listen((_) => _emit());
  }

  final ja.AudioPlayer _player;
  final StreamController<VoicePlaybackState> _states =
      StreamController<VoicePlaybackState>.broadcast();

  String? _messageId;

  @override
  Stream<VoicePlaybackState> get states => _states.stream;

  void _emit() {
    final id = _messageId;
    if (id == null || _states.isClosed) return;
    final state = _player.playerState;
    _states.add(
      VoicePlaybackState(
        messageId: id,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        playing: state.playing && state.processingState != ja.ProcessingState.completed,
        completed: state.processingState == ja.ProcessingState.completed,
      ),
    );
  }

  @override
  Future<void> play(String messageId, Uint8List bytes, {required String mediaType}) async {
    _messageId = messageId;
    await _player.setAudioSource(_MemorySource(bytes, mediaType));
    await _player.seek(Duration.zero);
    // Deliberately not awaited: just_audio's play() completes when playback
    // *finishes*, so awaiting it would leave the button showing a spinner for
    // the length of the message.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> stop() async {
    await _player.stop();
    _messageId = null;
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _player.dispose();
  }
}
