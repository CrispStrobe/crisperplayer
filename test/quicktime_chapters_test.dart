import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisperplayer/services/audio/chapter_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/quicktime_fixture.dart';

void main() {
  for (final co64 in [false, true]) {
    test(
      'QuickTime ${co64 ? '64' : '32'}-bit offsets, chunk mapping and Unicode',
      () {
        final f = fixture(co64: co64);
        final chapters = ChapterParser.parseBytes(
          Uint8List.fromList([...atom('mdat', f.data), ...f.moov]),
        );
        expect(chapters!.map((c) => c.title), ['Einführung 🎧', '第二章', 'Fée']);
        expect(chapters.map((c) => c.start.inSeconds), [0, 5, 10]);
        expect(chapters.map((c) => c.end.inSeconds), [5, 10, 20]);
      },
    );
  }

  test('honors initial empty edit before chapter media', () {
    final f = fixture(edit: true);
    final chapters = ChapterParser.parseBytes(
      Uint8List.fromList([...atom('mdat', f.data), ...f.moov]),
    );
    expect(chapters!.map((c) => c.start.inSeconds), [2, 7, 12]);
    expect(chapters.last.end.inSeconds, 22);
  });

  test('does not treat an unreferenced text track as chapters', () {
    final f = fixture(reference: false);
    expect(
      ChapterParser.parseBytes(
        Uint8List.fromList([...atom('mdat', f.data), ...f.moov]),
      ),
      isNull,
    );
  });

  test('rejects oversized and inconsistent sample tables', () {
    for (final f in [
      fixture(sampleCount: 10001),
      fixture(sampleCount: 2),
      fixture(truncateTiming: true),
      fixture(base: 0xffffff00),
    ]) {
      expect(
        ChapterParser.parseBytes(
          Uint8List.fromList([...atom('mdat', f.data), ...f.moov]),
        ),
        isNull,
      );
    }
  });

  test('truncated file samples fall back without throwing', () async {
    final directory = await Directory.systemTemp.createTemp('qt-truncated-');
    addTearDown(() => directory.delete(recursive: true));
    final f = fixture(base: 1000000);
    final file = await File('${directory.path}/book.m4b').writeAsBytes(f.moov);
    expect(await ChapterParser.parseFile(file.path), isNull);
  });

  test(
    'file parser seeks over a sparse 4 GB payload and reads co64 text',
    () async {
      final directory = await Directory.systemTemp.createTemp('qt-sparse-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/book.m4b');
      const offset = 0x100000100;
      final f = fixture(co64: true, base: offset + 8);
      final output = await file.open(mode: FileMode.write);
      try {
        await output.writeFrom([
          ...word(1),
          ...ascii.encode('free'),
          ...wide(offset),
        ]);
        await output.setPosition(offset);
        await output.writeFrom([...atom('mdat', f.data), ...f.moov]);
      } finally {
        await output.close();
      }
      final chapters = await ChapterParser.parseFile(
        file.path,
        totalDuration: const Duration(seconds: 25),
      );
      expect(chapters!.map((c) => c.title), ['Einführung 🎧', '第二章', 'Fée']);
      expect(chapters.last.end.inSeconds, 25);
    },
  );

  test('Nero chapter titles decode UTF-8', () {
    final title = utf8.encode('Über den Ozean 🌊');
    final bytes = atom(
      'moov',
      atom(
        'udta',
        atom('chpl', [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          ...wide(0),
          title.length,
          ...title,
        ]),
      ),
    );
    expect(ChapterParser.parseBytes(bytes)!.single.title, 'Über den Ozean 🌊');
  });
}
