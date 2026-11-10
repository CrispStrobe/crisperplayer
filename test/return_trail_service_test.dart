import 'package:crisperplayer/models/return_trail.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ReturnTrailService service;

  Future<void> book(String id, {List<int?> durations = const [900000]}) async {
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
      for (var i = 0; i < paths.length; i++)
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
    int end,
    int time, {
    String path = '/a/0.mp3',
  }) => service.record(
    bookId: 'a',
    filePath: path,
    startMs: start,
    endMs: end,
    heardAtMs: time,
  );

  TrailAnchor anchor({int position = 800000, String path = '/a/0.mp3'}) =>
      TrailAnchor(bookId: 'a', filePath: path, positionMs: position);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ReturnTrailService(db);
    await book('a');
  });
  tearDown(() => db.close());

  test(
    'continuous ticks merge, but seeks, long gaps and clock reversal do not',
    () async {
      await record(10000, 12000, 1000);
      await record(12000, 14000, 2000);
      await record(11000, 15000, 3000);
      var rows = await db.playedPassagesFor('a');
      expect(rows, hasLength(1));
      expect((rows.single.startMs, rows.single.endMs), (10000, 15000));
      await record(60000, 62000, 4000);
      await record(62000, 64000, 15000);
      await record(64000, 66000, 14000);
      rows = await db.playedPassagesFor('a');
      expect(rows, hasLength(4));
      expect(rows.any((p) => p.startMs <= 15000 && p.endMs >= 60000), isFalse);
    },
  );

  test(
    'record rejects invalid ranges and retains only the newest 200 per book',
    () async {
      for (final range in [(-1, 10), (10, 10), (20, 10)]) {
        await expectLater(
          record(range.$1, range.$2, 1000),
          throwsArgumentError,
        );
      }
      await expectLater(record(0, 10, -1), throwsArgumentError);
      for (var i = 0; i < 205; i++) {
        await record(i * 1000, i * 1000 + 500, i * 11000);
      }
      final rows = await db.select(db.playedPassages).get();
      expect(rows, hasLength(200));
      expect(rows.map((p) => p.startMs).reduce((a, b) => a < b ? a : b), 5000);
      expect((await db.playedPassagesFor('a')).first.startMs, 204000);
    },
  );

  test(
    'ordinary history is not treated as proof of uninterrupted playback',
    () async {
      await db.insertHistory(
        ListeningHistoryCompanion.insert(
          id: 'old',
          bookId: 'a',
          startedAtMs: 1,
          startMs: const Value(0),
          endMs: const Value(800000),
          listenedMs: const Value(1000),
        ),
      );
      final plan = await service.plan(anchor: anchor());
      expect(plan.clips, isEmpty);
      expect(plan.mediaDuration, Duration.zero);
    },
  );

  test(
    'one passage uses its tail and converts wall time using playback speed',
    () async {
      await record(0, 240000, 1);
      final plan = await service.plan(anchor: anchor(), speed: 1.5);
      expect(plan.clips, hasLength(1));
      expect(
        (plan.clips.single.startMs, plan.clips.single.endMs),
        (150000, 240000),
      );
      expect(plan.mediaDuration, const Duration(seconds: 90));
      expect(plan.estimatedDuration, const Duration(seconds: 60));
      expect(plan.clips.single.title, 'Part 1');
      expect(plan.clips.single.reason, 'Last played passage');
      expect(plan.toJson()['anchor'], anchor().toJson());
      expect(() => plan.clips.clear(), throwsUnsupportedError);
    },
  );

  test(
    'three recent excerpts favor the latest and replay in listening order',
    () async {
      await record(0, 120000, 1);
      await record(300000, 420000, 20000);
      await record(600000, 720000, 40000);
      final plan = await service.plan(anchor: anchor());
      expect(plan.clips.map((clip) => (clip.startMs, clip.endMs)), [
        (105000, 120000),
        (405000, 420000),
        (690000, 720000),
      ]);
      expect(plan.mediaDuration, const Duration(minutes: 1));
      expect(plan.clips.last.reason, 'Last played passage');
      final repeated = await service.plan(anchor: anchor());
      expect(repeated.toJson(), plan.toJson());
    },
  );

  test('overlapping revisits never replay the same audio twice', () async {
    await record(0, 100000, 1);
    await record(50000, 120000, 20000);
    final plan = await service.plan(anchor: anchor());
    expect(plan.clips, hasLength(2));
    expect(plan.clips[0].endMs, lessThanOrEqualTo(plan.clips[1].startMs));
    expect((plan.clips[0].startMs, plan.clips[0].endMs), (20000, 50000));
    expect((plan.clips[1].startMs, plan.clips[1].endMs), (90000, 120000));
  });

  test(
    'short passages redistribute budget without adding unheard time',
    () async {
      await record(0, 120000, 1);
      await record(300000, 310000, 20000);
      await record(600000, 605000, 40000);
      final plan = await service.plan(anchor: anchor());
      expect(plan.mediaDuration, const Duration(minutes: 1));
      expect(plan.clips.map((p) => p.duration.inSeconds), [45, 10, 5]);
    },
  );

  test(
    'physical anchor excludes later tracks and clamps known file duration',
    () async {
      await book('a', durations: [20000, 30000, 40000]);
      await record(0, 40000, 1);
      await record(0, 30000, 20000, path: '/a/1.mp3');
      await record(0, 40000, 40000, path: '/a/2.mp3');
      await record(0, 40000, 60000, path: '/removed.mp3');
      final plan = await service.plan(
        anchor: anchor(path: '/a/1.mp3', position: 15000),
      );
      expect(plan.clips.map((c) => c.filePath), ['/a/0.mp3', '/a/1.mp3']);
      expect(plan.clips.first.endMs, 20000);
      expect(plan.clips.last.endMs, 15000);
      expect(plan.mediaDuration, const Duration(seconds: 35));
    },
  );

  test(
    'unknown preceding duration never prevents safe file-local planning',
    () async {
      await book('a', durations: [null, 100000]);
      await record(0, 50000, 1);
      await record(0, 80000, 20000, path: '/a/1.mp3');
      final plan = await service.plan(
        anchor: anchor(path: '/a/1.mp3', position: 30000),
      );
      expect(plan.clips, hasLength(2));
      expect(plan.clips.last.endMs, 30000);
      expect(plan.clips.last.title, 'Part 2');
    },
  );

  test('chapter titles are resolved at the physical excerpt start', () async {
    await book('a', durations: [60000, 120000]);
    await db.replaceChapters('a', [
      ChaptersCompanion.insert(
        id: 'chapter',
        bookId: 'a',
        title: 'The winter road',
        startMs: 60000,
        endMs: 180000,
        filePath: const Value('/a/1.mp3'),
        trackIndex: const Value(1),
      ),
    ]);
    await record(0, 80000, 1, path: '/a/1.mp3');
    final plan = await service.plan(
      anchor: anchor(path: '/a/1.mp3', position: 90000),
    );
    expect(plan.clips.single.title, 'The winter road');
  });

  test(
    'missing anchors and beginning-of-book anchors produce an empty plan',
    () async {
      await record(0, 50000, 1);
      expect(
        (await service.plan(anchor: anchor(path: '/missing.mp3'))).clips,
        isEmpty,
      );
      expect((await service.plan(anchor: anchor(position: 0))).clips, isEmpty);
    },
  );

  test(
    'tiny ranges are omitted and even the smallest budget avoids tiny clips',
    () async {
      await record(0, 1999, 1);
      expect((await service.plan(anchor: anchor())).clips, isEmpty);
      await record(10000, 30000, 20000);
      await record(40000, 60000, 40000);
      await record(70000, 90000, 60000);
      final plan = await service.plan(
        anchor: anchor(),
        budget: const Duration(seconds: 15),
        speed: 0.5,
      );
      expect(plan.clips, hasLength(3));
      expect(
        plan.clips.every((clip) => clip.duration.inMilliseconds >= 2000),
        isTrue,
      );
      expect(
        plan.estimatedDuration,
        lessThanOrEqualTo(const Duration(seconds: 15)),
      );
    },
  );

  test('budgets and speed are validated before planning', () async {
    for (final seconds in [14, 301]) {
      await expectLater(
        service.plan(
          anchor: anchor(),
          budget: Duration(seconds: seconds),
        ),
        throwsArgumentError,
      );
    }
    for (final speed in [0.0, 0.49, 3.01, double.nan, double.infinity]) {
      await expectLater(
        service.plan(anchor: anchor(), speed: speed),
        throwsArgumentError,
      );
    }
    await expectLater(
      service.plan(anchor: anchor(position: -1)),
      throwsArgumentError,
    );
  });

  test(
    'clearing history and deleting books erase their played passages',
    () async {
      await book('b');
      await record(0, 10000, 1);
      await service.record(
        bookId: 'b',
        filePath: '/b/0.mp3',
        startMs: 0,
        endMs: 10000,
        heardAtMs: 1,
      );
      await db.clearHistoryForBook('a');
      expect(await db.playedPassagesFor('a'), isEmpty);
      expect(await db.playedPassagesFor('b'), hasLength(1));
      await db.clearAllHistory();
      expect(await db.select(db.playedPassages).get(), isEmpty);
      await record(0, 10000, 2);
      await db.deleteBook('a');
      expect(await db.select(db.playedPassages).get(), isEmpty);
    },
  );

  test(
    'backup merge is idempotent and local integer IDs cannot overwrite another book',
    () async {
      await record(0, 10000, 1);
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
        await ReturnTrailService(target).record(
          bookId: 'b',
          filePath: '/b.mp3',
          startMs: 20000,
          endMs: 30000,
          heardAtMs: 2,
        );
        await target.importAllJson(backup);
        await target.importAllJson(backup);
        expect(await target.playedPassagesFor('a'), hasLength(1));
        expect((await target.playedPassagesFor('b')).single.startMs, 20000);
        expect(await target.select(target.playedPassages).get(), hasLength(2));
        await target.importAllJson({'version': 4});
        expect(await target.select(target.playedPassages).get(), hasLength(2));
      } finally {
        await target.close();
      }
    },
  );

  test(
    'invalid passage backup and missing parent roll back the whole import',
    () async {
      await record(0, 10000, 1);
      final backup = await db.exportAllJson();
      final changedBooks = (backup['books'] as List)
          .map((b) => {...b as Map, 'title': 'Changed'})
          .toList();
      final valid = (backup['playedPassages'] as List).single as Map;
      for (final invalid in [
        {...valid, 'startMs': -1},
        {...valid, 'endMs': 0},
        {...valid, 'heardAtMs': 'yesterday'},
        {...valid, 'bookId': 'missing'},
      ]) {
        await expectLater(
          db.importAllJson({
            ...backup,
            'books': changedBooks,
            'playedPassages': [invalid],
          }),
          throwsFormatException,
        );
        expect((await db.getBook('a'))!.title, 'a');
        expect(await db.playedPassagesFor('a'), hasLength(1));
      }
    },
  );

  test(
    'import also enforces the per-book 200 passage retention limit',
    () async {
      await db.importAllJson({
        'version': 5,
        'playedPassages': [
          for (var i = 0; i < 210; i++)
            {
              'id': i,
              'bookId': 'a',
              'filePath': '/a/0.mp3',
              'startMs': i * 1000,
              'endMs': i * 1000 + 500,
              'heardAtMs': i,
            },
        ],
      });
      expect(await db.select(db.playedPassages).get(), hasLength(200));
      expect((await db.playedPassagesFor('a')).last.heardAtMs, 10);
    },
  );
}
