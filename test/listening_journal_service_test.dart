import 'dart:async';

import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ListeningJournalService journal;
  final day = DateTime.utc(2025, 11, 10).millisecondsSinceEpoch;
  String uuid(int n) =>
      '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
  Future<String> played({
    int id = 1,
    String book = 'a',
    int start = 0,
    int end = 10000,
    int? at,
    int? until,
    double speed = 1,
    String? reason,
  }) => journal.recordPlayed(
    id: uuid(id),
    bookId: book,
    filePath: '/$book.mp3',
    startMs: start,
    endMs: end,
    startedAtMs: at ?? day,
    endedAtMs: until ?? day + 10000,
    utcOffsetMinutes: 120,
    speed: speed,
    reason: reason,
  );
  Future<String> event(
    int id,
    String kind, {
    String book = 'a',
    int? at,
    int position = 10000,
  }) => journal.recordEvent(
    id: uuid(id),
    bookId: book,
    kind: kind,
    filePath: '/$book.mp3',
    positionMs: position,
    atMs: at ?? day,
    utcOffsetMinutes: 120,
    targetFilePath: kind == 'seek' ? '/$book-next.mp3' : null,
    targetPositionMs: kind == 'seek' ? 50000 : null,
    reason: kind == 'seek' ? 'next-chapter' : null,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    journal = ListeningJournalService(db);
    for (final id in ['a', 'b']) {
      await db.upsertBook(
        BooksCompanion.insert(
          id: id,
          title: 'Original $id',
          filePathsJson: '["/$id.mp3"]',
          addedAtMs: 1,
        ),
      );
    }
  });
  tearDown(() => db.close());

  test(
    'stable checkpoints extend one interval and stale retries cannot shrink it',
    () async {
      for (var i = 1; i <= 100; i++) {
        await played(end: i * 1000, until: day + i * 1000);
      }
      await played(end: 5000, until: day + 5000);
      final page = await journal.page();
      expect(page.entries, hasLength(1));
      expect(page.entries.single.endMs, 100000);
      expect(page.entries.single.startedAtMs, day);
      expect(page.entries.single.endedAtMs, day + 100000);
      expect(page.entries.single.utcOffsetMinutes, 120);
      expect(page.entries.single.bookTitle, 'Original a');
      expect(() => page.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'replays remain separate and Return Trail review retains its reason',
    () async {
      await played();
      await played(
        id: 2,
        at: day + 20000,
        until: day + 30000,
        reason: 'return_trail',
      );
      final entries = (await journal.page()).entries;
      expect(entries, hasLength(2));
      expect(entries.first.reason, 'return_trail');
      expect(entries.last.reason, isNull);
      expect(await db.coverageFor('a'), isEmpty);
      expect(await db.playedPassagesFor('a'), isEmpty);
    },
  );

  test(
    'checkpoint identity cannot change book, file, start, timestamp, speed or reason',
    () async {
      await played();
      for (final operation in [
        () => played(book: 'b'),
        () => played(start: 1000),
        () => played(at: day + 1),
        () => played(speed: 1.5),
        () => played(reason: 'return_trail'),
        () => journal.recordPlayed(
          id: uuid(1),
          bookId: 'a',
          filePath: '/different.mp3',
          startMs: 0,
          endMs: 10000,
          startedAtMs: day,
          endedAtMs: day + 10000,
          utcOffsetMinutes: 120,
        ),
        () => played(end: 20000, until: day + 9000),
      ]) {
        await expectLater(operation(), throwsStateError);
      }
      expect((await journal.getEntry(uuid(1)))!.endMs, 10000);
    },
  );

  test(
    'timestamps, stop positions and seek destinations remain exact',
    () async {
      await event(1, 'pause', position: 12345);
      await event(2, 'stop', at: day + 1000, position: 23456);
      await event(3, 'seek', at: day + 2000, position: 34567);
      await event(3, 'seek', at: day + 2000, position: 34567);
      final seek = (await journal.getEntry(uuid(3)))!;
      expect(seek.startMs, 34567);
      expect(seek.endMs, 34567);
      expect(seek.targetFilePath, '/a-next.mp3');
      expect(seek.targetPositionMs, 50000);
      expect(seek.reason, 'next-chapter');
      expect(seek.elapsedMs, 0);
      expect(seek.toJson()['utcOffsetMinutes'], 120);
      expect((await journal.page()).entries, hasLength(3));
    },
  );

  test(
    'date filters include crossing intervals whole and treat date bounds as half-open',
    () async {
      await played(id: 1, at: day - 5000, until: day + 5000);
      await played(id: 2, at: day - 10000, until: day);
      await event(3, 'pause', at: day);
      await event(4, 'stop', at: day + 86400000);
      await event(5, 'pause', at: day + 1000, book: 'b');
      final entries = (await journal.page(
        bookId: 'a',
        fromUtcMs: day,
        beforeUtcMs: day + 86400000,
      )).entries;
      expect(entries.map((entry) => entry.id), [uuid(3), uuid(1)]);
      expect(entries.last.startedAtMs, day - 5000);
      expect(entries.last.endedAtMs, day + 5000);
    },
  );

  test(
    'keyset pagination is deterministic for tied times and new inserts do not duplicate rows',
    () async {
      for (var i = 1; i <= 5; i++) {
        await event(i, 'pause');
      }
      final first = await journal.page(bookId: 'a', limit: 2);
      expect(first.entries.map((entry) => entry.id), [uuid(5), uuid(4)]);
      await event(6, 'play', at: day + 1000);
      final second = await journal.page(
        bookId: 'a',
        limit: 2,
        cursor: first.nextCursor,
      );
      final third = await journal.page(
        bookId: 'a',
        limit: 2,
        cursor: second.nextCursor,
      );
      expect(second.entries.map((entry) => entry.id), [uuid(3), uuid(2)]);
      expect(third.entries.map((entry) => entry.id), [uuid(1)]);
      expect(third.nextCursor, isNull);
      await expectLater(
        journal.page(bookId: 'b', cursor: first.nextCursor),
        throwsFormatException,
      );
      await expectLater(
        journal.page(bookId: 'a', fromUtcMs: day, cursor: first.nextCursor),
        throwsFormatException,
      );
      await expectLater(
        journal.page(cursor: 'not-a-cursor'),
        throwsFormatException,
      );
    },
  );

  test('journal has no 200-entry pruning or automatic expiry', () async {
    for (var i = 1; i <= 220; i++) {
      await event(i, 'pause', at: day - 366 * 86400000 + i);
    }
    final first = await journal.page(limit: 200);
    final second = await journal.page(limit: 200, cursor: first.nextCursor);
    expect(first.entries, hasLength(200));
    expect(second.entries, hasLength(20));
    expect(await db.select(db.listeningJournal).get(), hasLength(220));
  });

  test(
    'title snapshots survive renames and same-interval checkpoints',
    () async {
      await played();
      await (db.update(db.books)..where((book) => book.id.equals('a'))).write(
        const BooksCompanion(title: Value('Renamed')),
      );
      await played(end: 20000, until: day + 20000);
      await event(2, 'pause');
      expect((await journal.getEntry(uuid(1)))!.bookTitle, 'Original a');
      expect((await journal.getEntry(uuid(2)))!.bookTitle, 'Renamed');
    },
  );

  test(
    'invalid timestamps, offsets, event kinds and incomplete destinations are rejected',
    () async {
      await expectLater(played(until: day - 1), throwsFormatException);
      await expectLater(played(end: 0), throwsFormatException);
      await expectLater(event(1, 'invented'), throwsFormatException);
      await expectLater(
        journal.recordEvent(
          bookId: 'a',
          kind: 'seek',
          filePath: '/a.mp3',
          positionMs: 0,
          atMs: day,
          utcOffsetMinutes: 120,
        ),
        throwsFormatException,
      );
      await expectLater(
        journal.recordEvent(
          bookId: 'a',
          kind: 'stop',
          filePath: '/a.mp3',
          positionMs: 0,
          atMs: day,
          utcOffsetMinutes: 900,
        ),
        throwsFormatException,
      );
      await expectLater(
        journal.recordEvent(
          id: 'not-a-uuid',
          bookId: 'a',
          kind: 'stop',
          filePath: '/a.mp3',
          positionMs: 0,
          atMs: day,
          utcOffsetMinutes: 0,
        ),
        throwsFormatException,
      );
      await expectLater(journal.page(limit: 0), throwsArgumentError);
      await expectLater(journal.page(limit: 201), throwsArgumentError);
      await expectLater(
        journal.page(fromUtcMs: day, beforeUtcMs: day),
        throwsArgumentError,
      );
      expect((await journal.page()).entries, isEmpty);
    },
  );

  test('watch emits updates, checkpoint extensions and clearing', () async {
    final stream = StreamIterator(journal.watch(bookId: 'a'));
    Future<void> next(int count) async {
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(stream.current.entries, hasLength(count));
    }

    try {
      await next(0);
      await played();
      await next(1);
      await played(end: 20000, until: day + 20000);
      await next(1);
      expect(stream.current.entries.single.endMs, 20000);
      await journal.clear(bookId: 'a');
      await next(0);
    } finally {
      await stream.cancel();
    }
  });

  test(
    'book and history deletion erase journals while journal-only clear leaves other history',
    () async {
      await played();
      await played(id: 2, book: 'b');
      await db.insertHistory(
        ListeningHistoryCompanion.insert(
          id: 'history',
          bookId: 'a',
          startedAtMs: day,
        ),
      );
      await journal.clear(bookId: 'a');
      expect(await db.historyFor('a'), hasLength(1));
      expect((await journal.page()).entries.single.bookId, 'b');
      await played();
      await db.clearHistoryForBook('a');
      expect((await journal.page()).entries.single.bookId, 'b');
      await db.clearAllHistory();
      expect((await journal.page()).entries, isEmpty);
      await played();
      await db.deleteBook('a');
      expect((await journal.page()).entries, isEmpty);
    },
  );

  test(
    'backup imports deduplicate UUIDs, preserve origins and accept compatible newer checkpoints',
    () async {
      await played();
      await event(2, 'seek');
      final backup = await db.exportAllJson();
      await played(end: 20000, until: day + 20000);
      await db.importAllJson(backup);
      await db.importAllJson(backup);
      expect((await journal.page()).entries, hasLength(2));
      expect((await journal.getEntry(uuid(1)))!.endMs, 20000);
      final updated = (backup['listeningJournal'] as List)
          .map(
            (row) => row['id'] == uuid(1)
                ? {...row as Map, 'endMs': 30000, 'endedAtMs': day + 30000}
                : row,
          )
          .toList();
      await db.importAllJson({...backup, 'listeningJournal': updated});
      expect((await journal.getEntry(uuid(1)))!.endMs, 30000);
      await db.importAllJson({'version': 6});
      expect((await journal.page()).entries, hasLength(2));
    },
  );

  test(
    'remapping both source and destination keeps UUIDs and an old backup cannot undo it',
    () async {
      await played();
      await event(2, 'seek');
      await played(id: 3, book: 'b');
      final backup = await db.exportAllJson();
      await db.remapJournalFile('a', '/a.mp3', '/managed/a.mp3');
      await db.remapJournalFile('a', '/a-next.mp3', '/managed/next.mp3');
      expect((await journal.getEntry(uuid(1)))!.filePath, '/managed/a.mp3');
      expect(
        (await journal.getEntry(uuid(2)))!.targetFilePath,
        '/managed/next.mp3',
      );
      expect((await journal.getEntry(uuid(3)))!.filePath, '/b.mp3');
      await db.importAllJson(backup);
      expect((await journal.getEntry(uuid(1)))!.filePath, '/managed/a.mp3');
      expect(
        (await journal.getEntry(uuid(2)))!.targetFilePath,
        '/managed/next.mp3',
      );
    },
  );

  test(
    'malformed and orphaned journal restores roll back every library change',
    () async {
      await played();
      final backup = await db.exportAllJson();
      final original = (backup['listeningJournal'] as List).single as Map;
      final changedBooks = (backup['books'] as List)
          .map((row) => {...row as Map, 'title': 'Changed'})
          .toList();
      for (final invalid in [
        {...original, 'startedAtMs': 'yesterday'},
        {...original, 'utcOffsetMinutes': 1000},
        {...original, 'endedAtMs': day - 1},
        {...original, 'bookId': 'missing'},
        {...original, 'id': 'unstable'},
      ]) {
        await expectLater(
          db.importAllJson({
            ...backup,
            'books': changedBooks,
            'listeningJournal': [invalid],
          }),
          throwsFormatException,
        );
        expect((await db.getBook('a'))!.title, 'Original a');
        expect((await journal.page()).entries, hasLength(1));
      }
    },
  );
}
