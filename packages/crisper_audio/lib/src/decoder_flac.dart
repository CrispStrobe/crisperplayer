// SPDX-License-Identifier: MIT
part of 'decoder.dart';

const _flacWindow = 2 * 1024 * 1024;

final class _FlacFrameInfo extends Struct {
  @Int64()
  external int firstFrame;
  @Int32()
  external int frames;
  @Int32()
  external int encodedBytes;
}

typedef _FlacInfoNative =
    Int32 Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      Int32,
      Pointer<_FlacFrameInfo>,
    );
typedef _FlacInfoDart =
    int Function(Pointer<Uint8>, Pointer<Uint8>, int, Pointer<_FlacFrameInfo>);
typedef _FlacDecodeNative =
    Int32 Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      Int32,
      Pointer<Float>,
      Int32,
      Pointer<_FlacFrameInfo>,
    );
typedef _FlacDecodeDart =
    int Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      Pointer<Float>,
      int,
      Pointer<_FlacFrameInfo>,
    );

typedef _FlacFrame = ({int offset, int start, int frames, int bytes});

/// Native FLAC frames are independent. STREAMINFO supplies the presentation
/// length; CRC-validated frame numbers make seeks possible without decoding or
/// indexing the entire file. The two MiB window is a deliberate resource cap.
final class _FlacDecoder implements PcmDecoder {
  _FlacDecoder(
    this.reader,
    this.sampleRate,
    this.channels,
    this.totalFrames,
    this._maxBlock,
    this._audioStart,
    Uint8List streamInfo,
    DynamicLibrary library,
  ) : _frameInfo = library.lookupFunction<_FlacInfoNative, _FlacInfoDart>(
        'ca_glint_flac_frame_info',
      ),
      _decode = library.lookupFunction<_FlacDecodeNative, _FlacDecodeDart>(
        'ca_glint_flac_decode',
      ) {
    try {
      _streamInfo = calloc<Uint8>(34);
      _streamInfo.asTypedList(34).setAll(0, streamInfo);
      _input = calloc<Uint8>(_flacWindow);
      _probe = calloc<Uint8>(32);
      _info = calloc<_FlacFrameInfo>();
      _pcm = calloc<Float>(_maxBlock * channels);
      _nextOffset = _audioStart;
    } catch (_) {
      _freeNative();
      rethrow;
    }
  }

  static _FlacDecoder open(_FileReader reader, DynamicLibrary? library) {
    Uint8List? stream;
    var offset = 4;
    var last = false;
    while (!last) {
      final header = reader.bytes(offset, 4);
      final type = header[0] & 127;
      last = (header[0] & 128) != 0;
      final size = (header[1] << 16) | (header[2] << 8) | header[3];
      offset += 4;
      if (size > reader.length - offset || type == 127) {
        throw const FormatException('Invalid FLAC metadata block');
      }
      if (type == 0) {
        if (stream != null || size != 34) {
          throw const FormatException('Invalid FLAC STREAMINFO');
        }
        stream = Uint8List.fromList(reader.bytes(offset, size));
      } else if (stream == null) {
        throw const FormatException('FLAC STREAMINFO must be the first block');
      }
      // Pictures, comments and optional seek hints are skipped without copying.
      offset += size;
    }
    if (stream == null || offset >= reader.length) {
      throw const FormatException('FLAC is missing its audio frames');
    }
    final b = ByteData.sublistView(stream);
    final minBlock = b.getUint16(0);
    final maxBlock = b.getUint16(2);
    final maxEncoded = (stream[7] << 16) | (stream[8] << 8) | stream[9];
    final rate = (stream[10] << 12) | (stream[11] << 4) | (stream[12] >> 4);
    final channels = ((stream[12] >> 1) & 7) + 1;
    final bits = (((stream[12] & 1) << 4) | (stream[13] >> 4)) + 1;
    final frames =
        ((stream[13] & 15) << 32) |
        (stream[14] << 24) |
        (stream[15] << 16) |
        (stream[16] << 8) |
        stream[17];
    if (minBlock < 16 ||
        maxBlock < minBlock ||
        maxEncoded > _flacWindow ||
        rate < 8000 ||
        rate > 384000 ||
        channels > 2 ||
        bits < 4 ||
        bits > 24) {
      throw const FormatException(
        'FLAC requires mono/stereo 4–24-bit PCM, '
        '8–384 kHz, and frames no larger than 2 MiB',
      );
    }
    if (frames == 0) {
      throw const FormatException(
        'FLAC without a declared sample count is unsupported',
      );
    }
    return _FlacDecoder(
      reader,
      rate,
      channels,
      frames,
      maxBlock,
      offset,
      stream,
      library ?? openNativeLibrary(),
    );
  }

  final _FileReader reader;
  @override
  final int sampleRate;
  @override
  final int channels;
  @override
  final int totalFrames;
  final int _maxBlock;
  final int _audioStart;
  final _FlacInfoDart _frameInfo;
  final _FlacDecodeDart _decode;
  Pointer<Uint8> _streamInfo = nullptr;
  Pointer<Uint8> _input = nullptr;
  Pointer<Uint8> _probe = nullptr;
  Pointer<_FlacFrameInfo> _info = nullptr;
  Pointer<Float> _pcm = nullptr;
  final Uint8List _scan = Uint8List(64 * 1024);
  int _inputStart = -1;
  int _inputLength = 0;
  int _nextOffset = 0;
  int _nextFrame = 0;
  int _bufferAt = 0;
  int _bufferFrames = 0;
  int _position = 0;
  bool _disposed = false;
  Object? _failure;

  @override
  String get format => 'flac';
  @override
  int get positionFrames => _position;

  void _checkOpen() {
    if (_disposed) throw StateError('Decoder has been disposed');
    if (_failure != null) throw StateError('Decoder failed: $_failure');
    reader.checkCancelled?.call();
  }

  void _refill(int offset) {
    _inputStart = offset;
    _inputLength = math.min(_flacWindow, reader.length - offset);
    reader.readInto(offset, _input.asTypedList(_inputLength), 0, _inputLength);
  }

  _FlacFrame? _tryDecodeAt(int offset) {
    if (offset < _audioStart || offset > reader.length - 6) return null;
    reader.checkCancelled?.call();
    if (offset < _inputStart || offset >= _inputStart + _inputLength) {
      _refill(offset);
    }
    var local = offset - _inputStart;
    var result = _decode(
      _streamInfo,
      _input + local,
      _inputLength - local,
      _pcm,
      _maxBlock * channels,
      _info,
    );
    if (result < 0 && local > 0 && _inputStart + _inputLength < reader.length) {
      // A valid frame can straddle the end of the read-ahead window. Retry
      // once with its start aligned; all other failures stay hard failures.
      _refill(offset);
      local = 0;
      result = _decode(
        _streamInfo,
        _input,
        _inputLength,
        _pcm,
        _maxBlock * channels,
        _info,
      );
    }
    if (result <= 0) return null;
    final info = _info.ref;
    if (result != info.frames ||
        info.frames > _maxBlock ||
        info.firstFrame < 0 ||
        info.firstFrame + info.frames > totalFrames ||
        info.encodedBytes < 6 ||
        info.encodedBytes > _inputLength - local) {
      throw const FormatException('Invalid native FLAC frame result');
    }
    return (
      offset: offset,
      start: info.firstFrame,
      frames: info.frames,
      bytes: info.encodedBytes,
    );
  }

  /// A FLAC frame cannot exceed the bounded window. At any byte position the
  /// next frame header is therefore at most one window away. Both header CRC8
  /// and complete-frame CRC16 must pass before a candidate becomes a seek point.
  _FlacFrame? _findFrame(int from) {
    final end = math.min(reader.length, from + _flacWindow + 32);
    var offset = from;
    while (offset + 6 <= end) {
      final count = math.min(_scan.length, end - offset);
      reader.readInto(offset, _scan, 0, count);
      for (var i = 0; i + 1 < count; i++) {
        if ((i & 1023) == 0) reader.checkCancelled?.call();
        if (_scan[i] != 0xff || (_scan[i + 1] & 0xfc) != 0xf8) continue;
        final at = offset + i;
        final length = math.min(32, reader.length - at);
        if (length < 6) return null;
        _probe.asTypedList(length).setAll(0, reader.bytes(at, length));
        if (_frameInfo(_streamInfo, _probe, length, _info) < 0) continue;
        final decoded = _tryDecodeAt(at);
        if (decoded != null) return decoded;
      }
      offset += count - 1; // Keep a sync word crossing a scan-page boundary.
    }
    return null;
  }

  void _accept(_FlacFrame frame, int skip) {
    _bufferAt = skip;
    _bufferFrames = frame.frames;
    _nextOffset = frame.offset + frame.bytes;
    _nextFrame = frame.start + frame.frames;
  }

  @override
  int readFrames(Pointer<Float> destination, int maxFrames) {
    _checkOpen();
    if (maxFrames < 0) throw RangeError.value(maxFrames, 'maxFrames');
    if (maxFrames == 0 || _position == totalFrames) return 0;
    if (destination == nullptr) throw ArgumentError.notNull('destination');
    final wanted = math.min(
      math.min(maxFrames, _maxReadFrames),
      totalFrames - _position,
    );
    var written = 0;
    try {
      while (written < wanted) {
        if (_bufferAt == _bufferFrames) {
          final frame = _tryDecodeAt(_nextOffset);
          if (frame == null || frame.start != _nextFrame) {
            throw const FormatException(
              'Corrupt, discontinuous or unsupported FLAC frame',
            );
          }
          _accept(frame, 0);
        }
        final take = math.min(wanted - written, _bufferFrames - _bufferAt);
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

  @override
  void seek(int sourceFrame) {
    _checkOpen();
    if (sourceFrame < 0) throw RangeError.value(sourceFrame, 'sourceFrame');
    try {
      final wanted = math.min(sourceFrame, totalFrames);
      if (wanted == totalFrames) {
        _bufferAt = _bufferFrames = 0;
        _position = totalFrames;
        _nextFrame = totalFrames;
        return;
      }
      var low = _audioStart;
      var high = reader.length - 1;
      for (var iteration = 0; low <= high && iteration < 64; iteration++) {
        final middle = low + (high - low) ~/ 2;
        final frame = _findFrame(middle);
        if (frame == null || frame.start > wanted) {
          high = middle - 1;
        } else if (frame.start + frame.frames <= wanted) {
          low = frame.offset + frame.bytes;
        } else {
          _accept(frame, wanted - frame.start);
          _position = wanted;
          return;
        }
      }
      throw const FormatException('Cannot locate a CRC-valid FLAC seek frame');
    } catch (error) {
      _failure = error;
      rethrow;
    }
  }

  void _freeNative() {
    if (_streamInfo != nullptr) calloc.free(_streamInfo);
    if (_input != nullptr) calloc.free(_input);
    if (_probe != nullptr) calloc.free(_probe);
    if (_info != nullptr) calloc.free(_info);
    if (_pcm != nullptr) calloc.free(_pcm);
    _streamInfo = nullptr;
    _input = nullptr;
    _probe = nullptr;
    _info = nullptr;
    _pcm = nullptr;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _freeNative();
    reader.file.closeSync();
  }
}
