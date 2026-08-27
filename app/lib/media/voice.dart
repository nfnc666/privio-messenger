import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What a finished recording is, before it is sealed.
///
/// It exists in memory only. Nothing here is written to disk in the clear: the
/// recorder deletes its working file the moment these bytes have been read.
@immutable
class VoiceRecording {
  const VoiceRecording({
    required this.bytes,
    required this.duration,
    required this.waveform,
    required this.mediaType,
  });

  final Uint8List bytes;
  final Duration duration;

  /// One amplitude per slice, 0..1, sampled while recording.
  ///
  /// Drawn from the recorder's own level meter rather than by decoding the
  /// audio, so the bubble can show a shape without anything having to decode a
  /// file it may not be able to play.
  final List<double> waveform;

  /// `audio/mp4` (AAC) or `audio/ogg` (Opus), whichever the platform recorded.
  final String mediaType;

  int get byteSize => bytes.length;
}

/// The limits a voice message is held to.
///
/// Both are enforced on the sending device, before anything is uploaded. The
/// duration cap keeps a forgotten recording from becoming a 40 MB upload; the
/// size cap catches a codec that ignores it.
abstract final class VoiceLimits {
  static const Duration maxDuration = Duration(minutes: 5);

  /// Roughly 32 kbit/s for five minutes, with room to spare.
  static const int maxBytes = 2 * 1024 * 1024;

  /// Below this a recording is a slip of the finger, not a message.
  static const Duration minDuration = Duration(milliseconds: 700);

  /// How many bars the waveform is reduced to before it is sent.
  ///
  /// Fixed, and deliberately coarse: the shape of someone's speech is
  /// information, and a hundred bars carry more of it than a bubble needs.
  static const int waveformBars = 48;
}

/// Reduces a sampled amplitude series to [VoiceLimits.waveformBars] bars.
///
/// Averaging rather than sampling, so a spike does not decide a bar, and the
/// result is normalised so a quiet recording still looks like speech.
List<double> compressWaveform(List<double> samples, {int bars = VoiceLimits.waveformBars}) {
  if (samples.isEmpty) return List<double>.filled(bars, 0);

  final out = List<double>.filled(bars, 0);
  for (var i = 0; i < bars; i++) {
    final start = (i * samples.length / bars).floor();
    final end = math.max(start + 1, ((i + 1) * samples.length / bars).floor());
    var sum = 0.0;
    for (var j = start; j < end && j < samples.length; j++) {
      sum += samples[j];
    }
    out[i] = sum / (end - start);
  }

  final peak = out.fold<double>(0, math.max);
  if (peak <= 0) return out;
  return [for (final value in out) (value / peak).clamp(0.0, 1.0)];
}
