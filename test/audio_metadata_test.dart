import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisperplayer/services/audio/audio_metadata.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/quicktime_fixture.dart' show atom, word;

List<int> syncSafe(int n) => [
  n >> 21 & 127,
  n >> 14 & 127,
  n >> 7 & 127,
  n & 127,
];
Uint8List tag(int version, List<int> frames, {int flags = 0}) =>
    Uint8List.fromList([
      ...ascii.encode('ID3'),
      version,
      0,
      flags,
      ...syncSafe(frames.length),
      ...frames,
    ]);
List<int> frame(int version, String name, List<int> data, {int flags = 0}) => [
  ...ascii.encode(name),
  ...(version == 4 ? syncSafe(data.length) : word(data.length)),
  0,
  flags,
  ...data,
];
final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);

void main() {
  for (final v in [3, 4]) {
    test('ID3v2.$v: Unicode album/author and front cover', () {
      final bytes = tag(v, [
        ...frame(v, 'TIT2', [3, ...utf8.encode('Track 1')]),
        ...frame(v, 'TALB', [3, ...utf8.encode('Über den Ozean 🎧')]),
        ...frame(v, 'TPE1', [1, 255, 254, 0xe9, 0, 0x20, 0, 0, 0x4e]),
        ...frame(v, 'APIC', [
          3,
          ...ascii.encode('image/png'),
          0,
          3,
          ...utf8.encode('Cover'),
          0,
          ...png,
        ]),
      ]);
      final metadata = AudioMetadata.id3(bytes);
      expect(metadata.title, 'Über den Ozean 🎧');
      expect(metadata.author, 'é 一');
      expect(metadata.artwork, png);
    });
  }
  test('v2.4 syncsafe frame sizes and data length indicator', () {
    final name = 'Long title ${List.filled(200, 'a').join()}';
    final bytes = tag(
      4,
      frame(4, 'TIT2', [
        ...syncSafe(utf8.encode(name).length + 1),
        3,
        ...utf8.encode(name),
      ], flags: 1),
    );
    expect(AudioMetadata.id3(bytes).title, name);
  });
  test('v2.3 tag unsynchronisation restores image bytes', () {
    final jpeg = [255, 216, 255, 0xe0, 1, 2];
    final decoded = frame(3, 'APIC', [
      0,
      ...ascii.encode('image/jpeg'),
      0,
      3,
      0,
      ...jpeg,
    ]);
    final encoded = [
      for (final b in decoded) ...[b, if (b == 255) 0],
    ];
    expect(AudioMetadata.id3(tag(3, encoded, flags: 128)).artwork, jpeg);
  });
  test(
    'MP4 album and artist metadata are decoded without treating leaves as atoms',
    () {
      Uint8List field(String key, String text) => atom(
        key,
        atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(text)]),
      );
      final bytes = atom(
        'moov',
        atom(
          'udta',
          atom('meta', [
            0,
            0,
            0,
            0,
            ...atom('ilst', [
              ...field('©nam', 'Part 1'),
              ...field('©alb', 'The Book'),
              ...field('©ART', '作者'),
            ]),
          ]),
        ),
      );
      expect(AudioMetadata.mp4(bytes).title, 'The Book');
      expect(AudioMetadata.mp4(bytes).author, '作者');
    },
  );
  test('truncated/oversized tags fail closed without crashing', () {
    final bytes = tag(4, frame(4, 'TIT2', [3, ...utf8.encode('Safe')]));
    for (var i = 0; i < bytes.length; i++) {
      expect(AudioMetadata.id3(bytes.sublist(0, i)).title, isNull);
    }
    final bad = Uint8List.fromList([
      ...ascii.encode('ID3'),
      4,
      0,
      0,
      ...syncSafe(17 * 1024 * 1024),
    ]);
    expect(AudioMetadata.id3(bad).title, isNull);
  });
  test(
    'import uses tags/artwork, explicit details take priority, edits preserve source and progress',
    () async {
      final root = await Directory.systemTemp.createTemp('metadata-import-');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      final source = await File('${root.path}/track01.mp3').writeAsBytes(
        tag(4, [
          ...frame(4, 'TALB', [3, ...utf8.encode('Tagged book')]),
          ...frame(4, 'TPE1', [3, ...utf8.encode('Tagged author')]),
          ...frame(4, 'APIC', [
            0,
            ...ascii.encode('image/png'),
            0,
            3,
            0,
            ...png,
          ]),
        ]),
      );
      final library = LibraryService(
        db,
        storageDirectory: () async => root,
        probeDuration: (_) async => const Duration(minutes: 10),
      );
      final id = (await library.importFiles([source.path]))!;
      var book = (await db.getBook(id))!;
      expect(book.title, 'Tagged book');
      expect(book.author, 'Tagged author');
      expect(await File(book.coverPath).readAsBytes(), png);
      final owned = AppDatabase.decodePaths(book.filePathsJson).single;
      await library.updateProgress(
        id,
        owned,
        const Duration(seconds: 42),
        const Duration(seconds: 42),
        const Duration(minutes: 10),
      );
      await library.editBook(id, {
        'title': 'Edited',
        'series': 'Saga',
        'seriesOrder': 1.5,
        'collection': 'Favorites',
      });
      book = (await db.getBook(id))!;
      expect(book.lastPositionMs, 42000);
      expect(book.seriesOrder, 1.5);
      expect(await source.exists(), isTrue);
      final explicit = (await library.importFiles(
        [source.path],
        title: 'Custom',
        author: 'Chosen',
      ))!;
      expect((await db.getBook(explicit))!.title, 'Custom');
      expect((await db.getBook(explicit))!.author, 'Chosen');
      await expectLater(
        library.editBook(id, {'title': ' '}),
        throwsFormatException,
      );
      await expectLater(
        library.editBook(id, {'coverPath': '/outside'}),
        throwsFormatException,
      );
      expect(await library.refreshMetadata(id), isTrue);
      expect((await db.getBook(id))!.title, 'Tagged book');
      expect((await db.getBook(id))!.lastPositionMs, 42000);
    },
  );
}
