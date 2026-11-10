import 'dart:async';

import 'package:crisperplayer/models/listening_coverage.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_coverage_service.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ListeningCoverageService service;
  late ReturnTrailService recorder;

  Future<void> book(String id, List<int?> durations) async {
    final paths = [for (var i = 0; i < durations.length; i++) '/$id/$i.mp3'];
    await db.upsertBook(
      BooksCompanion.insert(
        id: id,
        title: id,
        filePathsJson: AppDatabase.encodePaths(paths),
        addedAtMs: 1,
      ),
    );
    await db.replaceTracks(id, [
      for (var i = 0; i < durations.length; i++)
        BookTracksCompanion.insert(
          bookId: id,
          trackIndex: i,
          filePath: paths[i],
          durationMs: Value(durations[i]),
        ),
    ]);
  }

  Future<void> record(
    int start,
    int end, {
    int time = 1,
    String id = 'a',
    int track = 0,
  }) => recorder.record(
    bookId: id,
    filePath: '/$id/$track.mp3',
    startMs: start,
    endMs: end,
    heardAtMs: time,
  );

  List<(int, int)> intervals(List<CoverageInterval> ranges) =>
      ranges.map((range) => (range.startMs, range.endMs)).toList();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ListeningCoverageService(db);
    recorder = ReturnTrailService(db);
    await book('a', [1000000]);
  });
  tearDown(() => db.close());

  test(
    'durable union counts revisits once and bridges only actually played gaps',
    () async {
      await record(0, 10000);
      await record(20000, 30000, time: 20000);
      await record(5000, 9000, time: 40000);
      var coverage = await service.forBook('a');
      expect(coverage.playedMs, 20000);
      expect(intervals(coverage.tracks.single.played), [
        (0, 10000),
        (20000, 30000),
      ]);
      expect(intervals(coverage.tracks.single.gaps), [
        (10000, 20000),
        (30000, 1000000),
      ]);
      await record(10000, 20000, time: 60000);
      coverage = await service.forBook('a');
      expect(coverage.playedMs, 30000);
      expect(intervals(coverage.tracks.single.played), [(0, 30000)]);
      expect(await db.coverageFor('a'), hasLength(1));
    },
  );

  test(
    '200 recent-passage pruning never removes cumulative coverage or tiny confirmed ranges',
    () async {
      for (var i = 0; i < 210; i++) {
        await record(i * 2000, i * 2000 + 500, time: i * 11000);
      }
      expect(await db.playedPassagesFor('a'), hasLength(200));
      expect(await db.coverageFor('a'), hasLength(210));
      final coverage = await service.forBook('a');
      expect(coverage.playedMs, 105000);
      expect(coverage.tracks.single.played.first.startMs, 0);
      expect(coverage.tracks.single.played.last.endMs, 418500);
    },
  );

  test(
    'recency and cumulative writes roll back together when either write fails',
    () async {
      await db.customStatement('''
      CREATE TRIGGER reject_test_passage BEFORE INSERT ON played_passages
      WHEN NEW.start_ms = 12345
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
      await expectLater(record(12345, 20000), throwsA(anything));
      expect(await db.coverageFor('a'), isEmpty);
      expect(await db.playedPassagesFor('a'), isEmpty);
    },
  );

  test(
    'resume, finished flags and session endpoints do not invent coverage',
    () async {
      await (db.update(db.books)..where((b) => b.id.equals('a'))).write(
        const BooksCompanion(
          lastPositionMs: Value(900000),
          totalProgress: Value(1),
          isFinished: Value(true),
        ),
      );
      await db.insertHistory(
        ListeningHistoryCompanion.insert(
          id: 'old',
          bookId: 'a',
          startedAtMs: 1,
          startMs: const Value(0),
          endMs: const Value(900000),
        ),
      );
      final coverage = await service.forBook('a');
      expect(coverage.playedMs, 0);
      expect(coverage.fraction, 0);
      expect(intervals(coverage.tracks.single.gaps), [(0, 1000000)]);
    },
  );

  test('book percentages are duration-weighted across tracks', () async {
    await book('a', [20000, 80000]);
    await record(0, 10000);
    await record(20000, 40000, track: 1);
    final coverage = await service.forBook('a');
    expect(coverage.durationMs, 100000);
    expect(coverage.playedMs, 30000);
    expect(coverage.fraction, .3);
    expect(coverage.tracks.map((track) => track.fraction), [.5, .25]);
    expect(coverage.toJson()['playedMs'], 30000);
    expect(coverage.toJson()['tracks'], hasLength(2));
  });

  test(
    'unknown durations expose only observed extent with no fabricated gaps or percent',
    () async {
      await book('a', [20000, null]);
      await record(0, 5000);
      await record(5000, 12000, track: 1);
      final coverage = await service.forBook('a');
      expect(coverage.playedMs, 12000);
      expect(coverage.durationMs, isNull);
      expect(coverage.fraction, isNull);
      expect(coverage.tracks.last.durationMs, isNull);
      expect(coverage.tracks.last.fraction, isNull);
      expect(coverage.tracks.last.gaps, isEmpty);
      expect(coverage.tracks.last.timelineExtentMs, 12000);
      expect(coverage.tracks.first.timelineExtentMs, 20000);
    },
  );

  test(
    'known durations clamp views and removed tracks are omitted without corrupting stored evidence',
    () async {
      await book('a', [20000]);
      await record(10000, 50000);
      await record(0, 90000, track: 9);
      var coverage = await service.forBook('a');
      expect(coverage.playedMs, 10000);
      expect(coverage.tracks, hasLength(1));
      expect(intervals(coverage.tracks.single.played), [(10000, 20000)]);
      expect((await db.coverageFor('a')).first.endMs, 50000);
      await (db.update(db.bookTracks)..where((t) => t.bookId.equals('a')))
          .write(const BookTracksCompanion(durationMs: Value(60000)));
      coverage = await service.forBook('a');
      expect(coverage.playedMs, 40000);
      expect(intervals(coverage.tracks.single.gaps), [
        (0, 10000),
        (50000, 60000),
      ]);
    },
  );

  test(
    'missing books and zero-duration tracks have finite empty coverage',
    () async {
      final missing = await service.forBook('missing');
      expect(missing.tracks, isEmpty);
      expect(missing.durationMs, isNull);
      expect(missing.fraction, isNull);
      await book('zero', [0]);
      final zero = await service.forBook('zero');
      expect(zero.durationMs, 0);
      expect(zero.fraction, 0);
      expect(zero.tracks.single.gaps, isEmpty);
    },
  );

  test(
    'watch emits range, duration, chapter and deletion changes without changing its book query result',
    () async {
      final values = StreamIterator(service.watch('a'));
      Future<BookListeningCoverage> next() async {
        expect(
          await values.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        return values.current;
      }

      try {
        expect((await next()).playedMs, 0);
        await record(10000, 30000);
        expect((await next()).playedMs, 20000);
        await (db.update(db.bookTracks)..where((t) => t.bookId.equals('a')))
            .write(const BookTracksCompanion(durationMs: Value(40000)));
        expect((await next()).fraction, .5);
        await db.replaceChapters('a', [
          ChaptersCompanion.insert(
            id: 'chapter',
            bookId: 'a',
            title: 'A mapped chapter',
            startMs: 0,
            endMs: 40000,
            filePath: const Value('/a/0.mp3'),
          ),
        ]);
        expect((await next()).tracks.single.title, 'A mapped chapter');
        await db.clearAllHistory();
        expect((await next()).playedMs, 0);
        await db.deleteBook('a');
        expect((await next()).tracks, isEmpty);
      } finally {
        await values.cancel();
      }
    },
  );

  test(
    'history clearing and per-book forgetting remove cumulative and recent records together',
    () async {
      await book('b', [100000]);
      await record(0, 10000);
      await record(0, 10000, id: 'b');
      await recorder.clearForBook('a');
      expect(await db.coverageFor('a'), isEmpty);
      expect(await db.playedPassagesFor('a'), isEmpty);
      expect(await db.coverageFor('b'), hasLength(1));
      await record(20000, 30000);
      await db.clearHistoryForBook('a');
      expect(await db.coverageFor('a'), isEmpty);
      await db.clearAllHistory();
      expect(await db.coverageFor('b'), isEmpty);
      await record(0, 10000);
      await db.deleteBook('a');
      expect(await db.coverageFor('a'), isEmpty);
    },
  );

  test(
    'backup merge preserves long-term coverage and ignores local row IDs',
    () async {
      for (var i = 0; i < 210; i++) {
        await record(i * 2000, i * 2000 + 500, time: i * 11000);
      }
      final backup = await db.exportAllJson();
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await target.upsertBook(
          BooksCompanion.insert(
            id: 'b',
            title: 'b',
            filePathsJson: '["/b.mp3"]',
            addedAtMs: 1,
          ),
        );
        await target.mergeCoverageRange(
          bookId: 'b',
          filePath: '/b.mp3',
          startMs: 0,
          endMs: 10000,
        );
        await target.importAllJson(backup);
        await target.importAllJson(backup);
        expect(await target.coverageFor('a'), hasLength(210));
        expect(await target.playedPassagesFor('a'), hasLength(200));
        expect(await target.coverageFor('b'), hasLength(1));
        expect(
          (await ListeningCoverageService(target).forBook('a')).playedMs,
          105000,
        );
        await target.importAllJson({'version': 4});
        expect(await target.coverageFor('a'), hasLength(210));
      } finally {
        await target.close();
      }
    },
  );

  test(
    'version-five backups seed only their retained ranges into cumulative coverage',
    () async {
      await db.importAllJson({
        'version': 5,
        'playedPassages': [
          {
            'bookId': 'a',
            'filePath': '/a/0.mp3',
            'startMs': 10000,
            'endMs': 20000,
            'heardAtMs': 1,
          },
          {
            'bookId': 'a',
            'filePath': '/a/0.mp3',
            'startMs': 15000,
            'endMs': 30000,
            'heardAtMs': 2,
          },
        ],
      });
      expect(intervals((await service.forBook('a')).tracks.single.played), [
        (10000, 30000),
      ]);
    },
  );

  test(
    'malformed or orphaned cumulative ranges roll back the entire restore',
    () async {
      await record(0, 10000);
      final backup = await db.exportAllJson();
      final original = (backup['playbackCoverage'] as List).single as Map;
      final changedBooks = (backup['books'] as List)
          .map((book) => {...book as Map, 'title': 'Changed'})
          .toList();
      for (final invalid in [
        {...original, 'startMs': -1},
        {...original, 'endMs': 0},
        {...original, 'endMs': 'later'},
        {...original, 'bookId': 'missing'},
      ]) {
        await expectLater(
          db.importAllJson({
            ...backup,
            'books': changedBooks,
            'playbackCoverage': [invalid],
          }),
          throwsFormatException,
        );
        expect((await db.getBook('a'))!.title, 'a');
        expect((await service.forBook('a')).playedMs, 10000);
      }
    },
  );

  test(
    'remapping a file merges destination coverage instead of duplicating it',
    () async {
      await record(0, 10000);
      await db.mergeCoverageRange(
        bookId: 'a',
        filePath: '/new.mp3',
        startMs: 5000,
        endMs: 20000,
      );
      await db.remapCoverageFile('a', '/a/0.mp3', '/new.mp3');
      final rows = await db.coverageFor('a');
      expect(rows, hasLength(1));
      expect(
        (rows.single.filePath, rows.single.startMs, rows.single.endMs),
        ('/new.mp3', 0, 20000),
      );
    },
  );
}
