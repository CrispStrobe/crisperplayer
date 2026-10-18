import 'dart:convert';
import 'dart:io';
import 'mp4_metadata.dart';
import 'dart:typed_data';

/// One chapter extracted from an MP4/M4B file.
///
/// [start] and [end] are offsets from the start of the book (same
/// timescale as the file – converted to [Duration]).
class ParsedChapter {
  final String title;
  final Duration start;
  final Duration end;
  const ParsedChapter({
    required this.title,
    required this.start,
    required this.end,
  });
}

/// Parse chapters from a single-file m4a/m4b without FFI.
///
/// Strategy:
/// 1. Scan MP4 atoms to find `moov.udta.chpl` (Nero chapters).
/// 2. Otherwise read the text samples from a referenced QuickTime chapter track.
///    Sample tables and text reads are bounded; audio payloads are never loaded.
/// 3. If found, convert 100-ns start times to ms and synthesize end times
///    from the next chapter or totalDuration.
class ChapterParser {
  /// Try to extract real chapter table from [filePath].
  /// Returns `null` when no chapter metadata exists (caller should fallback).
  /// Throws only on IO errors – malformed atoms are treated as "no chapters".
  static Future<List<ParsedChapter>?> parseFile(
    String filePath, {
    Duration? totalDuration,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    Uint8List bytes;
    try {
      bytes = await readMp4Metadata(file);
    } on FormatException {
      return null;
    }
    if (bytes.length < 16) return null;
    final chapters = _parseBytes(bytes, totalDuration: totalDuration);
    if (chapters != null && chapters.isNotEmpty) return chapters;
    final samples = _quickTimeSamples(bytes);
    if (samples == null) return null;
    final input = await file.open();
    try {
      final length = await input.length();
      final entries = <_RawEntry>[];
      for (final sample in samples) {
        if (sample.offset < 0 || sample.offset + sample.size > length) {
          return null;
        }
        await input.setPosition(sample.offset);
        final data = await input.read(sample.size);
        if (data.length != sample.size) return null;
        final title = _sampleTitle(data);
        if (title == null) return null;
        entries.add(_RawEntry(start100ns: sample.start100ns, title: title));
      }
      return _toParsedChapters(
        entries,
        totalDuration:
            totalDuration ??
            Duration(microseconds: samples.last.end100ns ~/ 10),
      );
    } finally {
      await input.close();
    }
  }

  /// Synchronous parse from raw bytes – useful for testing with synthetic headers.
  static List<ParsedChapter>? parseBytes(
    Uint8List bytes, {
    Duration? totalDuration,
  }) {
    final nero = _parseBytes(bytes, totalDuration: totalDuration);
    if (nero != null) return nero;
    final samples = _quickTimeSamples(bytes);
    if (samples == null) return null;
    final entries = <_RawEntry>[];
    for (final sample in samples) {
      if (sample.offset < 0 || sample.offset + sample.size > bytes.length) {
        return null;
      }
      final title = _sampleTitle(
        bytes.sublist(sample.offset, sample.offset + sample.size),
      );
      if (title == null) return null;
      entries.add(_RawEntry(start100ns: sample.start100ns, title: title));
    }
    return _toParsedChapters(
      entries,
      totalDuration:
          totalDuration ?? Duration(microseconds: samples.last.end100ns ~/ 10),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static List<ParsedChapter>? _parseBytes(
    Uint8List bytes, {
    Duration? totalDuration,
  }) {
    // Find moov, then search for chpl anywhere under it.
    final atoms = _scanAtoms(bytes, 0, bytes.length);
    final moov = _findAtom(atoms, 'moov', bytes);
    if (moov == null) return null;

    // Try chpl (Nero) – search recursively under moov.
    final chpl = _findRecursive(moov, 'chpl', bytes);
    if (chpl != null) {
      final raw = _payload(chpl, bytes);
      final entries = _parseChplPayload(raw);
      if (entries != null && entries.isNotEmpty) {
        return _toParsedChapters(entries, totalDuration: totalDuration);
      }
      // If chpl payload exists but is malformed, treat as no chapters
      // to trigger fallback rather than crash.
      return null;
    }

    return null;
  }

  /// Convert raw chpl entries (start in 100-ns units, title) to [ParsedChapter].
  static List<ParsedChapter> _toParsedChapters(
    List<_RawEntry> entries, {
    Duration? totalDuration,
  }) {
    // Entries already sorted by start (chpl order is chronological).
    final out = <ParsedChapter>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final startMs = (e.start100ns ~/ 10000);
      int endMs;
      if (i + 1 < entries.length) {
        endMs = (entries[i + 1].start100ns ~/ 10000);
      } else if (totalDuration != null && totalDuration.inMilliseconds > 0) {
        endMs = totalDuration.inMilliseconds;
      } else {
        // A zero-length last chapter marks an unknown endpoint until probing.
        endMs = startMs;
      }
      // Guard against zero/negative durations
      if (endMs < startMs) endMs = startMs;
      out.add(
        ParsedChapter(
          title: e.title.isEmpty ? 'Chapter ${i + 1}' : e.title,
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: endMs),
        ),
      );
    }
    return out;
  }

  // -- chpl payload parsing --------------------------------------------------

  static List<_RawEntry>? _parseChplPayload(Uint8List payload) {
    if (payload.length < 9) return null;
    // Go variant: version(1) + 7 reserved(0) + count(1) = 9 bytes before entries
    // Wiki variant: version(1)+flags(3)+reserved(1)+count(4 BE)=9 bytes as well
    // Try Go first, then wiki.

    // Try Go: data[0] is version 0 or 1, data[1..7] all zero, count at 8
    if ((payload[0] == 0 || payload[0] == 1)) {
      bool goReservedOk = true;
      for (int i = 1; i < 8; i++) {
        if (payload[i] != 0) {
          goReservedOk = false;
          break;
        }
      }
      if (goReservedOk) {
        final count = payload[8];
        final parsed = _parseChplEntries(payload, 9, count);
        if (parsed != null) return parsed;
      }
    }
    // Try wiki: version byte, 3 flags zero, 1 reserved zero, 4-byte BE count
    // payload[1..3] flags often 0, payload[4] reserved 0
    if (payload.length >= 9) {
      // allow non-zero flags tolerance: just check reserved-ish bytes
      final count = _u32BE(payload, 5);
      // sanity: count plausible (1..1024) and payload large enough
      if (count > 0 && count <= 2048) {
        final parsed = _parseChplEntries(payload, 9, count);
        if (parsed != null) return parsed;
      }
    }
    // Also handle files where version+flags are 4 bytes already counted, so
    // count is at offset 5 with 4 bytes, but we started counting at 0 including
    // version, so 4+1+4=9 – same as above but we already tried.
    // Last resort: try single-byte count at 5 (some encoders)
    if (payload.length >= 6) {
      // Check if payload[1..4]==0 and count at 5 is small and parses
      bool zeros = true;
      for (int i = 1; i < 5; i++) {
        if (payload[i] != 0) zeros = false;
      }
      if (zeros) {
        final c = payload[5];
        if (c > 0 && c < 128) {
          // this would be weird layout: version(1) + 4 reserved + count(1)
          final p = _parseChplEntries(payload, 6, c);
          if (p != null) return p;
        }
      }
    }
    return null;
  }

  static List<_RawEntry>? _parseChplEntries(
    Uint8List payload,
    int offset,
    int count,
  ) {
    int pos = offset;
    final out = <_RawEntry>[];
    for (int i = 0; i < count; i++) {
      if (pos + 9 > payload.length) return null; // need 8 start +1 len
      final start = _u64BE(payload, pos);
      final len = payload[pos + 8];
      pos += 9;
      if (pos + len > payload.length) return null;
      final title = utf8.decode(
        payload.sublist(pos, pos + len),
        allowMalformed: true,
      );
      pos += len;
      out.add(_RawEntry(start100ns: start, title: title));
    }
    // Accept trailing bytes as padding? Go requires exact consume, but be permissive.
    return out;
  }

  // QuickTime chapters are a text track referenced by tref.chap, not any
  // arbitrary subtitle track. See Apple's QTFF Chapter lists and TN2174.
  static List<_ChapterSample>? _quickTimeSamples(Uint8List bytes) {
    try {
      final moov = _findAtom(_scanAtoms(bytes, 0, bytes.length), 'moov', bytes);
      if (moov == null) return null;
      final tracks = _childrenOf(
        moov,
        bytes,
      ).where((a) => a.type == 'trak').toList();
      final ids = <int>{};
      for (final track in tracks) {
        final header = _childPayload(track, 'tkhd', bytes);
        if (header == null || header.length < 4 || (header[3] & 1) == 0) {
          continue;
        }
        final refs = _child(track, 'tref', bytes);
        final chap = refs == null ? null : _childPayload(refs, 'chap', bytes);
        if (chap != null) {
          for (var i = 0; i + 4 <= chap.length; i += 4) {
            ids.add(_u32BE(chap, i));
          }
        }
      }
      for (final track in tracks) {
        final header = _childPayload(track, 'tkhd', bytes);
        if (header == null) continue;
        final idOffset = header[0] == 1 ? 20 : 12;
        if (!ids.contains(_u32BE(header, idOffset))) continue;
        final mdia = _child(track, 'mdia', bytes);
        if (mdia == null) continue;
        final mdhd = _childPayload(mdia, 'mdhd', bytes);
        final handler = _childPayload(mdia, 'hdlr', bytes);
        if (mdhd == null ||
            handler == null ||
            handler.length < 12 ||
            !{'text', 'sbtl', 'subt'}.contains(_typeStr(handler, 8))) {
          continue;
        }
        final scale = _u32BE(mdhd, mdhd[0] == 1 ? 20 : 12);
        if (scale == 0) return null;
        final minf = _child(mdia, 'minf', bytes);
        final stbl = minf == null ? null : _child(minf, 'stbl', bytes);
        if (stbl == null) return null;
        final stsd = _childPayload(stbl, 'stsd', bytes);
        if (stsd == null ||
            _u32BE(stsd, 4) != 1 ||
            !{'text', 'tx3g'}.contains(_typeStr(stsd, 12))) {
          return null;
        }
        final sizes = _childPayload(stbl, 'stsz', bytes);
        final timing = _childPayload(stbl, 'stts', bytes);
        final mapping = _childPayload(stbl, 'stsc', bytes);
        final co64 = _childPayload(stbl, 'co64', bytes);
        final offsets = co64 ?? _childPayload(stbl, 'stco', bytes);
        if (sizes == null ||
            timing == null ||
            mapping == null ||
            offsets == null) {
          return null;
        }
        final count = _u32BE(sizes, 8);
        if (count == 0 || count > 10000) return null;
        final uniformSize = _u32BE(sizes, 4);
        final sampleSizes = [
          for (var i = 0; i < count; i++)
            uniformSize == 0 ? _u32BE(sizes, 12 + i * 4) : uniformSize,
        ];
        if (sampleSizes.any((s) => s < 2 || s > 65537) ||
            sampleSizes.fold<int>(0, (a, b) => a + b) > 8 * 1024 * 1024) {
          return null;
        }
        final durations = <int>[];
        final timingCount = _u32BE(timing, 4);
        if (timingCount > count) return null;
        for (var i = 0; i < timingCount; i++) {
          final n = _u32BE(timing, 8 + i * 8);
          final delta = _u32BE(timing, 12 + i * 8);
          if (n == 0 || n + durations.length > count) return null;
          durations.addAll(List.filled(n, delta));
        }
        if (durations.length != count) return null;
        final chunkCount = _u32BE(offsets, 4);
        final mapCount = _u32BE(mapping, 4);
        if (chunkCount == 0 ||
            chunkCount > count ||
            mapCount == 0 ||
            mapCount > chunkCount) {
          return null;
        }
        final maps = <(int, int)>[];
        for (var i = 0; i < mapCount; i++) {
          final first = _u32BE(mapping, 8 + i * 12);
          final perChunk = _u32BE(mapping, 12 + i * 12);
          final description = _u32BE(mapping, 16 + i * 12);
          if (first < 1 ||
              first > chunkCount ||
              perChunk < 1 ||
              perChunk > count ||
              description != 1 ||
              (i == 0 ? first != 1 : first <= maps.last.$1)) {
            return null;
          }
          maps.add((first, perChunk));
        }
        // Respect the common edit-list form: an optional initial empty edit,
        // followed by one continuous media edit at normal speed.
        var shift100ns = 0;
        final edts = _child(track, 'edts', bytes);
        if (edts != null) {
          final elst = _childPayload(edts, 'elst', bytes);
          final mvhd = _childPayload(moov, 'mvhd', bytes);
          if (elst == null || mvhd == null) return null;
          final movieScale = _u32BE(mvhd, mvhd[0] == 1 ? 20 : 12);
          final editCount = _u32BE(elst, 4);
          if (movieScale == 0 || editCount < 1 || editCount > 2) return null;
          final wide = elst[0] == 1;
          final view = ByteData.sublistView(elst);
          for (var i = 0; i < editCount; i++) {
            final p = 8 + i * (wide ? 20 : 12);
            final length = wide ? view.getUint64(p) : view.getUint32(p);
            final media = wide ? view.getInt64(p + 8) : view.getInt32(p + 4);
            final rate = view.getUint32(p + (wide ? 16 : 8));
            if (rate != 0x10000) return null;
            if (media == -1 && i == 0 && editCount == 2) {
              shift100ns += length * 10000000 ~/ movieScale;
            } else if (media >= 0 && i == editCount - 1) {
              shift100ns -= media * 10000000 ~/ scale;
            } else {
              return null;
            }
          }
        }
        final out = <_ChapterSample>[];
        var sample = 0;
        var time = 0;
        var map = 0;
        for (var chunk = 1; chunk <= chunkCount; chunk++) {
          while (map + 1 < maps.length && maps[map + 1].$1 <= chunk) {
            map++;
          }
          var offset = co64 == null
              ? _u32BE(offsets, 8 + (chunk - 1) * 4)
              : _u64BE(offsets, 8 + (chunk - 1) * 8);
          for (var i = 0; i < maps[map].$2; i++) {
            if (sample >= count) return null;
            final start = time * 10000000 ~/ scale + shift100ns;
            time += durations[sample];
            if (start < 0) return null;
            out.add(
              _ChapterSample(
                offset,
                sampleSizes[sample],
                start,
                time * 10000000 ~/ scale + shift100ns,
              ),
            );
            offset += sampleSizes[sample++];
          }
        }
        return sample == count ? out : null;
      }
    } on RangeError {
      // Missing/truncated tables are not usable chapter metadata.
      return null;
    }
    return null;
  }

  static _Atom? _child(_Atom parent, String type, Uint8List bytes) =>
      _findAtom(_childrenOf(parent, bytes), type, bytes);

  static Uint8List? _childPayload(_Atom parent, String type, Uint8List bytes) {
    final atom = _child(parent, type, bytes);
    return atom == null ? null : _payload(atom, bytes);
  }

  static String? _sampleTitle(Uint8List sample) {
    if (sample.length < 2) return null;
    final length = (sample[0] << 8) | sample[1];
    if (length + 2 > sample.length) return null;
    final text = sample.sublist(2, 2 + length);
    if (text.length >= 2 &&
        ((text[0] == 0xfe && text[1] == 0xff) ||
            (text[0] == 0xff && text[1] == 0xfe))) {
      if (text.length.isOdd) return null;
      final little = text[0] == 0xff;
      final data = ByteData.sublistView(text);
      return String.fromCharCodes([
        for (var i = 2; i < text.length; i += 2)
          data.getUint16(i, little ? Endian.little : Endian.big),
      ]);
    }
    return utf8.decode(text, allowMalformed: true);
  }

  // -- Atom scanning ---------------------------------------------------------

  static _Atom? _findAtom(List<_Atom> atoms, String type, Uint8List bytes) {
    for (final a in atoms) {
      if (a.type == type) return a;
    }
    return null;
  }

  static _Atom? _findRecursive(
    _Atom root,
    String type,
    Uint8List bytes, [
    int depth = 0,
  ]) {
    if (depth > 12) return null;
    if (root.type == type) return root;
    final children = _childrenOf(root, bytes);
    for (final c in children) {
      if (c.type == type) return c;
      if ({'moov', 'udta', 'meta', 'ilst'}.contains(c.type)) {
        final deep = _findRecursive(c, type, bytes, depth + 1);
        if (deep != null) return deep;
      }
    }
    return null;
  }

  static List<_Atom> _childrenOf(_Atom parent, Uint8List bytes) {
    int start = parent.dataStart;
    int end = parent.offset + parent.size;
    // Special case: 'meta' has 4 extra bytes (version+flags) before children
    if (parent.type == 'meta') {
      // payload begins with 4 bytes version/flags
      if (start + 4 <= end) start += 4;
    }
    return _scanAtoms(bytes, start, end);
  }

  /// Scan atoms in [bytes] from [start] (inclusive) to [end] (exclusive).
  static List<_Atom> _scanAtoms(Uint8List bytes, int start, int end) {
    final out = <_Atom>[];
    int pos = start;
    while (pos + 8 <= end) {
      final size = _u32BE(bytes, pos);
      final type = _typeStr(bytes, pos + 4);
      int headerSize = 8;
      int atomSize = size;

      if (size == 1) {
        // 64-bit size
        if (pos + 16 > end) break;
        atomSize = _u64BE(bytes, pos + 8).toInt();
        headerSize = 16;
      } else if (size == 0) {
        atomSize = end - pos;
      }

      if (atomSize < headerSize || atomSize == 0) break;
      if (pos + atomSize > end) {
        // Atom claims to extend beyond buffer – truncate or break
        // For moov at end of file, size should match. If mismatch, break.
        // But allow last atom to be truncated due to EOF.
        if (type == 'mdat' || type == 'moov') {
          // be permissive: clamp to end
          atomSize = end - pos;
        } else {
          break;
        }
      }

      final dataStart = pos + headerSize;
      // For 'meta', dataStart will be adjusted in _childrenOf
      out.add(
        _Atom(
          type: type,
          offset: pos,
          size: atomSize,
          headerSize: headerSize,
          dataStart: dataStart,
        ),
      );

      pos += atomSize;
    }
    return out;
  }

  static Uint8List _payload(_Atom atom, Uint8List bytes) {
    final end = atom.offset + atom.size;
    final start = atom.dataStart;
    if (start >= end) return Uint8List(0);
    // Clamp to bytes length
    final s = start.clamp(0, bytes.length);
    final e = end.clamp(0, bytes.length);
    return bytes.sublist(s, e);
  }

  // -- byte helpers ----------------------------------------------------------

  static int _u32BE(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static int _u64BE(Uint8List b, int off) {
    // Dart int is 64-bit, so we can combine two 32-bit halves
    final hi = _u32BE(b, off);
    final lo = _u32BE(b, off + 4);
    return (hi * 0x100000000) + lo;
  }

  static String _typeStr(Uint8List b, int off) {
    // 4 ASCII chars, may contain non-printable for © – handle generically
    final chars = <int>[];
    for (int i = 0; i < 4; i++) {
      chars.add(b[off + i]);
    }
    // For © (0xA9), first byte is 0xA9; preserve as string via fromCharCode
    return String.fromCharCodes(chars);
  }
}

class _Atom {
  final String type;
  final int offset;
  final int size;
  final int headerSize;
  final int dataStart;
  _Atom({
    required this.type,
    required this.offset,
    required this.size,
    required this.headerSize,
    required this.dataStart,
  });
}

class _RawEntry {
  final int start100ns;
  final String title;
  _RawEntry({required this.start100ns, required this.title});
}

class _ChapterSample {
  final int offset;
  final int size;
  final int start100ns;
  final int end100ns;
  const _ChapterSample(this.offset, this.size, this.start100ns, this.end100ns);
}
