import 'dart:async';
import 'dart:convert';

import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ListeningJournalService journal;
  final day = DateTime.utc(2025, 11, 10).millisecondsSinceEpoch;
  String uuid(int n) =>
      '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

  Future<String> played(
    int id,
    int start,
    int end, {
    String book = 'a',
    String path = '/shared.mp3',
    int? at,
    int? until,
    String? reason,
  }) => journal.recordPlayed(
    id: uuid(id),
    bookId: book,
    filePath: path,
    startMs: start,
    endMs: end,
    startedAtMs: at ?? day,
    endedAtMs: until ?? day + 10000,
    utcOffsetMinutes: 120,
    reason: reason,
  );

  JournalPassageFilter point(int position, {String path = '/shared.mp3'}) =>
      JournalPassageFilter.point(
        bookId: 'a',
        filePath: path,
        positionMs: position,
      );
  JournalPassageFilter range(int start, int end) => JournalPassageFilter.range(
    bookId: 'a',
    filePath: '/shared.mp3',
    startMs: start,
    endMs: end,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    journal = ListeningJournalService(db);
    for (final id in ['a', 'b']) {
      await db.upsertBook(
        BooksCompanion.insert(
          id: id,
          title: 'Book $id',
          filePathsJson: '["/shared.mp3"]',
          addedAtMs: 1,
        ),
      );
    }
  });
  tearDown(() => db.close());

  test('passage filters validate physical bounds and round-trip exactly', () {
    for (final passage in [point(0), point(8640000000000000), range(0, 1)]) {
      final restored = JournalPassageFilter.fromJson(passage.toJson());
      expect(restored, passage);
      expect(restored.hashCode, passage.hashCode);
    }
    expect(point(1).positionMs, 1);
    expect(range(1, 2).positionMs, isNull);
    expect(point(1), isNot(range(1, 2)));
    for (final create in <JournalPassageFilter Function()>[
      () => point(-1),
      () => point(8640000000000001),
      () => range(2, 2),
      () => range(2, 1),
      () => range(-1, 1),
      () => range(0, 8640000000000001),
      () => point(1, path: ''),
      () => point(1, path: 'x' * 32769),
      () => JournalPassageFilter.point(
        bookId: '',
        filePath: '/shared.mp3',
        positionMs: 1,
      ),
      () => JournalPassageFilter.point(
        bookId: 'x' * 1025,
        filePath: '/shared.mp3',
        positionMs: 1,
      ),
    ]) {
      expect(create, throwsArgumentError);
    }
    final source = <String, Object>{'bookId': 'a', 'filePath': '/shared.mp3'};
    for (final invalid in <Map<String, Object?>>[
      source,
      {...source, 'positionMs': null},
      {...source, 'positionMs': 1.5},
      {...source, 'positionMs': -1},
      {...source, 'startMs': 1},
      {...source, 'startMs': 1, 'endMs': 1},
      {...source, 'positionMs': 1, 'startMs': 1, 'endMs': 2},
      {...source, 'positionMs': 1, 'bookId': 1},
      {...source, 'positionMs': 1, 'filePath': ''},
    ]) {
      expect(
        () => JournalPassageFilter.fromJson(invalid),
        throwsFormatException,
      );
    }
  });

  test(
    'point queries include starts, exclude ends, and retain replay evidence',
    () async {
      await played(1, 0, 1000);
      await played(2, 1000, 2000);
      await played(3, 900, 1100, reason: 'return_trail');
      await played(4, 1000, 2000, book: 'b');
      await played(5, 1000, 2000, path: '/Shared.mp3');
      await journal.recordEvent(
        id: uuid(6),
        bookId: 'a',
        kind: 'pause',
        filePath: '/shared.mp3',
        positionMs: 1000,
        atMs: day,
        utcOffsetMinutes: 120,
      );
      await journal.recordEvent(
        id: uuid(7),
        bookId: 'a',
        kind: 'seek',
        filePath: '/shared.mp3',
        positionMs: 1000,
        targetFilePath: '/shared.mp3',
        targetPositionMs: 1500,
        atMs: day,
        utcOffsetMinutes: 120,
      );
      await journal.recordEvent(
        id: uuid(8),
        bookId: 'a',
        kind: 'seek',
        filePath: '/elsewhere.mp3',
        positionMs: 1000,
        targetFilePath: '/shared.mp3',
        targetPositionMs: 1000,
        atMs: day,
        utcOffsetMinutes: 120,
      );

      final entries = (await journal.page(passage: point(1000))).entries;
      expect(entries.map((entry) => entry.id), [uuid(3), uuid(2)]);
      expect(entries.first.reason, 'return_trail');
      expect((entries.first.startMs, entries.first.endMs), (900, 1100));
      expect(
        (entries.first.startedAtMs, entries.first.endedAtMs),
        (day, day + 10000),
      );
      expect(
        (await journal.page(passage: point(0))).entries.single.id,
        uuid(1),
      );
      expect((await journal.page(passage: point(2000))).entries, isEmpty);
      expect((await journal.page(bookId: 'a')).entries, hasLength(7));
    },
  );

  test(
    'range queries use strict overlap and leave matching intervals whole',
    () async {
      await played(1, 0, 1000);
      await played(2, 2000, 3000);
      await played(3, 999, 1001);
      await played(4, 1999, 2001);
      await played(5, 1000, 2000);
      await played(6, 0, 3000);
      final entries = (await journal.page(passage: range(1000, 2000))).entries;
      expect(entries.map((entry) => entry.id), [
        uuid(6),
        uuid(5),
        uuid(4),
        uuid(3),
      ]);
      expect((entries.first.startMs, entries.first.endMs), (0, 3000));
    },
  );

  test(
    'date and passage filters combine without estimating a time at the point',
    () async {
      await played(1, 0, 30000, at: day - 5000, until: day + 5000);
      await played(2, 0, 30000, at: day - 10000, until: day);
      await played(3, 0, 30000, at: day + 10000, until: day + 20000);
      final entries = (await journal.page(
        passage: point(15000),
        fromUtcMs: day,
        beforeUtcMs: day + 10000,
      )).entries;
      expect(entries.single.id, uuid(1));
      expect((entries.single.startMs, entries.single.endMs), (0, 30000));
      expect(
        (entries.single.startedAtMs, entries.single.endedAtMs),
        (day - 5000, day + 5000),
      );
      await expectLater(
        journal.page(bookId: 'b', passage: point(15000)),
        throwsArgumentError,
      );
    },
  );

  test(
    'queries retain historical evidence even if its source is unavailable',
    () async {
      await played(1, 0, 2000, path: '/missing.mp3');
      final page = await journal.page(
        passage: point(1000, path: '/missing.mp3'),
      );
      expect(page.entries.single.id, uuid(1));
      expect((await journal.page(passage: point(1000))).entries, isEmpty);
      expect(
        (await journal.page(passage: point(8640000000000000))).entries,
        isEmpty,
      );
    },
  );

  test(
    'passage cursors bind source, location, shape and date filters',
    () async {
      for (var id = 1; id <= 5; id++) {
        await played(id, 0, 5000);
      }
      final first = await journal.page(passage: point(1000), limit: 2);
      final second = await journal.page(
        bookId: 'a',
        passage: point(1000),
        limit: 2,
        cursor: first.nextCursor,
      );
      final third = await journal.page(
        passage: point(1000),
        limit: 2,
        cursor: second.nextCursor,
      );
      expect(first.entries.map((entry) => entry.id), [uuid(5), uuid(4)]);
      expect(second.entries.map((entry) => entry.id), [uuid(3), uuid(2)]);
      expect(third.entries.single.id, uuid(1));
      expect(third.nextCursor, isNull);
      for (final changed in <JournalPassageFilter?>[
        null,
        point(1001),
        point(1000, path: '/other.mp3'),
        range(1000, 1001),
        JournalPassageFilter.point(
          bookId: 'b',
          filePath: '/shared.mp3',
          positionMs: 1000,
        ),
      ]) {
        await expectLater(
          journal.page(passage: changed, cursor: first.nextCursor),
          throwsFormatException,
        );
      }
      await expectLater(
        journal.page(
          passage: point(1000),
          fromUtcMs: day,
          cursor: first.nextCursor,
        ),
        throwsFormatException,
      );
      final unfiltered = await journal.page(bookId: 'a', limit: 2);
      await expectLater(
        journal.page(passage: point(1000), cursor: unfiltered.nextCursor),
        throwsFormatException,
      );
      // Existing v1 tokens have no passage field and continue to page normally.
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(unfiltered.nextCursor!)))
              as Map;
      expect(decoded.containsKey('passage'), isFalse);
      final oldNext = await journal.page(
        bookId: 'a',
        limit: 2,
        cursor: unfiltered.nextCursor,
      );
      expect(oldNext.entries.map((entry) => entry.id), [uuid(3), uuid(2)]);
    },
  );

  test(
    'long exact source paths still produce reusable bounded cursors',
    () async {
      final path = '/${'x' * 12000}.mp3';
      await played(1, 0, 2000, path: path);
      await played(2, 0, 2000, path: path);
      final first = await journal.page(
        passage: point(1000, path: path),
        limit: 1,
      );
      expect(first.nextCursor!.length, lessThan(8192));
      final second = await journal.page(
        passage: point(1000, path: path),
        cursor: first.nextCursor,
        limit: 1,
      );
      expect(second.entries.single.id, uuid(1));
    },
  );

  test(
    'snapshot has no page cap, shares filters, and cannot change after capture',
    () async {
      for (var id = 1; id <= 205; id++) {
        await played(id, 0, 2000);
      }
      await played(206, 2000, 3000);
      final snapshot = await journal.snapshot(
        passage: point(1000),
        fromUtcMs: day,
        beforeUtcMs: day + 10000,
      );
      expect(snapshot, hasLength(205));
      expect(snapshot.first.id, uuid(205));
      expect(snapshot.last.id, uuid(1));
      expect(() => snapshot.clear(), throwsUnsupportedError);
      await journal.clear(bookId: 'a');
      expect(snapshot, hasLength(205));
      expect(await journal.snapshot(passage: point(1000)), isEmpty);
      await expectLater(
        journal.snapshot(bookId: 'b', passage: point(1000)),
        throwsArgumentError,
      );
      await expectLater(
        journal.snapshot(fromUtcMs: day, beforeUtcMs: day),
        throwsArgumentError,
      );
    },
  );

  test(
    'watch forwards passage bounds through checkpoint extensions and deletion',
    () async {
      final stream = StreamIterator(journal.watch(passage: point(1000)));
      Future<void> next(int count) async {
        expect(
          await stream.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(stream.current.entries, hasLength(count));
      }

      try {
        await next(0);
        await played(1, 0, 1000);
        await next(0);
        await played(1, 0, 2000, until: day + 20000);
        await next(1);
        expect(stream.current.entries.single.endMs, 2000);
        await journal.clear(bookId: 'a');
        await next(0);
      } finally {
        await stream.cancel();
      }
    },
  );
}
