import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Small, deterministic PCM fixture accepted by the real native decoder.
Future<File> writeTestWav(File file, {int seconds = 12}) async {
  const sampleRate = 16000;
  final samples = sampleRate * seconds;
  final bytes = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    bytes.setInt16(
      44 + i * 2,
      (sin(2 * pi * 440 * i / sampleRate) * 1000).round(),
      Endian.little,
    );
  }
  return file.writeAsBytes(bytes.buffer.asUint8List());
}
