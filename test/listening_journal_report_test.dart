import 'dart:convert';

import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_report.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';

final _day = DateTime.utc(2025, 11, 10).millisecondsSinceEpoch;
final _exported = DateTime.utc(2026, 11, 10, 14, 15, 16);

ListeningJournalEntry _entry({
  int id = 1,
  String bookTitle = 'A title',
  String? chapterTitle = 'A chapter',
  String? reason,
  String kind = 'played',
}) => ListeningJournalEntry(
  id: _id(id),
  bookId: 'book-a',
  kind: kind,
  bookTitle: bookTitle,
  chapterTitle: chapterTitle,
  filePath: '/private/reader/audio/source.mp3',
  startMs: 12345,
  endMs: kind == 'played' ? 67890 : 12345,
  targetFilePath: kind == 'seek' ? '/private/reader/audio/target.mp3' : null,
  targetPositionMs: kind == 'seek' ? 98765 : null,
  startedAtMs: _day + 123,
  endedAtMs: _day + (kind == 'played' ? 40001 : 123),
  utcOffsetMinutes: -330,
  speed: 1.37,
  reason: reason,
);

ListeningJournalReport _report(
  List<ListeningJournalEntry> entries, {
  JournalReportFilters filters = const JournalReportFilters(),
}) => ListeningJournalReport(
  entries: entries,
  exportedAtUtc: _exported,
  filters: filters,
);

String _encode(
  ListeningJournalReport report,
  JournalReportFormat format, {
  bool paths = false,
}) => report.chunks(format: format, includeFilePaths: paths).join();

Map<String, dynamic> _json(
  ListeningJournalReport report, {
  bool paths = false,
}) =>
    jsonDecode(_encode(report, JournalReportFormat.json, paths: paths))
        as Map<String, dynamic>;

/// A small independent CSV reader for verifying escaped records, including
/// embedded commas, doubled quotes, and CR/LF within quoted fields.
List<List<String>> _csv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final character = text[i];
    if (character == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((character == '\r' || character == '\n') && !quoted) {
      row.add(field.toString());
      rows.add(row);
      row = [];
      field = StringBuffer();
      if (character == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
        i++;
      }
    } else {
      field.write(character);
    }
  }
  expect(quoted, isFalse, reason: 'CSV quotes must be balanced');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

void main() {
  test(
    'JSON preserves exact evidence while redacting every path by default',
    () {
      final played = _entry(reason: 'return_trail');
      final seek = _entry(id: 2, kind: 'seek', reason: 'next-chapter');
      final passage = JournalPassageFilter.range(
        bookId: played.bookId,
        filePath: played.filePath,
        startMs: 20000,
        endMs: 30000,
      );
      final report = _report(
        [played, seek],
        filters: JournalReportFilters(
          fromUtcMs: _day,
          beforeUtcMs: _day + 86400000,
          passage: passage,
        ),
      );
      final data = _json(report);
      expect(data['format'], ListeningJournalReport.formatName);
      expect(data['version'], 1);
      expect(data['restorable'], isFalse);
      expect(data['exportedAtUtc'], '2026-11-10T14:15:16.000Z');
      expect(data['recordCount'], 2);
      expect(data['includesFilePaths'], isFalse);
      final scope = data['filters'] as Map;
      expect(scope['bookId'], 'book-a');
      expect(scope['fromUtcMs'], _day);
      expect(scope['beforeUtcMs'], _day + 86400000);
      expect(scope['passage'], {
        'bookId': 'book-a',
        'fileRef': ListeningJournalReport.fileRef('book-a', played.filePath),
        'startMs': 20000,
        'endMs': 30000,
      });
      final rows = data['entries'] as List;
      for (var i = 0; i < rows.length; i++) {
        final expected = [played, seek][i].toJson()
          ..remove('filePath')
          ..remove('targetFilePath');
        for (final key in expected.keys) {
          expect(rows[i][key], expected[key], reason: 'Exact $key is retained');
        }
        expect((rows[i] as Map).containsKey('filePath'), isFalse);
        expect((rows[i] as Map).containsKey('targetFilePath'), isFalse);
      }
      expect(rows.first['startedAtUtc'], '2025-11-10T00:00:00.123Z');
      expect(rows.first['endedAtUtc'], '2025-11-10T00:00:40.001Z');
      expect(rows.first['fileRef'], rows.last['fileRef']);
      expect(rows.last['targetFileRef'], isNot(rows.last['fileRef']));
      expect(rows.last['targetPositionMs'], 98765);
      final serialized = _encode(report, JournalReportFormat.json);
      expect(serialized, isNot(contains('/private/')));
      expect(serialized, isNot(contains('filePath')));
      expect(data.containsKey('books'), isFalse);
      expect(data.containsKey('listeningJournal'), isFalse);
    },
  );

  test(
    'path opt-in includes both source and destination and passage scope',
    () {
      final seek = _entry(kind: 'seek');
      final report = _report(
        [seek],
        filters: JournalReportFilters(
          passage: JournalPassageFilter.point(
            bookId: seek.bookId,
            filePath: seek.filePath,
            positionMs: seek.startMs,
          ),
        ),
      );
      final data = _json(report, paths: true);
      final row = (data['entries'] as List).single as Map;
      expect(data['includesFilePaths'], isTrue);
      expect(row['filePath'], seek.filePath);
      expect(row['targetFilePath'], seek.targetFilePath);
      expect(data['filters']['passage']['filePath'], seek.filePath);
      expect(data['filters']['passage']['positionMs'], seek.startMs);
      final csv = _csv(_encode(report, JournalReportFormat.csv, paths: true));
      expect(csv.last[csv.first.indexOf('filePath')], seek.filePath);
      expect(
        csv.last[csv.first.indexOf('targetFilePath')],
        seek.targetFilePath,
      );
    },
  );

  test(
    'CSV escapes delimiters and newlines while keeping numeric evidence',
    () {
      const title = 'A "quoted", title\r\nwith a second line';
      const chapter = 'Chapter, "two"\ncontinued';
      final report = _report([
        _entry(bookTitle: title, chapterTitle: chapter, kind: 'seek'),
      ]);
      final rows = _csv(_encode(report, JournalReportFormat.csv));
      expect(rows, hasLength(2));
      expect(rows.last, hasLength(rows.first.length));
      final record = Map<String, String>.fromIterables(rows.first, rows.last);
      expect(record['bookTitle'], title);
      expect(record['chapterTitle'], chapter);
      expect(record['id'], _id(1));
      expect(record['startMs'], '12345');
      expect(record['targetPositionMs'], '98765');
      expect(record['startedAtMs'], '${_day + 123}');
      expect(record['utcOffsetMinutes'], '-330');
      expect(record['speed'], '1.37');
      expect(record.containsKey('filePath'), isFalse);
      expect(record.containsKey('targetFilePath'), isFalse);
      expect(record['fileRef'], isNotEmpty);
    },
  );

  test('spreadsheet formulas are inert in every untrusted text column', () {
    for (final value in [
      '=HYPERLINK("https://example.invalid","open")',
      '+1+2',
      '-1+2',
      '@SUM(1,2)',
      '   =1+2',
      '\t=1+2',
      '\r=1+2',
      '\n=1+2',
      '\u0000=1+2',
    ]) {
      final original = _entry(
        bookTitle: value,
        chapterTitle: value,
        reason: value,
      );
      final report = _report([original]);
      final rows = _csv(_encode(report, JournalReportFormat.csv));
      final record = Map<String, String>.fromIterables(rows.first, rows.last);
      for (final column in ['bookTitle', 'chapterTitle', 'reason']) {
        expect(record[column], "'$value", reason: column);
      }
      // JSON is the lossless text form; CSV's apostrophe is intentional.
      expect(_json(report)['entries'][0]['bookTitle'], value);
    }
  });

  test(
    'path opt-in and external book IDs also receive CSV formula defense',
    () {
      final data = _entry(kind: 'seek').toJson()
        ..['bookId'] = '=1+2'
        ..['filePath'] = '@source'
        ..['targetFilePath'] = '  +target';
      final report = _report([ListeningJournalEntry.fromJson(data)]);
      final rows = _csv(_encode(report, JournalReportFormat.csv, paths: true));
      final record = Map<String, String>.fromIterables(rows.first, rows.last);
      expect(record['bookId'], "'=1+2");
      expect(record['filePath'], "'@source");
      expect(record['targetFilePath'], "'  +target");
    },
  );

  test(
    'empty reports are valid and immutable snapshots cannot change later',
    () {
      final entries = <ListeningJournalEntry>[];
      final report = _report(entries);
      entries.add(_entry());
      expect(_json(report)['entries'], isEmpty);
      expect(_json(report)['recordCount'], 0);
      expect(_csv(_encode(report, JournalReportFormat.csv)), hasLength(1));
      expect(() => report.entries.add(_entry()), throwsUnsupportedError);
    },
  );

  test(
    'large reports stream bounded UTF-8 chunks and retain every entry',
    () async {
      final report = _report([
        for (var i = 1; i <= 800; i++)
          _entry(id: i, bookTitle: 'Écouter 日本語 — $i'),
      ]);
      for (final format in JournalReportFormat.values) {
        final chunks = report.chunks(format: format).toList();
        expect(chunks.length, greaterThan(1));
        expect(
          chunks.map((chunk) => chunk.length),
          everyElement(lessThan(68000)),
        );
        final bytes = await report
            .bytes(format: format)
            .expand((part) => part)
            .toList();
        expect(utf8.decode(bytes), chunks.join());
        if (format == JournalReportFormat.json) {
          final data = jsonDecode(utf8.decode(bytes)) as Map;
          expect(data['entries'], hasLength(800));
          expect((data['entries'] as List).last['id'], _id(800));
        } else {
          expect(_csv(utf8.decode(bytes)), hasLength(801));
        }
      }
    },
  );

  test(
    'a filtered snapshot exports over 200 rows and survives later writes',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final journal = ListeningJournalService(db);
      for (final id in ['a', 'b']) {
        await db.upsertBook(
          BooksCompanion.insert(
            id: id,
            title: 'Book $id',
            filePathsJson: '["/$id.mp3"]',
            addedAtMs: 0,
          ),
        );
      }
      Future<void> played(
        int id, {
        String bookId = 'a',
        int? at,
        int end = 10000,
      }) async {
        await journal.recordPlayed(
          id: _id(id),
          bookId: bookId,
          filePath: '/$bookId.mp3',
          startMs: 0,
          endMs: end,
          startedAtMs: at ?? _day + id * 1000,
          endedAtMs: (at ?? _day + id * 1000) + end,
          utcOffsetMinutes: 120,
          speed: 1.37,
        );
      }

      await db.transaction(() async {
        for (var i = 1; i <= 230; i++) {
          await played(i);
        }
        await played(231, bookId: 'b');
        await played(232, at: _day + 900000);
        await journal.recordEvent(
          id: _id(233),
          bookId: 'a',
          kind: 'pause',
          filePath: '/a.mp3',
          positionMs: 5500,
          atMs: _day + 2000,
          utcOffsetMinutes: 120,
        );
      });
      final filters = JournalReportFilters(
        bookId: 'a',
        fromUtcMs: _day,
        beforeUtcMs: _day + 500000,
        passage: JournalPassageFilter.range(
          bookId: 'a',
          filePath: '/a.mp3',
          startMs: 5000,
          endMs: 6000,
        ),
      );
      final snapshot = await journal.snapshot(
        bookId: filters.bookId,
        fromUtcMs: filters.fromUtcMs,
        beforeUtcMs: filters.beforeUtcMs,
        passage: filters.passage,
      );
      final report = _report(snapshot, filters: filters);
      var wroteFirstChunk = false;
      final output = StringBuffer();
      await for (final bytes in report.bytes(
        format: JournalReportFormat.json,
      )) {
        output.write(utf8.decode(bytes));
        if (!wroteFirstChunk) {
          wroteFirstChunk = true;
          await played(1, end: 20000);
          await played(234);
        }
      }
      final rows = (jsonDecode(output.toString()) as Map)['entries'] as List;
      expect(rows, hasLength(230));
      expect(rows.first['id'], _id(230));
      expect(rows.last['id'], _id(1));
      expect(rows.last['endMs'], 10000);
      expect((await journal.getEntry(_id(1)))!.endMs, 20000);
      expect(rows.any((row) => row['id'] == _id(234)), isFalse);
      expect(rows.every((row) => row['kind'] == 'played'), isTrue);
      expect(rows.every((row) => row['bookId'] == 'a'), isTrue);
    },
  );
}
