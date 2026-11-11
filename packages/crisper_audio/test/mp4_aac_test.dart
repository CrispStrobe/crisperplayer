// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_audio/src/mp4_aac.dart';

Uint8List _u32(int n) => (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
Uint8List _u64(int n) => (ByteData(8)..setUint64(0, n)).buffer.asUint8List();
List<int> _box(String type, List<int> payload) => [
  ..._u32(payload.length + 8),
  ...type.codeUnits,
  ...payload,
];
List<int> _full(String type, List<int> payload) =>
    _box(type, [0, 0, 0, 0, ...payload]);
List<int> _desc(int type, List<int> payload) => [
  type,
  payload.length,
  ...payload,
];

class _Fixture {
  _Fixture(this.file, this.reader, this.firstData);
  final File file;
  final RandomAccessFile reader;
  final int firstData;
  void close() => reader.closeSync();
}

_Fixture _fixture(
  Directory directory, {
  bool wide = false,
  bool compact = false,
  bool fragmented = false,
  bool encrypted = false,
  int gap = 0,
  int count = 4,
  int fixed = 0,
  int? trim,
  int? presentationFrames,
  int? finalFrames,
  int editCount = 1,
  bool wideEdit = false,
  bool? selfContainedReference,
  bool duplicateConfig = false,
  List<int> asc = const [0x12, 0x10],
  List<int>? forcedOffsets,
}) {
  final path = File('${directory.path}/fixture.m4b');
  final sizes = fixed != 0
      ? const <int>[]
      : List.generate(count, (i) => i % 4 + 2);
  final mediaLength = fixed != 0
      ? fixed * count
      : sizes.reduce((a, b) => a + b);
  List<int> movie(List<int> offsets) {
    final config = _desc(3, [
      0,
      1,
      0,
      ..._desc(4, [0x40, 0x15, ...List.filled(11, 0), ..._desc(5, asc)]),
      ..._desc(6, [2]),
    ]);
    final entry = ByteData(28)
      ..setUint16(6, 1)
      ..setUint16(16, 2)
      ..setUint16(18, 16)
      ..setUint32(24, 44100 << 16);
    final sampleEntry = _box(encrypted ? 'enca' : 'mp4a', [
      ...entry.buffer.asUint8List(),
      ..._full('esds', config),
      if (duplicateConfig) ..._full('esds', config),
    ]);
    final sizeTable = compact
        ? _full('stz2', [
            0,
            0,
            0,
            4,
            ..._u32(count),
            for (var i = 0; i < count; i += 2)
              (sizes[i] << 4) | (i + 1 < count ? sizes[i + 1] : 0),
          ])
        : _full('stsz', [
            ..._u32(fixed),
            ..._u32(count),
            for (final size in sizes) ..._u32(size),
          ]);
    final stbl = _box('stbl', [
      ..._full('stsd', [..._u32(1), ...sampleEntry]),
      ..._full('stts', [
        ..._u32(finalFrames == null ? 1 : 2),
        ..._u32(finalFrames == null ? count : count - 1),
        ..._u32(1024),
        if (finalFrames != null) ...[..._u32(1), ..._u32(finalFrames)],
      ]),
      ..._full('stsc', [..._u32(1), ..._u32(1), ..._u32(count), ..._u32(1)]),
      ...sizeTable,
      ..._full(wide ? 'co64' : 'stco', [
        ..._u32(offsets.length),
        for (final offset in offsets) ...(wide ? _u64(offset) : _u32(offset)),
      ]),
    ]);
    final timing = [
      ...List.filled(8, 0),
      ..._u32(44100),
      ..._u32(count * 1024),
    ];
    return _box('moov', [
      ..._full('mvhd', timing),
      if (fragmented) ..._box('mvex', []),
      ..._box('trak', [
        if (trim != null)
          ..._box('edts', [
            ..._box('elst', [
              wideEdit ? 1 : 0,
              0,
              0,
              0,
              ..._u32(editCount),
              ...(wideEdit ? _u64 : _u32)(
                presentationFrames ?? (count * 1024 - trim),
              ),
              ...(wideEdit ? _u64 : _u32)(trim),
              ..._u32(0x10000),
            ]),
          ]),
        ..._box('mdia', [
          ..._full('mdhd', timing),
          ..._full('hdlr', [..._u32(0), ...'soun'.codeUnits]),
          ..._box('minf', [
            if (selfContainedReference != null)
              ..._box(
                'dinf',
                _full('dref', [
                  ..._u32(1),
                  ..._box('url ', [
                    ..._u32(selfContainedReference ? 1 : 0),
                    if (!selfContainedReference)
                      ...'external-audio.aac\x00'.codeUnits,
                  ]),
                ]),
              ),
            ...stbl,
          ]),
        ]),
      ]),
    ]);
  }

  final first = movie([0]).length + (wide ? 16 : 8) + gap;
  final moov = movie(forcedOffsets ?? [first]);
  final file = path.openSync(mode: FileMode.write);
  file.writeFromSync(moov);
  if (wide) {
    file.writeFromSync([
      ..._u32(1),
      ...'mdat'.codeUnits,
      ..._u64(16 + gap + mediaLength),
    ]);
  } else {
    file.writeFromSync([..._u32(8 + gap + mediaLength), ...'mdat'.codeUnits]);
  }
  // Sparse payload makes the >4 GiB co64 case cheap and proves no whole-file
  // buffer or int32 length lies between the parser and the actual file API.
  file.truncateSync(first + mediaLength);
  if (fixed == 0) {
    file.setPositionSync(first);
    for (var i = 0; i < sizes.length; i++) {
      file.writeFromSync(List.filled(sizes[i], i + 1));
    }
  }
  return _Fixture(path, file, first);
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('crisper-mp4-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('sample tables support sequential reads and backwards random seeks', () {
    final fixture = _fixture(directory);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.sampleRate, 44100);
      expect(track.sampleRateIndex, 4);
      expect(track.channels, 2);
      expect(track.totalFrames, 4096);
      expect(track.trimStartFrames, 0);
      final offsets = [0, 2, 5, 9];
      for (final index in [0, 1, 3, 2, 0, 3]) {
        final packet = track.packetAt(index);
        expect(packet.offset, fixture.firstData + offsets[index]);
        expect(packet.length, index + 2);
        expect(packet.startFrame, index * 1024);
        fixture.reader.setPositionSync(packet.offset);
        expect(fixture.reader.readSync(packet.length), everyElement(index + 1));
      }
      expect(() => track.packetAt(4), throwsRangeError);
    } finally {
      fixture.close();
    }
  });

  test(
    'AAC edit trims priming and presentation tail without changing packet positions',
    () {
      final fixture = _fixture(directory, trim: 1024, presentationFrames: 2880);
      try {
        final track = Mp4AacTrack.open(fixture.reader);
        expect(track.trimStartFrames, 1024);
        expect(track.totalFrames, 2880);
        expect(track.packetAt(1).startFrame, 1024);
      } finally {
        fixture.close();
      }
    },
  );

  test('final partial sample timing bounds the decoded presentation', () {
    final fixture = _fixture(directory, finalFrames: 128, trim: 1024);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.totalFrames, 2176);
      expect(track.packetAt(3).frames, 1024);
    } finally {
      fixture.close();
    }
  });

  test('version1 edits retain their 64-bit source/presentation timing', () {
    final fixture = _fixture(
      directory,
      trim: 1024,
      presentationFrames: 2880,
      wideEdit: true,
    );
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.trimStartFrames, 1024);
      expect(track.totalFrames, 2880);
    } finally {
      fixture.close();
    }
  });

  test(
    'version1 edit multiplication cannot wrap an out-of-range trim to zero',
    () {
      final fixture = _fixture(
        directory,
        trim: 1 << 62,
        presentationFrames: 1024,
        wideEdit: true,
      );
      try {
        expect(() => Mp4AacTrack.open(fixture.reader), throwsFormatException);
      } finally {
        fixture.close();
      }
    },
  );

  test('version1 presentation duration cannot wrap into a shorter track', () {
    final fixture = _fixture(
      directory,
      trim: 0,
      presentationFrames: (1 << 62) + 100,
      wideEdit: true,
    );
    try {
      expect(Mp4AacTrack.open(fixture.reader).totalFrames, 4096);
    } finally {
      fixture.close();
    }
  });

  test('compact sample-size tables preserve variable packet lengths', () {
    final fixture = _fixture(directory, compact: true);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.packetAt(3).offset, fixture.firstData + 9);
      expect(track.packetAt(1).length, 3);
    } finally {
      fixture.close();
    }
  });

  test('co64 addresses a sparse audio payload beyond 4 GiB', () {
    final fixture = _fixture(directory, wide: true, gap: 1 << 32);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.packetAt(3).offset, greaterThan(1 << 32));
      fixture.reader.setPositionSync(track.packetAt(3).offset);
      expect(fixture.reader.readSync(5), [4, 4, 4, 4, 4]);
    } finally {
      fixture.close();
    }
  });

  test('millions of fixed-size packets need no per-packet metadata array', () {
    final fixture = _fixture(directory, count: 2000000, fixed: 2);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(track.sampleCount, 2000000);
      expect(track.packetAt(1999999).offset, fixture.firstData + 3999998);
      expect(track.packetAt(1).offset, fixture.firstData + 2);
    } finally {
      fixture.close();
    }
  });

  test('LC configuration with disabled SBR extension is accepted', () {
    final fixture = _fixture(directory, asc: [0x12, 0x10, 0x56, 0xe5, 0]);
    try {
      expect(Mp4AacTrack.open(fixture.reader).sampleRate, 44100);
    } finally {
      fixture.close();
    }
  });

  test('data-reference1 must actually point to self-contained media', () {
    final fixture = _fixture(directory, selfContainedReference: false);
    try {
      expect(() => Mp4AacTrack.open(fixture.reader), throwsUnsupportedError);
    } finally {
      fixture.close();
    }
  });

  test('explicit self-contained URL data reference is accepted', () {
    final fixture = _fixture(directory, selfContainedReference: true);
    try {
      expect(Mp4AacTrack.open(fixture.reader).totalFrames, 4096);
    } finally {
      fixture.close();
    }
  });

  test('duplicate AAC configuration is rejected as ambiguous metadata', () {
    final fixture = _fixture(directory, duplicateConfig: true);
    try {
      expect(() => Mp4AacTrack.open(fixture.reader), throwsFormatException);
    } finally {
      fixture.close();
    }
  });

  for (final mode in ['fragmented', 'encrypted', 'HE-AAC', 'multiple edits']) {
    test('$mode is rejected instead of mislabeled as AAC-LC', () {
      final fixture = _fixture(
        directory,
        fragmented: mode == 'fragmented',
        encrypted: mode == 'encrypted',
        asc: mode == 'HE-AAC' ? [0x2a, 0x10] : [0x12, 0x10],
        trim: mode == 'multiple edits' ? 0 : null,
        editCount: 2,
      );
      try {
        expect(() => Mp4AacTrack.open(fixture.reader), throwsUnsupportedError);
      } finally {
        fixture.close();
      }
    });
  }

  test('packet offsets cannot refer to metadata or outside media data', () {
    final fixture = _fixture(directory, forcedOffsets: [0]);
    try {
      final track = Mp4AacTrack.open(fixture.reader);
      expect(() => track.packetAt(0), throwsFormatException);
    } finally {
      fixture.close();
    }
  });

  test(
    'cancellation during metadata scan leaves file ownership with caller',
    () {
      final fixture = _fixture(directory);
      var reads = 0;
      try {
        expect(
          () => Mp4AacTrack.open(
            fixture.reader,
            checkCancelled: () {
              if (++reads == 12) throw StateError('cancelled');
            },
          ),
          throwsStateError,
        );
        expect(reads, 12);
        expect(fixture.reader.lengthSync(), greaterThan(0));
      } finally {
        fixture.close();
      }
    },
  );
}
