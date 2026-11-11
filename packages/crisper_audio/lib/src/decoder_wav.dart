// SPDX-License-Identifier: MIT
part of 'decoder.dart';

final class _WavDecoder implements PcmDecoder {
  _WavDecoder(
    this.reader,
    this.sampleRate,
    this.channels,
    this.totalFrames,
    this.dataOffset,
    this.blockAlign,
    this.bits,
    this.floating,
  );
  final _FileReader reader;
  @override
  final int sampleRate;
  @override
  final int channels;
  @override
  final int totalFrames;
  final int dataOffset;
  final int blockAlign;
  final int bits;
  final bool floating;
  int _position = 0;
  bool _disposed = false;
  Object? _failure;
  final Uint8List _input = Uint8List(_maxReadFrames * 2 * 8);

  static _WavDecoder open(_FileReader reader) {
    final riff = ByteData.sublistView(reader.bytes(0, 12));
    final end = riff.getUint32(4, Endian.little) + 8;
    if (end < 12 || end > reader.length) {
      throw const FormatException('RIFF size exceeds file bounds');
    }
    int? rate, channels, align, bits, tag, dataOffset, dataBytes;
    var at = 12;
    while (at + 8 <= end) {
      final chunk = reader.bytes(at, 8);
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      if (size > end - at - 8) {
        throw const FormatException('WAV chunk exceeds RIFF bounds');
      }
      if (_matches(chunk, 0, 'fmt ')) {
        if (tag != null || size < 16) {
          throw const FormatException('Invalid WAV format chunk');
        }
        final fmt = ByteData.sublistView(
          reader.bytes(at + 8, math.min(size, 40)),
        );
        tag = fmt.getUint16(0, Endian.little);
        channels = fmt.getUint16(2, Endian.little);
        rate = fmt.getUint32(4, Endian.little);
        align = fmt.getUint16(12, Endian.little);
        bits = fmt.getUint16(14, Endian.little);
        if (tag == 0xfffe) {
          if (size < 40 ||
              fmt.getUint16(16, Endian.little) < 22 ||
              fmt.getUint16(18, Endian.little) != bits) {
            throw const FormatException('Unsupported WAV extensible format');
          }
          const guidTail = [
            0,
            0,
            0,
            0,
            0x10,
            0,
            0x80,
            0,
            0,
            0xaa,
            0,
            0x38,
            0x9b,
            0x71,
          ];
          for (var i = 0; i < guidTail.length; i++) {
            if (fmt.getUint8(26 + i) != guidTail[i]) {
              throw const FormatException('Unsupported WAV codec GUID');
            }
          }
          tag = fmt.getUint16(24, Endian.little);
        }
      } else if (_matches(chunk, 0, 'data') && dataOffset == null) {
        dataOffset = at + 8;
        dataBytes = size;
      }
      at += 8 + size + (size & 1);
    }
    if (rate == null ||
        rate < 8000 ||
        rate > 384000 ||
        channels == null ||
        channels < 1 ||
        channels > 2 ||
        align == null ||
        bits == null ||
        dataOffset == null ||
        dataBytes == null ||
        (tag != 1 && tag != 3) ||
        (tag == 1 && !const [8, 16, 24, 32].contains(bits)) ||
        (tag == 3 && !const [32, 64].contains(bits)) ||
        align != channels * (bits ~/ 8) ||
        dataBytes % align != 0) {
      throw const FormatException('WAV must contain mono/stereo PCM or float');
    }
    return _WavDecoder(
      reader,
      rate,
      channels,
      dataBytes ~/ align,
      dataOffset,
      align,
      bits,
      tag == 3,
    );
  }

  @override
  String get format => 'wav';
  @override
  int get positionFrames => _position;

  void _checkOpen() {
    if (_disposed) throw StateError('Decoder has been disposed');
    if (_failure != null) throw StateError('Decoder failed: $_failure');
  }

  @override
  int readFrames(Pointer<Float> destination, int maxFrames) {
    _checkOpen();
    if (maxFrames < 0) throw RangeError.value(maxFrames, 'maxFrames');
    final count = math.min(
      math.min(maxFrames, _maxReadFrames),
      totalFrames - _position,
    );
    if (count == 0) return 0;
    if (destination == nullptr) throw ArgumentError.notNull('destination');
    try {
      reader.readInto(
        dataOffset + _position * blockAlign,
        _input,
        0,
        count * blockAlign,
      );
      final bytes = ByteData.sublistView(_input);
      final out = destination.asTypedList(count * channels);
      for (var i = 0; i < out.length; i++) {
        final at = i * (bits ~/ 8);
        double value;
        if (floating) {
          value = bits == 32
              ? bytes.getFloat32(at, Endian.little)
              : bytes.getFloat64(at, Endian.little);
          if (!value.isFinite) {
            throw const FormatException('WAV contains non-finite PCM');
          }
        } else {
          value = switch (bits) {
            8 => (_input[at] - 128) / 128.0,
            16 => bytes.getInt16(at, Endian.little) / 32768.0,
            24 =>
              ((_input[at] | (_input[at + 1] << 8) | (_input[at + 2] << 16))
                      .toSigned(24)) /
                  8388608.0,
            32 => bytes.getInt32(at, Endian.little) / 2147483648.0,
            _ => throw StateError('Unsupported PCM sample size'),
          };
        }
        out[i] = value;
        if (!out[i].isFinite) {
          throw const FormatException('WAV sample exceeds float PCM range');
        }
      }
      _position += count;
      return count;
    } catch (error) {
      _failure = error;
      rethrow;
    }
  }

  @override
  void seek(int sourceFrame) {
    _checkOpen();
    if (sourceFrame < 0) throw RangeError.value(sourceFrame, 'sourceFrame');
    _position = math.min(sourceFrame, totalFrames);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reader.file.closeSync();
  }
}
