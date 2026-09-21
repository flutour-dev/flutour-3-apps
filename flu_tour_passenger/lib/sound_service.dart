// lib/sound_service.dart — FluTour Passenger
// Generates bell/chime tones in-process (no audio asset files required).
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();

  // ── Chime/bell WAV generator ───────────────────────────────────────────────
  // Produces a natural bell tone using exponential decay + inharmonic overtone.
  static Uint8List _buildChime({
    double frequency = 660,
    double durationSec = 1.0,
    double amplitude = 0.7,
    int sampleRate = 44100,
    double decayTau = 0.40,
  }) {
    final numSamples = (sampleRate * durationSec).round();
    final dataBytes = numSamples * 2;
    final totalBytes = 44 + dataBytes;
    final buf = ByteData(totalBytes);

    _setStr(buf, 0, 'RIFF');
    buf.setUint32(4, totalBytes - 8, Endian.little);
    _setStr(buf, 8, 'WAVE');
    _setStr(buf, 12, 'fmt ');
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little);
    buf.setUint16(22, 1, Endian.little);
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    _setStr(buf, 36, 'data');
    buf.setUint32(40, dataBytes, Endian.little);

    final attackLen = (sampleRate * 0.008).round(); // 8 ms attack
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double env = amplitude * math.exp(-t / decayTau);
      if (i < attackLen) env *= i / attackLen;
      final sample = env * 32767 * (
        0.72 * math.sin(2 * math.pi * frequency * t) +
        0.28 * math.sin(2 * math.pi * frequency * 2.76 * t)
      );
      buf.setInt16(44 + i * 2, sample.round().clamp(-32768, 32767), Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  static void _setStr(ByteData buf, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      buf.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  /// Double chime (A5 → E5) — play when a driver submits a fare offer.
  static Future<void> playDriverOffer() async {
    try {
      await _player.stop();
      await _player.play(BytesSource(_buildChime(frequency: 880, durationSec: 0.9, decayTau: 0.32)));
      await Future.delayed(const Duration(milliseconds: 380));
      await _player.play(BytesSource(_buildChime(frequency: 659, durationSec: 1.1, decayTau: 0.45)));
    } catch (_) {}
  }

  /// Single soft chime (B4) — play when driver sends a counter-offer.
  static Future<void> playCounterOffer() async {
    try {
      await _player.stop();
      await _player.play(BytesSource(_buildChime(frequency: 494, durationSec: 1.0, decayTau: 0.40)));
    } catch (_) {}
  }
}
