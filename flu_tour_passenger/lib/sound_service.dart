// lib/sound_service.dart — FluTour Passenger
// Generates and plays beep tones in-process (no audio asset files required).
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();

  static Uint8List _buildWav({
    double frequency = 660,
    double durationSec = 0.3,
    double amplitude = 0.75,
    int sampleRate = 44100,
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

    final fadeLen = (sampleRate * 0.04).round();
    for (int i = 0; i < numSamples; i++) {
      double env = amplitude;
      if (i < fadeLen) env *= i / fadeLen;
      if (i > numSamples - fadeLen) env *= (numSamples - i) / fadeLen;
      final s = (env * 32767 * math.sin(2 * math.pi * frequency * i / sampleRate)).round();
      buf.setInt16(44 + i * 2, s.clamp(-32768, 32767), Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  static void _setStr(ByteData buf, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      buf.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  /// Two descending beeps — play when a driver submits a fare offer.
  static Future<void> playDriverOffer() async {
    try {
      await _player.stop();
      await _player.play(BytesSource(_buildWav(frequency: 880, durationSec: 0.2)));
      await Future.delayed(const Duration(milliseconds: 220));
      await _player.play(BytesSource(_buildWav(frequency: 660, durationSec: 0.3)));
    } catch (_) {}
  }

  /// Single mid beep — play when driver sends a counter-offer.
  static Future<void> playCounterOffer() async {
    try {
      await _player.stop();
      await _player.play(BytesSource(_buildWav(frequency: 770, durationSec: 0.4)));
    } catch (_) {}
  }
}
