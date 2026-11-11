// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

typedef Mp4AacPacket = ({int offset, int length, int startFrame, int frames});

/// Seekable ISO-BMFF sample tables for one AAC-LC mono/stereo audio track.
///
/// Reads the tables from the file in bounded pages; neither `mdat` nor `moov`
/// is retained in memory. Sparse checkpoints have a fixed maximum size even
/// for multi-hour books. The caller owns [file], including its seek position.
/// Fragmented/encrypted media, HE-AAC, ALAC, 960-frame AAC and timeline edits
/// that insert silence or change rate are rejected explicitly.
final class Mp4AacTrack {
  final _Reader _reader;
  final int sampleRate;
  final int channels;
  final int sampleCount;
  final int totalFrames;
  final int trimStartFrames;
  final int sampleRateIndex;
  final _SampleSizes _sizes;
  final _PagedTable _chunks;
  final bool _wideChunks;
  final _PagedTable _mapping;
  final int _mappingCount;
  final List<_MappingPoint> _points;
  final List<({int start, int end})> _media;
  _Run? _cachedRun;
  int _lastPacket = -2;
  Mp4AacPacket? _last;
  int _lastChunkEnd = 0;

  Mp4AacTrack._(
    this._reader,
    this.sampleRate,
    this.channels,
    this.sampleCount,
    this.totalFrames,
    this.trimStartFrames,
    this.sampleRateIndex,
    this._sizes,
    this._chunks,
    this._wideChunks,
    this._mapping,
    this._mappingCount,
    this._points,
    this._media,
  );

  static Mp4AacTrack open(
    RandomAccessFile file, {
    void Function()? checkCancelled,
  }) {
    final r = _Reader(file, checkCancelled);
    _Box? movie;
    final media = <({int start, int end})>[];
    for (final box in r.boxes(0, r.length)) {
      if (box.type == 'moof') _unsupported('fragmented MP4');
      if (box.type == 'moov') {
        if (movie != null) _invalid('multiple movie boxes');
        movie = box;
      }
      if (box.type == 'mdat') {
        if (media.length == 4096) _invalid('too many media-data boxes');
        media.add((start: box.data, end: box.end));
      }
    }
    if (movie == null || media.isEmpty) _invalid('missing movie/media data');
    _Box? selected;
    _Box? movieHeader;
    for (final box in r.children(movie)) {
      if (box.type == 'mvex') _unsupported('fragmented MP4');
      if (box.type == 'mvhd') movieHeader = box;
      if (box.type == 'trak') {
        final mdia = r.child(box, 'mdia');
        final handler = mdia == null ? null : r.child(mdia, 'hdlr');
        if (handler != null &&
            r.text(handler.data + 8, 4, handler.end) == 'soun') {
          selected ??= box;
        }
      }
    }
    if (selected == null) _unsupported('no audio track');
    if (movieHeader == null) _invalid('missing movie timescale');
    final movieScale = r.timeHeader(movieHeader).scale;
    final mdia = r.requiredChild(selected, 'mdia');
    final timing = r.timeHeader(r.requiredChild(mdia, 'mdhd'));
    final table = r.requiredChild(r.requiredChild(mdia, 'minf'), 'stbl');
    final children = <String, _Box>{};
    for (final box in r.children(table)) {
      if (children.containsKey(box.type)) _invalid('duplicate ${box.type}');
      children[box.type] = box;
    }
    _Box required(String name) => children[name] ?? _invalid('missing $name');
    if (children.containsKey('senc') ||
        children.containsKey('saiz') ||
        children.containsKey('saio')) {
      _unsupported('encrypted MP4');
    }
    if (children.containsKey('ctts')) _unsupported('audio composition offsets');
    final description = required('stsd');
    r.fullBoxZero(description);
    if (r.u32(description.data + 4, description.end) != 1) {
      _unsupported('multiple audio sample descriptions');
    }
    final entries = r.boxes(description.data + 8, description.end).iterator;
    if (!entries.moveNext()) _invalid('audio sample description count');
    final entry = entries.current;
    if (entries.moveNext()) _invalid('audio sample description count');
    if (entry.type != 'mp4a') _unsupported('audio codec ${entry.type}');
    if (r.u16(entry.data + 6, entry.end) != 1) {
      _unsupported('external media reference');
    }
    final version = r.u16(entry.data + 8, entry.end);
    if (version != 0 && version != 1) {
      _unsupported('QuickTime audio version $version');
    }
    final channelHint = r.u16(entry.data + 16, entry.end);
    final rateHint = r.u32(entry.data + 24, entry.end) >> 16;
    _Box? esds;
    for (final box in r.boxes(
      entry.data + (version == 1 ? 44 : 28),
      entry.end,
    )) {
      if (box.type == 'sinf') _unsupported('encrypted audio');
      if (box.type == 'esds') esds = box;
      if (box.type == 'wave') esds ??= r.child(box, 'esds');
    }
    if (esds == null) _invalid('missing AAC configuration');
    r.fullBoxZero(esds);
    if (esds.end - esds.data > 65536) _invalid('oversized AAC configuration');
    final config = _aacConfig(r.bytes(esds.data + 4, esds.end - esds.data - 4));
    // The ASC is authoritative. Some muxers put 2 in a mono mp4a entry, but
    // contradictory non-placeholder sample-rate fields indicate a bad file.
    if (channelHint < 1 || channelHint > 2) _unsupported('multichannel AAC');
    if (rateHint != 0 && rateHint != config.rate) {
      _invalid('inconsistent AAC sample rate');
    }
    final sizes = _SampleSizes.open(r, children['stsz'], children['stz2']);
    final sampleCount = sizes.count;
    if (sampleCount == 0) _invalid('empty AAC track');
    final stts = required('stts');
    r.fullBoxZero(stts);
    final timeCount = r.u32(stts.data + 4, stts.end);
    final times = r.table(stts.data + 8, timeCount, 8, stts.end);
    var timedSamples = 0;
    var timedFrames = 0;
    for (var i = 0; i < timeCount; i++) {
      if (i % 256 == 0) r.checkCancelled?.call();
      final count = times.u32(i * 8);
      final delta = times.u32(i * 8 + 4);
      if (count == 0 || delta == 0 || timedSamples + count > sampleCount) {
        _invalid('invalid sample timing');
      }
      final numerator = delta * config.rate;
      if (numerator % timing.scale != 0) {
        _unsupported('fractional AAC frame timing');
      }
      final frames = numerator ~/ timing.scale;
      if (frames != 1024 &&
          !(i == timeCount - 1 && count == 1 && frames > 0 && frames < 1024)) {
        _unsupported('non-1024 AAC frame timing');
      }
      timedSamples += count;
      timedFrames += count * frames;
    }
    if (timedSamples != sampleCount) _invalid('sample timing count mismatch');
    var trimStart = 0;
    var totalFrames = timedFrames;
    final edits = r.child(selected, 'edts');
    if (edits != null) {
      final list = r.requiredChild(edits, 'elst');
      final version = r.u8(list.data, list.end);
      if (version != 0 && version != 1) _unsupported('edit-list version');
      final count = r.u32(list.data + 4, list.end);
      if (count != 1) _unsupported('multiple or empty timeline edits');
      final wide = version == 1;
      final segment = wide
          ? r.u64(list.data + 8, list.end)
          : r.u32(list.data + 8, list.end);
      final mediaTime = wide
          ? r.i64(list.data + 16, list.end)
          : r.i32(list.data + 12, list.end);
      final rateAt = list.data + (wide ? 24 : 16);
      if (mediaTime < 0) _unsupported('timeline silence edits');
      if (r.u32(rateAt, list.end) != 0x00010000) {
        _unsupported('timeline rate edits');
      }
      if (mediaTime * config.rate % timing.scale != 0) {
        _unsupported('fractional AAC trim');
      }
      trimStart = mediaTime * config.rate ~/ timing.scale;
      if (trimStart >= timedFrames || segment == 0) {
        _invalid('edit outside audio timeline');
      }
      totalFrames = math.min(
        timedFrames - trimStart,
        segment * config.rate ~/ movieScale,
      );
    }
    if (totalFrames <= 0) _invalid('empty audio presentation');
    final stco = children['stco'];
    final co64 = children['co64'];
    if ((stco == null) == (co64 == null)) {
      _invalid('missing or ambiguous chunk offsets');
    }
    final chunkBox = (co64 ?? stco)!;
    r.fullBoxZero(chunkBox);
    final chunkCount = r.u32(chunkBox.data + 4, chunkBox.end);
    if (chunkCount == 0) _invalid('empty chunk table');
    final chunks = r.table(
      chunkBox.data + 8,
      chunkCount,
      co64 == null ? 4 : 8,
      chunkBox.end,
    );
    final mappingBox = required('stsc');
    r.fullBoxZero(mappingBox);
    final mappingCount = r.u32(mappingBox.data + 4, mappingBox.end);
    if (mappingCount == 0) _invalid('empty sample/chunk map');
    final mapping = r.table(
      mappingBox.data + 8,
      mappingCount,
      12,
      mappingBox.end,
    );
    final points = <_MappingPoint>[];
    final stride = math.max(1, (mappingCount + 1023) ~/ 1024);
    var firstSample = 0;
    for (var i = 0; i < mappingCount; i++) {
      if (i % 256 == 0) r.checkCancelled?.call();
      final firstChunk = mapping.u32(i * 12);
      final perChunk = mapping.u32(i * 12 + 4);
      final desc = mapping.u32(i * 12 + 8);
      final nextChunk = i + 1 == mappingCount
          ? chunkCount + 1
          : mapping.u32((i + 1) * 12);
      if ((i == 0 && firstChunk != 1) ||
          firstChunk < 1 ||
          firstChunk > chunkCount ||
          nextChunk <= firstChunk ||
          nextChunk > chunkCount + 1 ||
          perChunk == 0 ||
          desc != 1) {
        _invalid('invalid sample/chunk map');
      }
      if (i % stride == 0) points.add(_MappingPoint(i, firstSample));
      firstSample += (nextChunk - firstChunk) * perChunk;
      if (firstSample > sampleCount) {
        _invalid('chunk sample count exceeds track');
      }
    }
    if (firstSample != sampleCount) _invalid('chunk sample count mismatch');
    return Mp4AacTrack._(
      r,
      config.rate,
      config.channels,
      sampleCount,
      totalFrames,
      trimStart,
      config.rateIndex,
      sizes,
      chunks,
      co64 != null,
      mapping,
      mappingCount,
      points,
      media,
    );
  }

  Mp4AacPacket packetAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', sampleCount);
    final length = _sizes.at(index);
    int offset;
    if (index == _lastPacket + 1 && index < _lastChunkEnd) {
      offset = _last!.offset + _last!.length;
    } else {
      final run = _runFor(index);
      final chunkInRun = (index - run.firstSample) ~/ run.perChunk;
      final chunk = run.firstChunk + chunkInRun - 1;
      final first = run.firstSample + chunkInRun * run.perChunk;
      final base = _wideChunks
          ? _chunks.u64(chunk * 8)
          : _chunks.u32(chunk * 4);
      offset = base + _sizes.sumBefore(index) - _sizes.sumBefore(first);
      _lastChunkEnd = first + run.perChunk;
    }
    if (offset < 0 ||
        offset > _reader.length - length ||
        !_media.any(
          (region) => offset >= region.start && offset + length <= region.end,
        )) {
      _invalid('AAC packet outside media data');
    }
    _lastPacket = index;
    return _last = (
      offset: offset,
      length: length,
      startFrame: index * 1024,
      frames: 1024,
    );
  }

  _Run _runFor(int sample) {
    final cached = _cachedRun;
    if (cached != null &&
        sample >= cached.firstSample &&
        sample < cached.endSample) {
      return cached;
    }
    var lo = 0;
    var hi = _points.length;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_points[mid].firstSample <= sample) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final point = _points[lo];
    var firstSample = point.firstSample;
    final chunkCount = _chunks.length ~/ (_wideChunks ? 8 : 4);
    for (var i = point.entry; i < _mappingCount; i++) {
      final firstChunk = _mapping.u32(i * 12);
      final perChunk = _mapping.u32(i * 12 + 4);
      final endChunk = i + 1 == _mappingCount
          ? chunkCount + 1
          : _mapping.u32((i + 1) * 12);
      final endSample = firstSample + (endChunk - firstChunk) * perChunk;
      if (sample < endSample) {
        return _cachedRun = _Run(firstChunk, firstSample, endSample, perChunk);
      }
      firstSample = endSample;
    }
    return _invalid('sample has no chunk');
  }
}

Never _invalid(String reason) =>
    throw FormatException('Invalid M4A/M4B: $reason');
Never _unsupported(String reason) => throw UnsupportedError(
  'M4A/M4B playback does not support $reason. This decoder supports unencrypted AAC-LC mono/stereo.',
);

final class _Box {
  final String type;
  final int data, end;
  const _Box(this.type, this.data, this.end);
}

final class _Reader {
  final RandomAccessFile file;
  final int length;
  final void Function()? checkCancelled;
  _Reader(this.file, this.checkCancelled) : length = file.lengthSync();
  Uint8List bytes(int at, int count, [int? end]) {
    checkCancelled?.call();
    if (at < 0 || count < 0 || count > 65544 || at > (end ?? length) - count) {
      _invalid('truncated metadata');
    }
    file.setPositionSync(at);
    final result = file.readSync(count);
    if (result.length != count) _invalid('truncated file');
    return result;
  }

  int u8(int at, int end) => bytes(at, 1, end)[0];
  int u16(int at, int end) =>
      ByteData.sublistView(bytes(at, 2, end)).getUint16(0);
  int u32(int at, int end) =>
      ByteData.sublistView(bytes(at, 4, end)).getUint32(0);
  int u64(int at, int end) {
    final value = ByteData.sublistView(bytes(at, 8, end)).getUint64(0);
    if (value < 0) _invalid('64-bit value exceeds signed file offsets');
    return value;
  }

  int i32(int at, int end) =>
      ByteData.sublistView(bytes(at, 4, end)).getInt32(0);
  int i64(int at, int end) =>
      ByteData.sublistView(bytes(at, 8, end)).getInt64(0);
  String text(int at, int count, int end) =>
      String.fromCharCodes(bytes(at, count, end));
  Iterable<_Box> boxes(int at, int end) sync* {
    var count = 0;
    while (at < end) {
      if (++count > 4096) _invalid('excessive box count');
      final header = ByteData.sublistView(bytes(at, 8, end));
      var size = header.getUint32(0);
      final type = text(at + 4, 4, end);
      var headerLength = 8;
      if (size == 1) {
        size = u64(at + 8, end);
        headerLength = 16;
      }
      if (size == 0) size = end - at;
      if (size < headerLength || size > end - at) {
        _invalid('invalid $type box length');
      }
      yield _Box(type, at + headerLength, at + size);
      at += size;
    }
  }

  Iterable<_Box> children(_Box box) => boxes(box.data, box.end);
  _Box? child(_Box box, String type) {
    _Box? result;
    for (final candidate in children(box)) {
      if (candidate.type == type) {
        if (result != null) _invalid('duplicate $type');
        result = candidate;
      }
    }
    return result;
  }

  _Box requiredChild(_Box box, String type) =>
      child(box, type) ?? _invalid('missing $type');
  void fullBoxZero(_Box box) {
    if (u32(box.data, box.end) != 0) {
      _unsupported('${box.type} version or flags');
    }
  }

  ({int scale, int duration}) timeHeader(_Box box) {
    final version = u8(box.data, box.end);
    if (version != 0 && version != 1) _unsupported('${box.type} version');
    final scale = u32(box.data + (version == 1 ? 20 : 12), box.end);
    final duration = version == 1
        ? u64(box.data + 24, box.end)
        : u32(box.data + 16, box.end);
    if (scale < 1) _invalid('zero timescale');
    return (scale: scale, duration: duration);
  }

  _PagedTable table(int at, int count, int stride, int end) {
    if (count < 0 || count > (end - at) ~/ stride) {
      _invalid('truncated sample table');
    }
    return _PagedTable(this, at, count * stride);
  }
}

final class _PagedTable {
  final _Reader reader;
  final int start, length;
  ByteData _cache = ByteData(0);
  int _cacheAt = -1;
  _PagedTable(this.reader, this.start, this.length);
  int _offset(int relative, int width) {
    if (relative < 0 || relative > length - width) {
      _invalid('sample-table bounds');
    }
    if (_cacheAt < 0 ||
        relative < _cacheAt ||
        relative + width > _cacheAt + _cache.lengthInBytes) {
      _cacheAt = relative ~/ 16384 * 16384;
      _cache = ByteData.sublistView(
        reader.bytes(start + _cacheAt, math.min(16392, length - _cacheAt)),
      );
    }
    return relative - _cacheAt;
  }

  int u8(int relative) {
    final offset = _offset(relative, 1);
    return _cache.getUint8(offset);
  }

  int u32(int relative) {
    final offset = _offset(relative, 4);
    return _cache.getUint32(offset);
  }

  int u64(int relative) {
    final offset = _offset(relative, 8);
    final value = _cache.getUint64(offset);
    if (value < 0) _invalid('chunk offset exceeds signed file offsets');
    return value;
  }
}

final class _SampleSizes {
  final int count, fixed, bits, stride;
  final _PagedTable? table;
  final List<int> sums = [];
  _SampleSizes(this.count, this.fixed, this.bits, this.table)
    : stride = math.max(1, (count + 4095) ~/ 4096) {
    if (fixed != 0) {
      _checkSize(fixed);
      return;
    }
    var total = 0;
    for (var i = 0; i < count; i++) {
      if (i % 256 == 0) table?.reader.checkCancelled?.call();
      if (i % stride == 0) sums.add(total);
      total += at(i);
    }
    // A terminal checkpoint makes sumBefore(count) bounded too.
    if (count % stride == 0) sums.add(total);
  }
  static _SampleSizes open(_Reader r, _Box? stsz, _Box? stz2) {
    if ((stsz == null) == (stz2 == null)) {
      _invalid('missing or ambiguous sample sizes');
    }
    final box = (stsz ?? stz2)!;
    r.fullBoxZero(box);
    final word = r.u32(box.data + 4, box.end);
    final count = r.u32(box.data + 8, box.end);
    if (stsz != null) {
      return _SampleSizes(
        count,
        word,
        32,
        word == 0 ? r.table(box.data + 12, count, 4, box.end) : null,
      );
    }
    final bits = word & 0xff;
    if (word >> 8 != 0 || ![4, 8, 16].contains(bits)) {
      _invalid('compact sample-size width');
    }
    final length = (count * bits + 7) ~/ 8;
    return _SampleSizes(
      count,
      0,
      bits,
      r.table(box.data + 12, length, 1, box.end),
    );
  }

  static void _checkSize(int size) {
    if (size < 1 || size > 8184) _invalid('AAC packet size cannot fit ADTS');
  }

  int at(int index) {
    if (index < 0 || index >= count) _invalid('sample-size index');
    if (fixed != 0) return fixed;
    final int value;
    switch (bits) {
      case 4:
        final byte = table!.u8(index ~/ 2);
        value = index.isEven ? byte >> 4 : byte & 15;
      case 8:
        value = table!.u8(index);
      case 16:
        value = (table!.u8(index * 2) << 8) | table!.u8(index * 2 + 1);
      default:
        value = table!.u32(index * 4);
    }
    _checkSize(value);
    return value;
  }

  int sumBefore(int index) {
    if (index < 0 || index > count) _invalid('sample-size sum bounds');
    if (fixed != 0) return index * fixed;
    final checkpoint = index ~/ stride;
    var sum = sums[checkpoint];
    for (var i = checkpoint * stride; i < index; i++) {
      sum += at(i);
    }
    return sum;
  }
}

final class _MappingPoint {
  final int entry, firstSample;
  const _MappingPoint(this.entry, this.firstSample);
}

final class _Run {
  final int firstChunk, firstSample, endSample, perChunk;
  const _Run(this.firstChunk, this.firstSample, this.endSample, this.perChunk);
}

({int rate, int channels, int rateIndex}) _aacConfig(Uint8List bytes) {
  Uint8List? asc;
  void descriptors(int begin, int end, int depth, {bool decoder = false}) {
    if (depth > 4) _invalid('AAC descriptor nesting');
    var at = begin;
    while (at < end) {
      final tag = bytes[at++];
      var length = 0;
      var complete = false;
      for (var i = 0; i < 4; i++) {
        if (at >= end) _invalid('truncated AAC descriptor');
        final value = bytes[at++];
        length = length * 128 + (value & 127);
        if (value & 128 == 0) {
          complete = true;
          break;
        }
      }
      if (!complete || length > end - at) _invalid('AAC descriptor length');
      final next = at + length;
      if (tag == 3) {
        if (length < 3) _invalid('ES descriptor');
        final flags = bytes[at + 2];
        var child = at + 3;
        if (flags & 128 != 0) child += 2;
        if (flags & 64 != 0) {
          if (child >= next) _invalid('ES URL descriptor');
          child += 1 + bytes[child];
        }
        if (flags & 32 != 0) child += 2;
        if (child > next) _invalid('ES descriptor fields');
        descriptors(child, next, depth + 1);
      } else if (tag == 4) {
        if (length < 13) _invalid('decoder descriptor');
        if (![0x40, 0x67].contains(bytes[at]) || bytes[at + 1] >> 2 != 5) {
          _unsupported('non-AAC elementary stream');
        }
        descriptors(at + 13, next, depth + 1, decoder: true);
      } else if (tag == 5 && decoder) {
        if (asc != null) _invalid('multiple AAC configurations');
        asc = Uint8List.sublistView(bytes, at, next);
      }
      at = next;
    }
  }

  descriptors(0, bytes.length, 0);
  if (asc == null || asc!.length > 64) {
    _invalid('missing or oversized AudioSpecificConfig');
  }
  final bits = _Bits(asc!);
  var type = bits.read(5);
  if (type == 31) type = 32 + bits.read(6);
  var rateIndex = bits.read(4);
  const rates = [
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
    7350,
  ];
  int rate;
  if (rateIndex == 15) {
    rate = bits.read(24);
    rateIndex = rates.indexOf(rate);
  } else {
    if (rateIndex >= rates.length) _invalid('AAC sample rate');
    rate = rates[rateIndex];
  }
  final channels = bits.read(4);
  if (type != 2) _unsupported('AAC profile $type (AAC-LC required)');
  if (rateIndex < 0 || rate < 8000) _unsupported('AAC sample rate $rate');
  if (channels != 1 && channels != 2) {
    _unsupported('AAC channel configuration $channels');
  }
  if (bits.read(1) != 0) _unsupported('960-frame AAC');
  if (bits.read(1) != 0) _unsupported('AAC core-coder dependency');
  if (bits.read(1) != 0) _unsupported('AAC extension flags');
  if (bits.remaining >= 16) {
    final sync = bits.read(11);
    if (sync == 0x2b7) {
      final extension = bits.read(5);
      if (extension != 5) _unsupported('AAC extension profile $extension');
      if (bits.read(1) != 0) _unsupported('HE-AAC/SBR');
    } else if (sync != 0) {
      _unsupported('AAC configuration extension');
    }
  }
  // Permit padding only; a PS/SBR extension is not silently treated as LC.
  while (bits.remaining > 0) {
    if (bits.read(1) != 0) _unsupported('AAC configuration extension');
  }
  return (rate: rate, channels: channels, rateIndex: rateIndex);
}

final class _Bits {
  final Uint8List data;
  int at = 0;
  _Bits(this.data);
  int get remaining => data.length * 8 - at;
  int read(int count) {
    if (count > remaining) _invalid('truncated AAC configuration');
    var value = 0;
    for (var i = 0; i < count; i++, at++) {
      value = (value << 1) | ((data[at ~/ 8] >> (7 - at % 8)) & 1);
    }
    return value;
  }
}
