// lib/sound_service.dart — FluTour Passenger
// Generates bell/chime tones and plays via temp file (reliable on iOS + Android).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class SoundService {
  static AudioPlayer? _player;
  static bool _sessionConfigured = false;

  static Future<AudioPlayer> _getPlayer() async {
    if (_player == null) {
      _player = AudioPlayer();
    }
    if (!_sessionConfigured) {
      _sessionConfigured = true;
      try {
        await _player!.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ));
      } catch (_) {}
    }
    return _player!;
  }

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

    final attackLen = (sampleRate * 0.008).round();
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
    for (int i = 0; i < s.length; i++) buf.setUint8(offset + i, s.codeUnitAt(i));
  }

  static Future<String> _writeTempWav(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.wav');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Double chime (A5 → E5) — play when a driver submits a fare offer.
  static Future<void> playDriverOffer() async {
    try {
      final player = await _getPlayer();
      await player.stop();
      final p1 = await _writeTempWav(
          _buildChime(frequency: 880, durationSec: 0.9, decayTau: 0.32), 'offer1');
      await player.play(DeviceFileSource(p1));
      await Future.delayed(const Duration(milliseconds: 420));
      final p2 = await _writeTempWav(
          _buildChime(frequency: 659, durationSec: 1.1, decayTau: 0.45), 'offer2');
      await player.play(DeviceFileSource(p2));
    } catch (_) {}
  }

  /// Single soft chime (B4) — play when driver sends a counter-offer.
  static Future<void> playCounterOffer() async {
    try {
      final player = await _getPlayer();
      await player.stop();
      final path = await _writeTempWav(
          _buildChime(frequency: 494, durationSec: 1.0, decayTau: 0.40), 'counter');
      await player.play(DeviceFileSource(path));
    } catch (_) {}
  }
}
