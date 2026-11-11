// SPDX-License-Identifier: MIT
part of 'decoder.dart';

final class _FrameHeader {
  const _FrameHeader(
    this.codec,
    this.sampleRate,
    this.channels,
    this.frames,
    this.bytes,
    this.headerBytes,
    this.mainBytes,
  );
  final int codec;
  final int sampleRate;
  final int channels;
  final int frames;
  final int bytes;
  final int headerBytes;
  final int mainBytes;
}

_FrameHeader? _frameHeader(List<int> h) {
  if (h.length < 7 || h[0] != 0xff || (h[1] & 0xe0) != 0xe0) {
    return null;
  }
  if ((h[1] & 0xf6) == 0xf0) {
    final profile = (h[2] >> 6) & 3;
    final rate = (h[2] >> 2) & 15;
    final channels = ((h[2] & 1) << 2) | (h[3] >> 6);
    final size = ((h[3] & 3) << 11) | (h[4] << 3) | (h[5] >> 5);
    final prefix = (h[1] & 1) == 1 ? 7 : 9;
    if (profile != 1 ||
        rate >= _aacRates.length ||
        channels < 1 ||
        channels > 2 ||
        (h[6] & 3) != 0 ||
        size < prefix) {
      return null;
    }
    return _FrameHeader(2, _aacRates[rate], channels, 1024, size, prefix, 0);
  }
  final version = (h[1] >> 3) & 3;
  final layer = (h[1] >> 1) & 3;
  final bitrateIndex = (h[2] >> 4) & 15;
  final rateIndex = (h[2] >> 2) & 3;
  if (version == 1 ||
      layer != 1 ||
      bitrateIndex == 0 ||
      bitrateIndex == 15 ||
      rateIndex == 3) {
    return null;
  }
  const v1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
  const v2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
  var rate = const [44100, 48000, 32000][rateIndex];
  if (version == 2) rate ~/= 2;
  if (version == 0) rate ~/= 4;
  final channels = (h[3] >> 6) == 3 ? 1 : 2;
  final bitrate = (version == 3 ? v1 : v2)[bitrateIndex];
  final size =
      (version == 3 ? 144000 : 72000) * bitrate ~/ rate + ((h[2] >> 1) & 1);
  final prefix = 4 + ((h[1] & 1) == 0 ? 2 : 0);
  final side = version == 3
      ? (channels == 1 ? 17 : 32)
      : (channels == 1 ? 9 : 17);
  if (size <= prefix + side) return null;
  return _FrameHeader(
    1,
    rate,
    channels,
    version == 3 ? 1152 : 576,
    size,
    prefix,
    size - prefix - side,
  );
}

final class _Checkpoint {
  const _Checkpoint(this.packet, this.offset);
  final int packet;
  final int offset;
}

final class _RawFrameSource implements _EncodedSource {
  _RawFrameSource(
    this.reader,
    this.header,
    this.checkpoints,
    this.checkpointStride,
    this.sampleCount,
    this.trimStartFrames,
    this.totalFrames,
  );
  final _FileReader reader;
  final _FrameHeader header;
  final List<_Checkpoint> checkpoints;
  final int checkpointStride;
  @override
  final int sampleCount;
  @override
  final int trimStartFrames;
  @override
  final int totalFrames;
  int _cursorPacket = -1;
  int _cursorOffset = 0;

  static _RawFrameSource scan(_FileReader reader) {
    var offset = 0;
    // ID3v2 is metadata; its potentially large cover image is skipped in place.
    while (offset + 10 <= reader.length &&
        _matches(reader.bytes(offset, 3), 0, 'ID3')) {
      final tag = reader.bytes(offset, 10);
      if (tag[3] < 2 || tag[3] > 4 || tag.sublist(6, 10).any((v) => v > 127)) {
        throw const FormatException('Invalid ID3v2 header');
      }
      final size = (tag[6] << 21) | (tag[7] << 14) | (tag[8] << 7) | tag[9];
      final hasFooter = tag[3] == 4 && (tag[5] & 0x10) != 0;
      offset += 10 + size;
      if (hasFooter) offset += 10;
      if (offset > reader.length) {
        throw const FormatException('ID3 tag extends beyond the file');
      }
    }
    var end = reader.length;
    if (end >= 128 && _matches(reader.bytes(end - 128, 3), 0, 'TAG')) {
      end -= 128;
    }
    if (end >= 32 && _matches(reader.bytes(end - 32, 8), 0, 'APETAGEX')) {
      final footer = reader.bytes(end - 32, 32);
      final data = ByteData.sublistView(footer);
      final size = data.getUint32(12, Endian.little);
      final flags = data.getUint32(20, Endian.little);
      if (size < 32 || size > end - offset) {
        throw const FormatException('Invalid trailing APE tag');
      }
      end -= size;
      if ((flags & 0x80000000) != 0) {
        if (end < 32 || !_matches(reader.bytes(end - 32, 8), 0, 'APETAGEX')) {
          throw const FormatException('Missing APE tag header');
        }
        end -= 32;
      }
    }
    if (offset + 7 > end) throw const FormatException('No audio frames');
    final first = _frameHeader(reader.bytes(offset, 7));
    if (first == null) {
      throw const FormatException(
        'Direct decoder supports PCM WAV, MP3, '
        'AAC-LC ADTS, AAC-LC MP4/M4A/M4B, and native FLAC',
      );
    }
    var trimStart = 0;
    var trimEnd = 0;
    // Xing/Info is a metadata frame, excluded from the decoded PCM timeline.
    if (first.codec == 1 && offset + first.bytes <= end) {
      final frame = reader.bytes(offset, first.bytes);
      final side = first.frames == 1152
          ? (first.channels == 1 ? 17 : 32)
          : (first.channels == 1 ? 9 : 17);
      var tag = first.headerBytes + side;
      if (_matches(frame, tag, 'Xing') || _matches(frame, tag, 'Info')) {
        if (tag + 8 > frame.length) {
          throw const FormatException('Truncated Xing header');
        }
        final flags = ByteData.sublistView(frame).getUint32(tag + 4);
        tag += 8;
        if ((flags & 1) != 0) tag += 4;
        if ((flags & 2) != 0) tag += 4;
        if ((flags & 4) != 0) tag += 100;
        if ((flags & 8) != 0) tag += 4;
        if (tag + 24 <= frame.length &&
            (_matches(frame, tag, 'LAME') ||
                _matches(frame, tag, 'Lavc') ||
                _matches(frame, tag, 'Lavf'))) {
          final delay = (frame[tag + 21] << 4) | (frame[tag + 22] >> 4);
          final padding = ((frame[tag + 22] & 15) << 8) | frame[tag + 23];
          if (delay != 0 || padding != 0) {
            trimStart = delay + 529;
            trimEnd = math.max(0, padding - 529);
          }
        }
        offset += first.bytes;
      }
    }
    var count = 0;
    var stride = 128;
    final checkpoints = <_Checkpoint>[];
    while (offset < end) {
      if (offset + 7 > end) {
        throw const FormatException('Truncated audio frame');
      }
      final frame = _frameHeader(reader.bytes(offset, 7));
      if (frame == null ||
          frame.codec != first.codec ||
          frame.sampleRate != first.sampleRate ||
          frame.channels != first.channels ||
          frame.frames != first.frames) {
        throw FormatException('Invalid or changing audio header at $offset');
      }
      if (offset + frame.bytes > end) {
        throw const FormatException('Audio frame extends beyond the file');
      }
      if (count % stride == 0) {
        // A fixed-size index also bounds memory for unusually long recordings.
        // Doubling its stride preserves exact seeking, with more header reads.
        if (checkpoints.length == 16384) {
          for (var i = 0; i < 8192; i++) {
            checkpoints[i] = checkpoints[i * 2];
          }
          checkpoints.length = 8192;
          stride *= 2;
        }
        if (count % stride == 0) {
          checkpoints.add(_Checkpoint(count, offset));
        }
      }
      if (count == 0 && frame.codec == 1) {
        final side = reader.bytes(offset + frame.headerBytes, 2);
        final back = frame.frames == 1152
            ? (side[0] << 1) | (side[1] >> 7)
            : side[0];
        if (back != 0) {
          throw const FormatException(
            'MP3 starts without bit-reservoir history',
          );
        }
      }
      count++;
      offset += frame.bytes;
    }
    final total = count * first.frames - trimStart - trimEnd;
    if (count == 0 || total < 0) {
      throw const FormatException('Invalid audio frame count or gapless trim');
    }
    return _RawFrameSource(
      reader,
      first,
      checkpoints,
      stride,
      count,
      trimStart,
      total,
    );
  }

  @override
  int get sampleRate => header.sampleRate;
  @override
  int get channels => header.channels;
  @override
  int get codec => header.codec;
  @override
  int get framesPerPacket => header.frames;
  @override
  bool get needsAdts => false;
  @override
  String get format => codec == 1 ? 'mp3' : 'aac-adts';

  @override
  _Packet packetAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', sampleCount);
    final cp = checkpoints[index ~/ checkpointStride];
    var packet = cp.packet;
    var offset = cp.offset;
    if (_cursorPacket >= packet && _cursorPacket <= index) {
      packet = _cursorPacket;
      offset = _cursorOffset;
    }
    while (true) {
      final frame = _frameHeader(reader.bytes(offset, 7));
      if (frame == null ||
          frame.codec != codec ||
          frame.sampleRate != sampleRate ||
          frame.channels != channels ||
          frame.frames != framesPerPacket) {
        throw const FormatException('Audio changed after indexing');
      }
      if (packet == index) {
        _cursorPacket = index + 1;
        _cursorOffset = offset + frame.bytes;
        return _Packet(
          offset,
          frame.bytes,
          index * framesPerPacket,
          framesPerPacket,
          mainBytes: frame.mainBytes,
        );
      }
      offset += frame.bytes;
      packet++;
    }
  }
}
