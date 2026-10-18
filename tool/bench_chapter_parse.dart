import 'dart:io';
import 'dart:typed_data';
import 'package:crisperplayer/services/audio/chapter_parser.dart';

Uint8List buildMp4WithMdat(Uint8List moov, int mdatBytes) {
  Uint8List atom(String type, Uint8List p) {
    final size = 8 + p.length;
    final out = Uint8List(size);
    out[0] = (size >> 24) & 0xFF;
    out[1] = (size >> 16) & 0xFF;
    out[2] = (size >> 8) & 0xFF;
    out[3] = size & 0xFF;
    for (int i = 0; i < 4; i++) {
      out[4 + i] = type.codeUnits[i];
    }
    for (int i = 0; i < p.length; i++) {
      out[8 + i] = p[i];
    }
    return out;
  }

  final ftypPayload = Uint8List.fromList([
    0x4d,
    0x34,
    0x41,
    0x20,
    0,
    0,
    2,
    0,
    0x4d,
    0x34,
    0x41,
    0x20,
    0x69,
    0x73,
    0x6f,
    0x6d
  ]);
  final ftyp = atom('ftyp', ftypPayload);
  final mdatHeader = Uint8List(8);
  final mdatSize = 8 + mdatBytes;
  mdatHeader[0] = (mdatSize >> 24) & 0xFF;
  mdatHeader[1] = (mdatSize >> 16) & 0xFF;
  mdatHeader[2] = (mdatSize >> 8) & 0xFF;
  mdatHeader[3] = mdatSize & 0xFF;
  mdatHeader[4] = 0x6d;
  mdatHeader[5] = 0x64;
  mdatHeader[6] = 0x61;
  mdatHeader[7] = 0x74;
  final mdat = Uint8List.fromList([...mdatHeader, ...Uint8List(mdatBytes)]);
  return Uint8List.fromList([...ftyp, ...mdat, ...moov]);
}

Uint8List buildMoov(int chapters) {
  final entries =
      List.generate(chapters, (i) => (i * 300000 * 10000, 'Chapter ${i + 1}'));
  // reuse buildChpl logic but extract moov only
  int payloadSize = 9;
  for (final e in entries) {
    payloadSize += 8 + 1 + e.$2.length;
  }
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
    final tb = e.$2.codeUnits;
    payload[pos + 8] = tb.length;
    pos += 9;
    for (int i = 0; i < tb.length; i++) {
      payload[pos + i] = tb[i];
    }
    pos += tb.length;
  }
  Uint8List atom(String type, Uint8List p) {
    final size = 8 + p.length;
    final out = Uint8List(size);
    out[0] = (size >> 24) & 0xFF;
    out[1] = (size >> 16) & 0xFF;
    out[2] = (size >> 8) & 0xFF;
    out[3] = size & 0xFF;
    for (int i = 0; i < 4; i++) {
      out[4 + i] = type.codeUnits[i];
    }
    for (int i = 0; i < p.length; i++) {
      out[8 + i] = p[i];
    }
    return out;
  }

  final chpl = atom('chpl', payload);
  final udta = atom('udta', chpl);
  final mvhdPayload = Uint8List(100);
  mvhdPayload[12] = 0;
  mvhdPayload[13] = 0;
  mvhdPayload[14] = 3;
  mvhdPayload[15] = 0xE8;
  mvhdPayload[16] = 0;
  mvhdPayload[17] = 0;
  mvhdPayload[18] = 0x2A;
  mvhdPayload[19] = 0xF8;
  final mvhd = atom('mvhd', mvhdPayload);
  final moovPayload = Uint8List.fromList([...mvhd, ...udta]);
  return atom('moov', moovPayload);
}

void bench(String label, Uint8List bytes, int iterations) {
  // warmup
  for (int i = 0; i < 10; i++) {
    ChapterParser.parseBytes(bytes, totalDuration: const Duration(hours: 10));
  }
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final r = ChapterParser.parseBytes(bytes,
        totalDuration: const Duration(hours: 10));
    if (r == null) throw StateError('parse failed');
  }
  sw.stop();
  final totalUs = sw.elapsedMicroseconds;
  final perMs = totalUs / iterations / 1000.0;
  final perUs = totalUs / iterations;
  stdout.writeln(
      '$label: ${perMs.toStringAsFixed(3)} ms avg (${perUs.toStringAsFixed(1)} µs) over $iterations iters | bytes=${bytes.length} | chapters=${bytes.length}');
  // more precise per chapter
}

Future<void> benchFile(String label, Uint8List bytes, int iterations) async {
  final tmp = File(
      '${Directory.systemTemp.path}/bench_${label.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '__')}_${DateTime.now().millisecondsSinceEpoch}.m4b');
  await tmp.writeAsBytes(bytes);
  // warmup file
  for (int i = 0; i < 5; i++) {
    await ChapterParser.parseFile(tmp.path,
        totalDuration: const Duration(hours: 10));
  }
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final r = await ChapterParser.parseFile(tmp.path,
        totalDuration: const Duration(hours: 10));
    if (r == null) throw StateError('file parse failed');
  }
  sw.stop();
  final perMs = sw.elapsedMicroseconds / iterations / 1000.0;
  stdout.writeln(
      '$label (file I/O): ${perMs.toStringAsFixed(3)} ms avg over $iterations | file=${bytes.length} bytes');
  await tmp.delete();
}

void main() async {
  stdout.writeln('CrisperPlayer ChapterParser m4b benchmark');
  stdout.writeln(
      'Device: ${Platform.operatingSystem} ${Platform.version.split(' ').first} | Dart ${Platform.version}');
  stdout.writeln('Date: ${DateTime.now().toIso8601String()}');
  stdout.writeln('');

  // Benchmarks with varying chapter counts, fixed header size (~mdat 1KB)
  for (final n in [3, 10, 50, 100, 500, 1000]) {
    final moov = buildMoov(n);
    final mp4 = buildMp4WithMdat(moov, 1024); // small mdat
    bench('parseBytes $n chapters (header ~${mp4.length} B)', mp4,
        n <= 100 ? 5000 : 1000);
  }
  stdout.writeln('');
  for (final n in [3, 10, 50]) {
    for (final mdatKB in [10, 100, 1024]) {
      final moov = buildMoov(n);
      final mp4 = buildMp4WithMdat(moov, mdatKB * 1024);
      bench(
          'parseBytes $n ch, mdat ${mdatKB}KB (total ${(mp4.length / 1024).toStringAsFixed(1)}KB)',
          mp4,
          2000);
    }
  }
  stdout.writeln('');
  // File I/O benchmark
  for (final n in [10, 100]) {
    final moov = buildMoov(n);
    final mp4 = buildMp4WithMdat(moov, 100 * 1024);
    await benchFile('parseFile $n chapters', mp4, 500);
  }

  // Simulate jfk-test.m4a size ~98KB but with our synthetic
  final jfkLike = buildMp4WithMdat(buildMoov(3), 90 * 1024);
  bench('jfk-like 98KB synthetic 3ch', jfkLike, 5000);

  stdout.writeln('');
  stdout.writeln(
      'Notes: O(n) atom scan over header only; mdat skipped via size field, so mdat size does not affect parse time significantly.');
}
