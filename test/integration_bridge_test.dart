import 'dart:io';
import 'dart:typed_data';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/audio/chapter_parser.dart';
import 'package:crisperplayer/services/audio/mp4_metadata.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late LibraryService library;
  setUp(() {
    root = Directory.systemTemp.createTempSync('crisper_library_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryService(db,
        storageDirectory: () async => Directory('${root.path}/owned'),
        probeDuration: (path) async => path.endsWith('part1.mp3')
            ? const Duration(seconds: 10)
            : path.endsWith('part2.mp3')
                ? const Duration(seconds: 25)
                : const Duration(seconds: 90));
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<File> source(String name) async =>
      File('${root.path}/$name').writeAsBytes([1, 2, 3]);
  test(
      'import owns a durable copy, uses natural order and real per-file durations',
      () async {
    final a = await source('part1.mp3');
    final b = await source('part2.mp3');
    final c = await source('part10.mp3');
    final id = (await library.importFiles([c.path, b.path, a.path]))!;
    final book = (await db.getBook(id))!;
    final tracks = await db.tracksFor(id);
    final chapters = await db.chaptersFor(id);
    expect(tracks.map((t) => t.durationMs), [10000, 25000, 90000]);
    expect(chapters.map((c) => c.startMs), [0, 10000, 35000]);
    expect(chapters.map((c) => c.endMs), [10000, 35000, 125000]);
    expect(book.totalDurationMs, 125000);
    for (final f in [a, b, c]) {
      await f.delete();
    }
    for (final track in tracks) {
      expect(await File(track.filePath).readAsBytes(), [1, 2, 3]);
      expect(track.filePath, contains('/owned/library/$id/'));
    }
    await library.deleteBook(id);
    expect(await Directory('${root.path}/owned/library/$id').exists(), isFalse);
    expect(await db.tracksFor(id), isEmpty);
    expect(await db.chaptersFor(id), isEmpty);
  });
  test('failed import leaves neither partial database rows nor managed files',
      () async {
    final a = await source('a.mp3');
    await expectLater(library.importFiles([a.path, '${root.path}/missing.mp3']),
        throwsA(isA<FileSystemException>()));
    expect(await db.allBooks, isEmpty);
    expect(await Directory('${root.path}/owned').exists(), isFalse);
    expect(await a.exists(), isTrue);
  });
  test('unknown duration stays unknown rather than inventing chapter lengths',
      () async {
    library = LibraryService(db,
        storageDirectory: () async => Directory('${root.path}/owned'),
        probeDuration: (_) async => null);
    final f = await source('unknown.mp3');
    final id = (await library.importFiles([f.path]))!;
    expect((await db.tracksFor(id)).single.durationMs, isNull);
    expect((await db.chaptersFor(id)).single.endMs, 0);
    await library.updateTrackDuration(id, 0, const Duration(seconds: 123));
    expect((await db.getBook(id))!.totalDurationMs, 123000);
    expect((await db.chaptersFor(id)).single.endMs, 123000);
  });
  test('legacy library timing is reconstructed from actual files', () async {
    final f = await source('part1.mp3');
    final g = await source('part2.mp3');
    final data = {
      'version': 1,
      'books': [
        {
          'id': 'legacy',
          'title': 'Legacy',
          'filePathsJson': AppDatabase.encodePaths([f.path, g.path]),
          'addedAtMs': 0
        }
      ]
    };
    await db.importAllJson(data);
    final tracks = await library.ensureTracks((await db.getBook('legacy'))!);
    expect(tracks.map((t) => t.durationMs), [10000, 25000]);
    expect((await db.chaptersFor('legacy')).last.startMs, 10000);
  });
  test(
      'large sparse M4B import scans metadata without reading its audio payload',
      () async {
    final file = File('${root.path}/large.m4b');
    final out = await file.open(mode: FileMode.write);
    const size = 1024 * 1024 * 1024;
    final header = Uint8List(8);
    ByteData.sublistView(header).setUint32(0, size);
    header.setRange(4, 8, 'mdat'.codeUnits);
    await out.writeFrom(header);
    await out.setPosition(size);
    await out.writeFrom([0, 0, 0, 8, ...'moov'.codeUnits]);
    await out.close();
    // Exercise parser directly: copying 1 GB is unrelated to metadata memory use.
    // The source is sparse, so the test uses little disk space.
    expect(await file.length(), size + 8);
    expect(await readMp4Metadata(file), [0, 0, 0, 8, ...'moov'.codeUnits]);
    expect(await ChapterParser.parseFile(file.path), isNull);
  });
}
