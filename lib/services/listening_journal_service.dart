import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../models/listening_journal.dart';
import 'db/app_database.dart';

/// Optional durable history. The playback coordinator owns consent and only
/// supplies observed intervals; enabling this service never backfills dates.
class ListeningJournalService {
  final AppDatabase db;
  ListeningJournalService(this.db);

  Future<String> recordPlayed({
    String? id,
    required String bookId,
    required String filePath,
    required int startMs,
    required int endMs,
    required int startedAtMs,
    required int endedAtMs,
    required int utcOffsetMinutes,
    double speed = 1,
    String? chapterTitle,
    String? reason,
  }) async {
    final entryId = (id ?? const Uuid().v4()).toLowerCase();
    final book = await db.getBook(bookId);
    if (book == null) throw StateError('Journal book is unavailable');
    final entry = ListeningJournalEntry.fromJson(
      ListeningJournalEntry(
        id: entryId,
        bookId: bookId,
        kind: 'played',
        bookTitle: book.title,
        chapterTitle: chapterTitle,
        filePath: filePath,
        startMs: startMs,
        endMs: endMs,
        startedAtMs: startedAtMs,
        endedAtMs: endedAtMs,
        utcOffsetMinutes: utcOffsetMinutes,
        speed: speed,
        reason: reason,
      ).toJson(),
    );
    await db.saveJournalEntry(entry);
    return entryId;
  }

  Future<String> recordEvent({
    String? id,
    required String bookId,
    required String kind,
    required String filePath,
    required int positionMs,
    required int atMs,
    required int utcOffsetMinutes,
    double speed = 1,
    String? targetFilePath,
    int? targetPositionMs,
    String? reason,
    String? chapterTitle,
  }) async {
    if (kind == 'played') {
      throw ArgumentError('Use recordPlayed for audio intervals');
    }
    final entryId = (id ?? const Uuid().v4()).toLowerCase();
    final book = await db.getBook(bookId);
    if (book == null) throw StateError('Journal book is unavailable');
    final entry = ListeningJournalEntry.fromJson(
      ListeningJournalEntry(
        id: entryId,
        bookId: bookId,
        kind: kind,
        bookTitle: book.title,
        chapterTitle: chapterTitle,
        filePath: filePath,
        startMs: positionMs,
        endMs: positionMs,
        targetFilePath: targetFilePath,
        targetPositionMs: targetPositionMs,
        startedAtMs: atMs,
        endedAtMs: atMs,
        utcOffsetMinutes: utcOffsetMinutes,
        speed: speed,
        reason: reason,
      ).toJson(),
    );
    await db.saveJournalEntry(entry);
    return entryId;
  }

  Future<ListeningJournalEntry?> getEntry(String id) async {
    final row = await (db.select(
      db.listeningJournal,
    )..where((entry) => entry.id.equals(id.toLowerCase()))).getSingleOrNull();
    return row == null ? null : ListeningJournalEntry.fromJson(row.toJson());
  }

  Future<void> clear({String? bookId}) async {
    final query = db.delete(db.listeningJournal);
    if (bookId != null) query.where((entry) => entry.bookId.equals(bookId));
    await query.go();
  }

  /// Date bounds are UTC and half-open. Played intervals overlapping the date
  /// range remain whole; returned timestamps are never clipped or reconstructed.
  Future<JournalPage> page({
    String? bookId,
    int? fromUtcMs,
    int? beforeUtcMs,
    int limit = 50,
    String? cursor,
  }) async {
    if (limit < 1 ||
        limit > 200 ||
        (bookId != null && (bookId.isEmpty || bookId.length > 1024)) ||
        (fromUtcMs != null &&
            (fromUtcMs < 0 || fromUtcMs > 8640000000000000)) ||
        (beforeUtcMs != null &&
            (beforeUtcMs < 0 || beforeUtcMs > 8640000000000000)) ||
        (fromUtcMs != null &&
            beforeUtcMs != null &&
            fromUtcMs >= beforeUtcMs)) {
      throw ArgumentError('Invalid journal filters or page size');
    }
    int? lastTime;
    String? lastId;
    if (cursor != null) {
      try {
        if (cursor.length > 8192) throw const FormatException();
        final decoded = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
        );
        if (decoded is! Map ||
            decoded['v'] != 1 ||
            decoded['book'] != bookId ||
            decoded['from'] != fromUtcMs ||
            decoded['before'] != beforeUtcMs ||
            decoded['time'] is! int ||
            (decoded['time'] as int) < 0 ||
            decoded['id'] is! String ||
            (decoded['id'] as String).isEmpty) {
          throw const FormatException();
        }
        lastTime = decoded['time'] as int;
        lastId = decoded['id'] as String;
      } catch (_) {
        throw const FormatException(
          'Invalid journal cursor or changed filters',
        );
      }
    }
    final query = db.select(db.listeningJournal)
      ..where((entry) {
        Expression<bool> filter = const Constant(true);
        if (bookId != null) filter = filter & entry.bookId.equals(bookId);
        if (fromUtcMs != null) {
          filter =
              filter &
              (entry.endedAtMs.isBiggerThanValue(fromUtcMs) |
                  entry.startedAtMs.isBiggerOrEqualValue(fromUtcMs));
        }
        if (beforeUtcMs != null) {
          filter = filter & entry.startedAtMs.isSmallerThanValue(beforeUtcMs);
        }
        if (lastTime != null) {
          filter =
              filter &
              (entry.startedAtMs.isSmallerThanValue(lastTime) |
                  (entry.startedAtMs.equals(lastTime) &
                      entry.id.isSmallerThanValue(lastId!)));
        }
        return filter;
      })
      ..orderBy([
        (entry) => OrderingTerm.desc(entry.startedAtMs),
        (entry) => OrderingTerm.desc(entry.id),
      ])
      ..limit(limit + 1);
    final rows = await query.get();
    final entries = rows
        .take(limit)
        .map((row) => ListeningJournalEntry.fromJson(row.toJson()))
        .toList();
    final hasMore = rows.length > limit;
    final last = hasMore ? entries.last : null;
    return JournalPage(
      entries: entries,
      nextCursor: last == null
          ? null
          : base64Url.encode(
              utf8.encode(
                jsonEncode({
                  'v': 1,
                  'book': bookId,
                  'from': fromUtcMs,
                  'before': beforeUtcMs,
                  'time': last.startedAtMs,
                  'id': last.id,
                }),
              ),
            ),
    );
  }

  Stream<JournalPage> watch({
    String? bookId,
    int? fromUtcMs,
    int? beforeUtcMs,
    int limit = 50,
    String? cursor,
  }) => Stream<JournalPage>.multi((output) {
    var cancelled = false;
    Future<void> pending = Future.value();
    void refresh() {
      pending = pending.then((_) async {
        if (cancelled) return;
        try {
          final snapshot = await page(
            bookId: bookId,
            fromUtcMs: fromUtcMs,
            beforeUtcMs: beforeUtcMs,
            limit: limit,
            cursor: cursor,
          );
          if (!cancelled) output.add(snapshot);
        } catch (error, stack) {
          if (!cancelled) output.addError(error, stack);
        }
      });
    }

    final subscription = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([db.listeningJournal, db.books]),
        )
        .listen(
          (_) => refresh(),
          onError: output.addError,
          onDone: () {
            cancelled = true;
            output.close();
          },
        );
    output.onCancel = () async {
      cancelled = true;
      await subscription.cancel();
    };
    refresh();
  });
}
