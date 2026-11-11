// SPDX-License-Identifier: MIT
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'library.dart';
import 'mp4_aac.dart';

part 'decoder_raw.dart';
part 'decoder_wav.dart';

/// A seekable, bounded-memory decoder for local audio files.
///
/// All I/O is synchronous: create and use this object inside the player's worker
/// isolate. WAV and MP4 read bounded metadata; raw MP3/ADTS scan frame headers to
/// establish exact duration and a sparse seek index. The optional cancellation
/// callback is polled between bounded reads, including during open. No whole
/// media file or decoded
/// book is retained. One call returns at most 4096 interleaved PCM frames.
abstract class PcmDecoder {
  static PcmDecoder open(
    String path, {
    DynamicLibrary? library,
    void Function()? checkCancelled,
  }) {
    checkCancelled?.call();
    final file = File(path).openSync();
    try {
      final reader = _FileReader(file, checkCancelled: checkCancelled);
      if (reader.length < 12) {
        throw const FormatException('Audio file is empty or truncated');
      }
      final header = reader.bytes(0, 12);
      if (_matches(header, 0, 'RIFF') && _matches(header, 8, 'WAVE')) {
        return _WavDecoder.open(reader);
      }
      _EncodedSource source;
      // ISO-BMFF files may begin with a small free/wide box before ftyp/moov.
      if (_matches(header, 4, 'ftyp') ||
          _matches(header, 4, 'moov') ||
          _matches(header, 4, 'free') ||
          _matches(header, 4, 'wide') ||
          _matches(header, 4, 'mdat')) {
        source = _Mp4Source(
          Mp4AacTrack.open(file, checkCancelled: checkCancelled),
        );
      } else {
        source = _RawFrameSource.scan(reader);
      }
      return _GlintDecoder(reader, source, library ?? openNativeLibrary());
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  int get sampleRate;
  int get channels;
  int get totalFrames;
  int get positionFrames;
  String get format;

  /// Copies interleaved floats and returns frames, never scalar samples.
  /// Zero denotes EOF (or a request for zero frames); errors throw.
  int readFrames(Pointer<Float> destination, int maxFrames);

  /// Seeks in presentation PCM frames, including container gapless trimming.
  /// Negative positions throw; positions after EOF clamp to EOF.
  void seek(int sourceFrame);
  void dispose();
}

const _maxReadFrames = 4096;
const _aacRates = <int>[
  96000,
  88200,
  64000,
  48000,
  44100,
  32000,
  24000,
  22050,
  16000,
  12000,
  11025,
  8000,
];

bool _matches(List<int> data, int offset, String value) {
  if (offset < 0 || offset + value.length > data.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (data[offset + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

/// File offsets are Dart's 64-bit integers on native targets. The small cache
/// makes a header-only scan sequential without allocating each media frame.
final class _FileReader {
  _FileReader(this.file, {this.checkCancelled}) : length = file.lengthSync();
  final void Function()? checkCancelled;
  final RandomAccessFile file;
  final int length;
  final Uint8List _cache = Uint8List(64 * 1024);
  int _cacheStart = -1;
  int _cacheLength = 0;

  Uint8List bytes(int offset, int count) {
    checkCancelled?.call();
    _check(offset, count);
    if (count > _cache.length) {
      throw const FormatException('Oversized audio metadata read');
    }
    if (_cacheStart < 0 ||
        offset < _cacheStart ||
        offset + count > _cacheStart + _cacheLength) {
      _cacheStart = offset;
      _cacheLength = math.min(_cache.length, length - offset);
      readInto(offset, _cache, 0, _cacheLength);
    }
    return Uint8List.sublistView(
      _cache,
      offset - _cacheStart,
      offset - _cacheStart + count,
    );
  }

  void readInto(int offset, Uint8List buffer, int start, int count) {
    checkCancelled?.call();
    _check(offset, count);
    file.setPositionSync(offset);
    var written = 0;
    while (written < count) {
      checkCancelled?.call();
      final got = file.readIntoSync(buffer, start + written, start + count);
      if (got == 0) throw const FormatException('Truncated audio payload');
      written += got;
    }
  }

  void _check(int offset, int count) {
    if (offset < 0 || count < 0 || offset > length - count) {
      throw const FormatException('Audio offset exceeds file bounds');
    }
  }
}

final class _Packet {
  const _Packet(
    this.offset,
    this.length,
    this.startFrame,
    this.frames, {
    this.mainBytes = 0,
  });
  final int offset;
  final int length;
  final int startFrame;
  final int frames;
  final int mainBytes;
}

abstract interface class _EncodedSource {
  int get sampleRate;
  int get channels;
  int get sampleCount;
  int get framesPerPacket;
  int get totalFrames;
  int get trimStartFrames;
  int get codec;
  bool get needsAdts;
  String get format;
  _Packet packetAt(int index);
}

final class _Mp4Source implements _EncodedSource {
  _Mp4Source(this.track);
  final Mp4AacTrack track;
  @override
  int get sampleRate => track.sampleRate;
  @override
  int get channels => track.channels;
  @override
  int get sampleCount => track.sampleCount;
  @override
  int get framesPerPacket => 1024;
  @override
  int get totalFrames => track.totalFrames;
  @override
  int get trimStartFrames => track.trimStartFrames;
  @override
  int get codec => 2;
  @override
  bool get needsAdts => true;
  @override
  String get format => 'aac-mp4';
  @override
  _Packet packetAt(int index) {
    final p = track.packetAt(index);
    return _Packet(p.offset, p.length, p.startFrame, p.frames);
  }
}

final class _GlintFrameInfo extends Struct {
  @Int32()
  external int sampleRate;
  @Int32()
  external int channels;
  @Int32()
  external int samples;
  @Int32()
  external int frameBytes;
}

typedef _CreateNative = Pointer<Void> Function(Int32);
typedef _CreateDart = Pointer<Void> Function(int);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _DecodeNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int32,
      Pointer<Float>,
      Pointer<_GlintFrameInfo>,
      Int64,
    );
typedef _DecodeDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Float>,
      Pointer<_GlintFrameInfo>,
      int,
    );

final class _GlintDecoder implements PcmDecoder {
  _GlintDecoder(this._reader, this._source, DynamicLibrary library)
    : _create = library.lookupFunction<_CreateNative, _CreateDart>(
        'ca_glint_create',
      ),
      _destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
        'ca_glint_destroy',
      ),
      _decode = library.lookupFunction<_DecodeNative, _DecodeDart>(
        'ca_glint_decode',
      ) {
    try {
      _compressed = calloc<Uint8>(8191);
      _pcm = calloc<Float>(1152 * 2);
      _info = calloc<_GlintFrameInfo>();
      _resetNative();
      _discardUntil = _source.trimStartFrames;
    } catch (_) {
      _freeNative();
      rethrow;
    }
  }

  final _FileReader _reader;
  final _EncodedSource _source;
  final _CreateDart _create;
  final _DestroyDart _destroy;
  final _DecodeDart _decode;
  Pointer<Void> _context = nullptr;
  Pointer<Uint8> _compressed = nullptr;
  Pointer<Float> _pcm = nullptr;
  Pointer<_GlintFrameInfo> _info = nullptr;
  int _nextPacket = 0;
  int _bufferAt = 0;
  int _bufferFrames = 0;
  int _position = 0;
  int _discardUntil = 0;
  bool _disposed = false;
  Object? _failure;

  @override
  int get sampleRate => _source.sampleRate;
  @override
  int get channels => _source.channels;
  @override
  int get totalFrames => _source.totalFrames;
  @override
  int get positionFrames => _position;
  @override
  String get format => _source.format;

  void _checkOpen() {
    if (_disposed) throw StateError('Decoder has been disposed');
    if (_failure != null) throw StateError('Decoder failed: $_failure');
  }

  void _resetNative() {
    if (_context != nullptr) _destroy(_context);
    _context = _create(_source.codec);
    if (_context == nullptr) throw StateError('Cannot allocate Glint decoder');
    _bufferAt = _bufferFrames = 0;
  }

  @override
  int readFrames(Pointer<Float> destination, int maxFrames) {
    _checkOpen();
    if (maxFrames < 0) throw RangeError.value(maxFrames, 'maxFrames');
    if (maxFrames == 0 || _position >= totalFrames) return 0;
    if (destination == nullptr) throw ArgumentError.notNull('destination');
    final wanted = math.min(
      math.min(maxFrames, _maxReadFrames),
      totalFrames - _position,
    );
    var written = 0;
    try {
      while (written < wanted) {
        if (_bufferAt == _bufferFrames) _loadPacket();
        final take = math.min(wanted - written, _bufferFrames - _bufferAt);
        if (take <= 0) {
          throw const FormatException('Audio ends before declared duration');
        }
        destination
            .asTypedList(wanted * channels)
            .setRange(
              written * channels,
              (written + take) * channels,
              _pcm.asTypedList(_bufferFrames * channels),
              _bufferAt * channels,
            );
        written += take;
        _bufferAt += take;
      }
      _position += written;
      return written;
    } catch (error) {
      _failure = error;
      rethrow;
    }
  }

  void _loadPacket() {
    _bufferAt = _bufferFrames = 0;
    while (_nextPacket < _source.sampleCount) {
      final ordinal = _nextPacket++;
      final packet = _source.packetAt(ordinal);
      final prefix = _source.needsAdts ? 7 : 0;
      if (packet.length <= 0 || packet.length > 8191 - prefix) {
        throw const FormatException('Compressed frame exceeds decoder limit');
      }
      final input = _compressed.asTypedList(packet.length + prefix);
      if (prefix != 0) _writeAdts(input, packet.length + prefix);
      _reader.readInto(packet.offset, input, prefix, packet.length);
      final frames = _decode(
        _context,
        _compressed,
        input.length,
        _pcm,
        _info,
        ordinal,
      );
      if (frames < 0) {
        throw FormatException(
          'Glint ${_source.format} packet $ordinal '
          'is corrupt or uses an unsupported coding tool (error $frames)',
        );
      }
      if (_info.ref.sampleRate != sampleRate ||
          _info.ref.channels != channels ||
          _info.ref.frameBytes != input.length ||
          (frames != 0 && frames != packet.frames)) {
        throw const FormatException('Compressed audio changes stream format');
      }
      final end = packet.startFrame + packet.frames;
      if (end <= _discardUntil) continue;
      // MP3 reservoir warmup is allowed only in discarded seek preroll.
      if (frames == 0) {
        throw const FormatException('Missing MP3 bit-reservoir history');
      }
      _bufferFrames = frames;
      _bufferAt = math.max(0, _discardUntil - packet.startFrame);
      return;
    }
    throw const FormatException('Audio packet table ends prematurely');
  }

  void _writeAdts(Uint8List target, int size) {
    final rateIndex = _aacRates.indexOf(sampleRate);
    if (rateIndex < 0 || channels < 1 || channels > 2) {
      throw const FormatException('AAC configuration cannot be framed as ADTS');
    }
    target[0] = 0xff;
    target[1] = 0xf1;
    target[2] = 0x40 | (rateIndex << 2) | (channels >> 2);
    target[3] = ((channels & 3) << 6) | (size >> 11);
    target[4] = (size >> 3) & 0xff;
    target[5] = ((size & 7) << 5) | 0x1f;
    target[6] = 0xfc;
  }

  @override
  void seek(int sourceFrame) {
    _checkOpen();
    if (sourceFrame < 0) throw RangeError.value(sourceFrame, 'sourceFrame');
    try {
      final wanted = math.min(sourceFrame, totalFrames);
      final rawFrame = wanted + _source.trimStartFrames;
      final packet = math.min(
        rawFrame ~/ _source.framesPerPacket,
        _source.sampleCount,
      );
      var start = math.max(0, packet - (_source.codec == 1 ? 4 : 2));
      if (_source.codec == 1) {
        // Refill the maximum 511-byte MP3 reservoir before four complete
        // packets that rebuild IMDCT/polyphase history. This also handles
        // very low-bitrate MPEG-2 frames with only a few main-data bytes.
        var history = 0;
        while (start > 0 && history < 511) {
          history += _source.packetAt(--start).mainBytes;
        }
      }
      _resetNative();
      _nextPacket = start;
      _discardUntil = rawFrame;
      _position = wanted;
    } catch (error) {
      _failure = error;
      rethrow;
    }
  }

  void _freeNative() {
    if (_context != nullptr) _destroy(_context);
    if (_compressed != nullptr) calloc.free(_compressed);
    if (_pcm != nullptr) calloc.free(_pcm);
    if (_info != nullptr) calloc.free(_info);
    _context = nullptr;
    _compressed = nullptr;
    _pcm = nullptr;
    _info = nullptr;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _freeNative();
    _reader.file.closeSync();
  }
}
