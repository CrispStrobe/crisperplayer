import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisperplayer/services/audio/chapter_parser.dart';
import 'package:crisperplayer/services/audio/cover_extractor.dart';

// Helpers: we need access to internal raw entry type. Since ChapterParser.buildSyntheticMp4
// needs private _RawEntry, we replicate synthetic building manually for cover,
// and for chapters we use ChapterParser's public buildSyntheticMp4 via dynamic trick.
// Instead build chpl manually using parser's own helper exposed via synthetic method
// that we already added – but it uses private type. To work around, we build MP4
// atoms manually here mirroring parser logic.

Uint8List buildChplMp4ForTest() {
  // Build 3 chapters: Intro@0s, Middle@300s, Finale@600s
  // Use ChapterParser's own synthetic builder via constructing raw payload directly
  // We will craft atom bytes manually without relying on private API.
  // Instead directly craft a minimal chpl payload following Go spec:
  // version 0, 7 zeros, count 3, entries.
  final entries = [
    (0, 'Intro'),
    (300000 * 10000, 'Middle'), // 300s -> 300000 ms *10000
    (600000 * 10000, 'Finale'),
  ];
  // chpl payload
  int payloadSize = 9;
  for (final e in entries) payloadSize += 8 + 1 + e.$2.length;
  final payload = Uint8List(payloadSize);
  payload[0] = 0;
  payload[8] = entries.length;
  int pos = 9;
  for (final e in entries) {
    final start = e.$1;
    payload[pos] = (start >> 56) & 0xFF;
    payload[pos + 1] = (start >> 48) & 0xFF;
    payload[pos + 2] = (start >> 40) & 0xFF;
    payload[pos + 3] = (start >> 32) & 0xFF;
    payload[pos + 4] = (start >> 24) & 0xFF;
    payload[pos + 5] = (start >> 16) & 0xFF;
    payload[pos + 6] = (start >> 8) & 0xFF;
    payload[pos + 7] = start & 0xFF;
    final titleBytes = e.$2.codeUnits;
    payload[pos + 8] = titleBytes.length;
    pos += 9;
    for (int i = 0; i < titleBytes.length; i++) payload[pos + i] = titleBytes[i];
    pos += titleBytes.length;
  }
  Uint8List atom(String type, Uint8List p) {
    final size = 8 + p.length;
    final out = Uint8List(size);
    out[0] = (size >> 24) & 0xFF;
    out[1] = (size >> 16) & 0xFF;
    out[2] = (size >> 8) & 0xFF;
    out[3] = size & 0xFF;
    final codes = type.codeUnits;
    for (int i = 0; i < 4; i++) out[4 + i] = codes[i];
    for (int i = 0; i < p.length; i++) out[8 + i] = p[i];
    return out;
  }

  final chplAtom = atom('chpl', payload);
  final udtaAtom = atom('udta', chplAtom);
  final mvhdPayload = Uint8List(100);
  mvhdPayload[12] = 0x00; mvhdPayload[13] = 0x00; mvhdPayload[14] = 0x03; mvhdPayload[15] = 0xE8; // 1000
  mvhdPayload[16] = 0x00; mvhdPayload[17] = 0x00; mvhdPayload[18] = 0x2A; mvhdPayload[19] = 0xF8; // 11000
  final mvhdAtom = atom('mvhd', mvhdPayload);
  final moovPayload = Uint8List.fromList([...mvhdAtom, ...udtaAtom]);
  final moovAtom = atom('moov', moovPayload);
  final ftypPayload = Uint8List.fromList([0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x02, 0x00, 0x4d, 0x34, 0x41, 0x20, 0x69, 0x73, 0x6f, 0x6d]);
  final ftypAtom = atom('ftyp', ftypPayload);
  final mdatAtom = atom('mdat', Uint8List.fromList([0x00, 0x01]));
  return Uint8List.fromList([...ftypAtom, ...mdatAtom, ...moovAtom]);
}

void main() {
  group('ChapterParser', () {
    test('parses synthetic MP4 with 3 Nero chapters', () {
      final mp4 = buildChplMp4ForTest();
      final chapters = ChapterParser.parseBytes(mp4, totalDuration: const Duration(seconds: 900));
      expect(chapters, isNotNull);
      expect(chapters!.length, 3);
      expect(chapters[0].title, 'Intro');
      expect(chapters[1].title, 'Middle');
      expect(chapters[2].title, 'Finale');
      expect(chapters[0].start.inMilliseconds, 0);
      expect(chapters[1].start.inMilliseconds, 300000);
      expect(chapters[2].start.inMilliseconds, 600000);
      // end of previous == start of next
      expect(chapters[0].end.inMilliseconds, 300000);
      expect(chapters[1].end.inMilliseconds, 600000);
      expect(chapters[2].end.inMilliseconds, 900000);
    });

    test('fallback to null when no chpl present', () {
      // Minimal MP4 with only ftyp + mdat + moov(mvhd)
      Uint8List atom(String type, Uint8List p) {
        final size = 8 + p.length;
        final out = Uint8List(size);
        out[0] = (size >> 24) & 0xFF;
        out[1] = (size >> 16) & 0xFF;
        out[2] = (size >> 8) & 0xFF;
        out[3] = size & 0xFF;
        final codes = type.codeUnits;
        for (int i = 0; i < 4; i++) out[4 + i] = codes[i];
        for (int i = 0; i < p.length; i++) out[8 + i] = p[i];
        return out;
      }
      final mvhd = atom('mvhd', Uint8List(20));
      final moov = atom('moov', mvhd);
      final ftyp = atom('ftyp', Uint8List.fromList([0x4d, 0x34, 0x41, 0x20, 0,0,0,0]));
      final mdat = atom('mdat', Uint8List.fromList([0x01]));
      final mp4 = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      final chapters = ChapterParser.parseBytes(mp4, totalDuration: const Duration(seconds: 10));
      expect(chapters, isNull);
    });

    test('fixture jfk-test.m4a has no chapters (fallback)', () async {
      final f = File('/home/claudeuser/jfk-test.m4a');
      if (!await f.exists()) return; // skip if not present in CI
      final bytes = await f.readAsBytes();
      final result = ChapterParser.parseBytes(bytes);
      // jfk sample has no chapters – should be null or empty
      expect(result == null || result.isEmpty, isTrue);
    });

    test('truncated chpl payload does not crash and returns null', () {
      final mp4 = buildChplMp4ForTest();
      // Corrupt count to 99 to force truncation
      // count byte is at payload offset 8 inside chpl atom payload.
      // Find chpl atom header and corrupt.
      final truncated = Uint8List.fromList(mp4);
      // Locate 'chpl' string
      for (int i = 0; i < truncated.length - 4; i++) {
        if (truncated[i] == 0x63 && truncated[i+1]==0x68 && truncated[i+2]==0x70 && truncated[i+3]==0x6c) {
          // payload starts after this 4-byte type
          // chpl payload offset = i+4
          if (i+4+8 < truncated.length) {
            truncated[i+4+8] = 99; // set count to out-of-range
          }
          break;
        }
      }
      final chapters = ChapterParser.parseBytes(truncated);
      // Should be null due to truncated entries
      expect(chapters, isNull);
    });

    test('file API parseFile reads from temp synthetic file', () async {
      final mp4 = buildChplMp4ForTest();
      final tmp = File('${Directory.systemTemp.path}/test_chapters_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await tmp.writeAsBytes(mp4);
      final chapters = await ChapterParser.parseFile(tmp.path, totalDuration: const Duration(seconds: 900));
      expect(chapters, isNotNull);
      expect(chapters!.length, 3);
      await tmp.delete();
    });
  });

  group('CoverExtractor', () {
    test('extracts synthetic JPEG cover', () {
      // Tiny JPEG header: FF D8 FF E0 ... JFIF minimal (not valid image but header detectable)
      final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x02]);
      final mp4 = CoverExtractor.buildSyntheticMp4(fakeJpeg, dataType: 13);
      final extracted = CoverExtractor.extractBytes(mp4);
      expect(extracted, isNotNull);
      expect(extracted![0], 0xFF);
      expect(extracted[1], 0xD8);
      expect(extracted.length, fakeJpeg.length);
    });

    test('extracts synthetic PNG cover', () {
      final fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]);
      final mp4 = CoverExtractor.buildSyntheticMp4(fakePng, dataType: 14);
      final extracted = CoverExtractor.extractBytes(mp4);
      expect(extracted, isNotNull);
      expect(extracted![0], 0x89);
      expect(extracted[1], 0x50);
    });

    test('returns null when no covr present', () {
      Uint8List atom(String type, Uint8List p) {
        final size = 8 + p.length;
        final out = Uint8List(size);
        out[0] = (size >> 24) & 0xFF;
        out[1] = (size >> 16) & 0xFF;
        out[2] = (size >> 8) & 0xFF;
        out[3] = size & 0xFF;
        final codes = type.codeUnits;
        for (int i = 0; i < 4; i++) out[4 + i] = codes[i];
        for (int i = 0; i < p.length; i++) out[8 + i] = p[i];
        return out;
      }
      final mvhd = atom('mvhd', Uint8List(20));
      final moov = atom('moov', mvhd);
      final mp4 = Uint8List.fromList([...atom('ftyp', Uint8List.fromList([0x4d,0x34,0x41,0x20])), ...moov]);
      final extracted = CoverExtractor.extractBytes(mp4);
      expect(extracted, isNull);
    });

    test('fixture jfk-test.m4a has no cover', () async {
      final f = File('/home/claudeuser/jfk-test.m4a');
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      final result = CoverExtractor.extractBytes(bytes);
      expect(result, isNull);
    });

    test('extractCover writes temp file', () async {
      final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final mp4 = CoverExtractor.buildSyntheticMp4(fakeJpeg);
      final tmp = File('${Directory.systemTemp.path}/test_cover_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await tmp.writeAsBytes(mp4);
      final coverPath = await CoverExtractor.extractCover(tmp.path);
      expect(coverPath, isNotNull);
      expect(File(coverPath!).existsSync(), isTrue);
      expect(coverPath.endsWith('.jpg'), isTrue);
      await tmp.delete();
      await File(coverPath).delete();
    });
  });
}
