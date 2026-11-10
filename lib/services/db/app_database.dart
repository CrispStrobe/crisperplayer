import 'dart:convert';
import 'dart:math' as math;
import '../../models/book_preferences.dart';
import '../../models/listening_journal.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get series => text().withDefault(const Constant(''))();
  RealColumn get seriesOrder => real().nullable()();
  TextColumn get collection => text().withDefault(const Constant(''))();
  TextColumn get playbackPreferencesJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get author => text().withDefault(const Constant('Unknown'))();
  TextColumn get coverPath => text().withDefault(const Constant(''))();
  TextColumn get filePathsJson => text()();
  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();
  IntColumn get addedAtMs => integer()();
  IntColumn get lastPlayedAtMs => integer().nullable()();
  TextColumn get lastPositionFilePath => text().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  RealColumn get totalProgress => real().withDefault(const Constant(0))();
  BoolColumn get finishedOverride => boolean().nullable()();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Physical files in playback order. Unknown durations stay null until probed.
class BookTracks extends Table {
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  IntColumn get trackIndex => integer()();
  TextColumn get filePath => text()();
  IntColumn get durationMs => integer().nullable()();
  @override
  Set<Column> get primaryKey => {bookId, trackIndex};
}

class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
  TextColumn get title => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get filePath => text().nullable()();
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('manual'))();
  TextColumn get filePath => text()();
  IntColumn get positionMs => integer()();
  IntColumn get bookPositionMs => integer()();
  IntColumn get createdAtMs => integer()();
  IntColumn get chapterIndex => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class ListeningHistory extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
  IntColumn get startedAtMs => integer()();
  IntColumn get endedAtMs => integer().nullable()();
  IntColumn get startMs => integer().withDefault(const Constant(0))();
  IntColumn get endMs => integer().withDefault(const Constant(0))();
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Physical audio intervals observed while playing, without seek gaps.
/// The newest 200 ranges per book are retained for local Return Trail replays.
@DataClassName('PlayedPassage')
class PlayedPassages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  TextColumn get filePath => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  IntColumn get heardAtMs => integer()();
}

/// Durable disjoint unions of played audio. Unlike the recent Return Trail,
/// these intervals are never pruned while a book's history is retained.
@DataClassName('CoverageRange')
class PlaybackCoverage extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  TextColumn get filePath => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
}

/// Optional unbounded timestamped evidence and explicit player actions.
@DataClassName('JournalRecord')
class ListeningJournal extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  TextColumn get kind => text()();
  TextColumn get bookTitle => text().withDefault(const Constant(''))();
  TextColumn get chapterTitle => text().nullable()();
  TextColumn get filePath => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get targetFilePath => text().nullable()();
  IntColumn get targetPositionMs => integer().nullable()();
  IntColumn get startedAtMs => integer()();
  IntColumn get endedAtMs => integer()();
  IntColumn get utcOffsetMinutes => integer()();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  TextColumn get reason => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class PlaybackQueue extends Table {
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {bookId};
}

/// Download identity for duplicate detection. Credentials live in secure storage.
class RemoteLinks extends Table {
  TextColumn get bookId => text().customConstraint(
    'NOT NULL REFERENCES books(id) ON DELETE CASCADE',
  )();
  TextColumn get serverUrl => text()();
  TextColumn get userId => text()();
  TextColumn get itemId => text()();
  @override
  Set<Column> get primaryKey => {bookId};
}

@DriftDatabase(
  tables: [
    Books,
    BookTracks,
    Chapters,
    Bookmarks,
    ListeningHistory,
    PlayedPassages,
    PlaybackCoverage,
    ListeningJournal,
    PlaybackQueue,
    RemoteLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'crisperplayer'));
  AppDatabase.forTesting(super.e);
  @override
  int get schemaVersion => 7;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPlayedPassageIndex();
      await _createCoverageIndex();
      await _createJournalIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(bookTracks);
      if (from < 3) {
        await m.addColumn(books, books.finishedOverride);
        await m.addColumn(books, books.series);
        await m.addColumn(books, books.seriesOrder);
        await m.addColumn(books, books.collection);
        await m.addColumn(books, books.playbackPreferencesJson);
        await m.createTable(playbackQueue);
      }
      if (from < 4) await m.createTable(remoteLinks);
      if (from < 5) {
        await m.createTable(playedPassages);
        await _createPlayedPassageIndex();
      }
      if (from < 6) {
        await m.createTable(playbackCoverage);
        await _createCoverageIndex();
        // Only the retained physical evidence can seed an older library.
        // Session endpoints and resume positions do not prove coverage.
        for (final passage in await select(playedPassages).get()) {
          if (passage.startMs >= 0 && passage.endMs > passage.startMs) {
            await mergeCoverageRange(
              bookId: passage.bookId,
              filePath: passage.filePath,
              startMs: passage.startMs,
              endMs: passage.endMs,
            );
          }
        }
      }
      if (from < 7) {
        await m.createTable(listeningJournal);
        await _createJournalIndexes();
        // Existing session endpoints and timeless coverage cannot supply
        // historical timestamped physical evidence. Do not backfill them.
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> _createPlayedPassageIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS played_passages_book_recency '
    'ON played_passages (book_id, heard_at_ms DESC, id DESC)',
  );

  Future<void> _createCoverageIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS playback_coverage_book_file_start '
    'ON playback_coverage (book_id, file_path, start_ms)',
  );

  Future<void> _createJournalIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS listening_journal_time '
      'ON listening_journal (started_at_ms DESC, id DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS listening_journal_book_time '
      'ON listening_journal (book_id, started_at_ms DESC, id DESC)',
    );
  }

  Future<void> saveJournalEntry(
    ListeningJournalEntry input, {
    bool restoring = false,
  }) async {
    final entry = ListeningJournalEntry.fromJson(input.toJson());
    await transaction(() async {
      if (await getBook(entry.bookId) == null) {
        throw const FormatException('Journal book is missing');
      }
      final existing = await (select(
        listeningJournal,
      )..where((row) => row.id.equals(entry.id))).getSingleOrNull();
      if (existing == null) {
        await into(
          listeningJournal,
        ).insert(JournalRecord.fromJson(entry.toJson()).toCompanion(true));
        return;
      }
      final previous = ListeningJournalEntry.fromJson(existing.toJson());
      if (previous.samePlayedOrigin(entry)) {
        if (entry.endMs >= previous.endMs &&
            entry.endedAtMs >= previous.endedAtMs) {
          if (entry.endMs == previous.endMs &&
              entry.endedAtMs == previous.endedAtMs) {
            return;
          }
          await (update(
            listeningJournal,
          )..where((row) => row.id.equals(entry.id))).write(
            ListeningJournalCompanion(
              endMs: Value(entry.endMs),
              endedAtMs: Value(entry.endedAtMs),
            ),
          );
          return;
        }
        if ((entry.endMs <= previous.endMs &&
                entry.endedAtMs <= previous.endedAtMs) ||
            restoring) {
          return;
        }
        throw StateError(
          'A journal checkpoint must advance position and time together',
        );
      }
      if (previous.sameEvent(entry)) return;
      // A restore merges stable UUIDs. Preserve an existing identity, captured
      // timestamps and locally remapped paths. Only compatible played
      // checkpoints above may extend the existing record.
      if (restoring) return;
      throw StateError(
        'A journal ID cannot be reused for a different event or passage',
      );
    });
  }

  Future<void> remapJournalFile(
    String bookId,
    String oldPath,
    String newPath,
  ) => transaction(() async {
    if (oldPath == newPath) return;
    await (update(listeningJournal)..where(
          (row) => row.bookId.equals(bookId) & row.filePath.equals(oldPath),
        ))
        .write(ListeningJournalCompanion(filePath: Value(newPath)));
    await (update(listeningJournal)..where(
          (row) =>
              row.bookId.equals(bookId) & row.targetFilePath.equals(oldPath),
        ))
        .write(ListeningJournalCompanion(targetFilePath: Value(newPath)));
  });

  Future<List<CoverageRange>> coverageFor(String bookId) =>
      (select(playbackCoverage)
            ..where((range) => range.bookId.equals(bookId))
            ..orderBy([
              (range) => OrderingTerm.asc(range.filePath),
              (range) => OrderingTerm.asc(range.startMs),
            ]))
          .get();

  /// Merge exactly overlapping or touching intervals. A seek gap is never
  /// filled, even when both of its endpoints have been played.
  Future<void> mergeCoverageRange({
    required String bookId,
    required String filePath,
    required int startMs,
    required int endMs,
  }) async {
    if (bookId.isEmpty || filePath.isEmpty || startMs < 0 || endMs <= startMs) {
      throw ArgumentError('A valid playback coverage range is required');
    }
    await transaction(() async {
      final overlaps =
          await (select(playbackCoverage)
                ..where(
                  (range) =>
                      range.bookId.equals(bookId) &
                      range.filePath.equals(filePath) &
                      range.startMs.isSmallerOrEqualValue(endMs) &
                      range.endMs.isBiggerOrEqualValue(startMs),
                )
                ..orderBy([(range) => OrderingTerm.asc(range.startMs)]))
              .get();
      if (overlaps.isEmpty) {
        await into(playbackCoverage).insert(
          PlaybackCoverageCompanion.insert(
            bookId: bookId,
            filePath: filePath,
            startMs: startMs,
            endMs: endMs,
          ),
        );
        return;
      }
      final mergedStart = overlaps.fold(
        startMs,
        (start, range) => math.min(start, range.startMs),
      );
      final mergedEnd = overlaps.fold(
        endMs,
        (end, range) => math.max(end, range.endMs),
      );
      final retained = overlaps.first;
      if (overlaps.length == 1 &&
          retained.startMs == mergedStart &&
          retained.endMs == mergedEnd) {
        return;
      }
      await (update(
        playbackCoverage,
      )..where((range) => range.id.equals(retained.id))).write(
        PlaybackCoverageCompanion(
          startMs: Value(mergedStart),
          endMs: Value(mergedEnd),
        ),
      );
      if (overlaps.length > 1) {
        await (delete(playbackCoverage)..where(
              (range) =>
                  range.id.isIn(overlaps.skip(1).map((range) => range.id)),
            ))
            .go();
      }
    });
  }

  Future<void> remapCoverageFile(
    String bookId,
    String oldPath,
    String newPath,
  ) async {
    if (oldPath == newPath) return;
    await transaction(() async {
      final previous =
          await (select(playbackCoverage)..where(
                (range) =>
                    range.bookId.equals(bookId) &
                    range.filePath.equals(oldPath),
              ))
              .get();
      await (delete(playbackCoverage)..where(
            (range) =>
                range.bookId.equals(bookId) & range.filePath.equals(oldPath),
          ))
          .go();
      for (final range in previous) {
        await mergeCoverageRange(
          bookId: bookId,
          filePath: newPath,
          startMs: range.startMs,
          endMs: range.endMs,
        );
      }
    });
  }

  Future<List<PlayedPassage>> playedPassagesFor(String bookId) =>
      (select(playedPassages)
            ..where((p) => p.bookId.equals(bookId))
            ..orderBy([
              (p) => OrderingTerm.desc(p.heardAtMs),
              (p) => OrderingTerm.desc(p.id),
            ])
            ..limit(200))
          .get();

  Future<void> prunePlayedPassages(String bookId) => customStatement(
    'DELETE FROM played_passages WHERE book_id = ? AND id NOT IN '
    '(SELECT id FROM played_passages WHERE book_id = ? '
    'ORDER BY heard_at_ms DESC, id DESC LIMIT 200)',
    [bookId, bookId],
  );
  Future<List<BookTrack>> tracksFor(String bookId) =>
      (select(bookTracks)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.asc(t.trackIndex)]))
          .get();
  Future<void> replaceTracks(String bookId, List<BookTracksCompanion> tracks) =>
      transaction(() async {
        await (delete(bookTracks)..where((t) => t.bookId.equals(bookId))).go();
        await batch((b) => b.insertAll(bookTracks, tracks));
      });
  Future<List<PlaybackQueueData>> queue() => (select(
    playbackQueue,
  )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
  Stream<List<PlaybackQueueData>> watchQueue() => (select(
    playbackQueue,
  )..orderBy([(t) => OrderingTerm.asc(t.position)])).watch();
  Future<void> replaceQueue(List<String> ids) => transaction(() async {
    await delete(playbackQueue).go();
    await batch(
      (b) => b.insertAll(playbackQueue, [
        for (var i = 0; i < ids.length; i++)
          PlaybackQueueCompanion.insert(bookId: ids[i], position: i),
      ]),
    );
  });
  Future<void> clearAllChapters() => delete(chapters).go();
  Future<List<Book>> get allBooks => select(books).get();
  Stream<List<Book>> watchAllBooks() => select(books).watch();
  Future<Book?> getBook(String id) =>
      (select(books)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Book?> watchBook(String id) =>
      (select(books)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<void> upsertBook(BooksCompanion c) =>
      into(books).insertOnConflictUpdate(c);
  Future<void> deleteBook(String id) =>
      (delete(books)..where((t) => t.id.equals(id))).go();
  Future<List<Chapter>> chaptersFor(String bookId) =>
      (select(chapters)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
          .get();
  Stream<List<Chapter>> watchChapters(String bookId) =>
      (select(chapters)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
          .watch();
  Future<void> replaceChapters(
    String bookId,
    List<ChaptersCompanion> list,
  ) async {
    await batch((b) {
      b.deleteWhere(chapters, (t) => t.bookId.equals(bookId));
      b.insertAll(chapters, list);
    });
  }

  Future<List<Bookmark>> bookmarksFor(String bookId) =>
      (select(bookmarks)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
          .get();
  Stream<List<Bookmark>> watchBookmarks(String bookId) =>
      (select(bookmarks)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
          .watch();
  Stream<List<Bookmark>> watchAllBookmarks() => (select(
    bookmarks,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).watch();
  Future<void> insertBookmark(BookmarksCompanion c) =>
      into(bookmarks).insert(c);
  Future<void> deleteBookmark(String id) =>
      (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  Future<void> updateBookmark(String id, String title, String? note) async {
    await (update(bookmarks)..where((t) => t.id.equals(id))).write(
      BookmarksCompanion(title: Value(title), note: Value(note)),
    );
  }

  Future<void> insertHistory(ListeningHistoryCompanion c) =>
      into(listeningHistory).insert(c);
  Future<List<ListeningHistoryData>> historyFor(String bookId) =>
      (select(listeningHistory)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)]))
          .get();
  Stream<List<ListeningHistoryData>> watchHistory() => (select(
    listeningHistory,
  )..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])).watch();
  Future<List<ListeningHistoryData>> recentHistory({int limit = 100}) =>
      (select(listeningHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])
            ..limit(limit))
          .get();
  Future<void> updateHistoryEnd(
    String id,
    int endedAtMs,
    int endMs,
    int listenedMs,
  ) async {
    await (update(listeningHistory)..where((t) => t.id.equals(id))).write(
      ListeningHistoryCompanion(
        endedAtMs: Value(endedAtMs),
        endMs: Value(endMs),
        listenedMs: Value(listenedMs),
      ),
    );
  }

  Future<void> clearAllHistory() => transaction(() async {
    await delete(listeningHistory).go();
    await delete(playedPassages).go();
    await delete(playbackCoverage).go();
    await delete(listeningJournal).go();
  });
  Future<void> clearAllBookmarks() => delete(bookmarks).go();
  Future<void> clearHistoryForBook(String bookId) => transaction(() async {
    await (delete(
      listeningHistory,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (delete(playedPassages)..where((t) => t.bookId.equals(bookId))).go();
    await (delete(
      playbackCoverage,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (delete(
      listeningJournal,
    )..where((t) => t.bookId.equals(bookId))).go();
  });
  Future<void> clearBookmarksForBook(String bookId) =>
      (delete(bookmarks)..where((t) => t.bookId.equals(bookId))).go();
  Future<Map<String, dynamic>> exportAllJson() async {
    final bks = await select(books).get();
    final chs = await select(chapters).get();
    final bms = await select(bookmarks).get();
    final hist = await select(listeningHistory).get();
    final tracks = await select(bookTracks).get();
    final passages = await select(playedPassages).get();
    final coverage = await select(playbackCoverage).get();
    final journal = await select(listeningJournal).get();
    return {
      'version': schemaVersion,
      'queue': (await queue()).map((e) => e.toJson()).toList(),
      'remoteLinks': (await select(
        remoteLinks,
      ).get()).map((e) => e.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'playedPassages': passages.map((p) => p.toJson()).toList(),
      'playbackCoverage': coverage.map((range) => range.toJson()).toList(),
      'listeningJournal': journal.map((entry) => entry.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
      'books': bks
          .map(
            (e) => {
              'id': e.id,
              'title': e.title,
              'author': e.author,
              'series': e.series,
              'seriesOrder': e.seriesOrder,
              'collection': e.collection,
              'playbackPreferencesJson': e.playbackPreferencesJson,
              'coverPath': e.coverPath,
              'filePathsJson': e.filePathsJson,
              'totalDurationMs': e.totalDurationMs,
              'addedAtMs': e.addedAtMs,
              'lastPlayedAtMs': e.lastPlayedAtMs,
              'lastPositionFilePath': e.lastPositionFilePath,
              'lastPositionMs': e.lastPositionMs,
              'totalProgress': e.totalProgress,
              'finishedOverride': e.finishedOverride,
              'isFinished': e.isFinished,
            },
          )
          .toList(),
      'chapters': chs
          .map(
            (e) => {
              'id': e.id,
              'bookId': e.bookId,
              'title': e.title,
              'startMs': e.startMs,
              'endMs': e.endMs,
              'filePath': e.filePath,
              'trackIndex': e.trackIndex,
            },
          )
          .toList(),
      'bookmarks': bms
          .map(
            (e) => {
              'id': e.id,
              'bookId': e.bookId,
              'title': e.title,
              'note': e.note,
              'kind': e.kind,
              'filePath': e.filePath,
              'positionMs': e.positionMs,
              'bookPositionMs': e.bookPositionMs,
              'createdAtMs': e.createdAtMs,
              'chapterIndex': e.chapterIndex,
            },
          )
          .toList(),
      'history': hist
          .map(
            (e) => {
              'id': e.id,
              'bookId': e.bookId,
              'startedAtMs': e.startedAtMs,
              'endedAtMs': e.endedAtMs,
              'startMs': e.startMs,
              'endMs': e.endMs,
              'listenedMs': e.listenedMs,
              'speed': e.speed,
            },
          )
          .toList(),
    };
  }

  Future<void> importAllJson(Map<String, dynamic> data) async {
    final version = data['version'] as int? ?? 1;
    if (version < 1 || version > schemaVersion) {
      throw const FormatException('Unsupported library version');
    }
    // Validate structure before touching the database; all writes are atomic.
    for (final key in [
      'books',
      'tracks',
      'chapters',
      'bookmarks',
      'history',
      'queue',
      'remoteLinks',
      'playedPassages',
      'playbackCoverage',
      'listeningJournal',
    ]) {
      if (data[key] != null && data[key] is! List) {
        throw FormatException('Invalid $key');
      }
    }
    final passages = <PlayedPassagesCompanion>[];
    for (final row in data['playedPassages'] as List? ?? []) {
      if (row is! Map ||
          row['bookId'] is! String ||
          (row['bookId'] as String).isEmpty ||
          row['filePath'] is! String ||
          (row['filePath'] as String).isEmpty ||
          row['startMs'] is! int ||
          row['endMs'] is! int ||
          row['heardAtMs'] is! int ||
          (row['startMs'] as int) < 0 ||
          (row['endMs'] as int) <= (row['startMs'] as int) ||
          (row['heardAtMs'] as int) < 0) {
        throw const FormatException('Invalid played passage');
      }
      // Integer row IDs belong to this database, not the backup. Importing
      // them could overwrite an unrelated book's local passage.
      passages.add(
        PlayedPassagesCompanion.insert(
          bookId: row['bookId'] as String,
          filePath: row['filePath'] as String,
          startMs: row['startMs'] as int,
          endMs: row['endMs'] as int,
          heardAtMs: row['heardAtMs'] as int,
        ),
      );
    }
    final coverage = <PlaybackCoverageCompanion>[];
    for (final row in data['playbackCoverage'] as List? ?? []) {
      if (row is! Map ||
          row['bookId'] is! String ||
          (row['bookId'] as String).isEmpty ||
          row['filePath'] is! String ||
          (row['filePath'] as String).isEmpty ||
          row['startMs'] is! int ||
          row['endMs'] is! int ||
          (row['startMs'] as int) < 0 ||
          (row['endMs'] as int) <= (row['startMs'] as int)) {
        throw const FormatException('Invalid playback coverage');
      }
      coverage.add(
        PlaybackCoverageCompanion.insert(
          bookId: row['bookId'] as String,
          filePath: row['filePath'] as String,
          startMs: row['startMs'] as int,
          endMs: row['endMs'] as int,
        ),
      );
    }
    final journal = <ListeningJournalEntry>[];
    for (final row in data['listeningJournal'] as List? ?? []) {
      if (row is! Map) throw const FormatException('Invalid listening journal');
      try {
        journal.add(
          ListeningJournalEntry.fromJson(row.cast<String, dynamic>()),
        );
      } on TypeError {
        throw const FormatException('Invalid listening journal');
      }
    }
    await transaction(() async {
      final booksJson = (data['books'] as List?) ?? [];
      for (final m in booksJson) {
        final mm = (m as Map).cast<String, dynamic>();
        await into(books).insertOnConflictUpdate(
          BooksCompanion.insert(
            id: mm['id'] as String,
            title: mm['title'] as String,
            author: Value(mm['author'] as String? ?? 'Unknown'),
            series: Value(mm['series'] as String? ?? ''),
            seriesOrder: Value((mm['seriesOrder'] as num?)?.toDouble()),
            collection: Value(mm['collection'] as String? ?? ''),
            playbackPreferencesJson: Value(
              jsonEncode(
                BookPreferences.decode(
                  mm['playbackPreferencesJson'] as String? ?? '{}',
                ),
              ),
            ),
            coverPath: Value(mm['coverPath'] as String? ?? ''),
            filePathsJson: mm['filePathsJson'] as String,
            totalDurationMs: Value(mm['totalDurationMs'] as int? ?? 0),
            addedAtMs: mm['addedAtMs'] as int,
            lastPlayedAtMs: Value(mm['lastPlayedAtMs'] as int?),
            lastPositionFilePath: Value(mm['lastPositionFilePath'] as String?),
            lastPositionMs: Value(mm['lastPositionMs'] as int? ?? 0),
            totalProgress: Value(
              (mm['totalProgress'] as num?)?.toDouble() ?? 0.0,
            ),
            finishedOverride: Value(mm['finishedOverride'] as bool?),
            isFinished: Value(mm['isFinished'] as bool? ?? false),
          ),
        );
      }
      for (final row in data['remoteLinks'] as List? ?? []) {
        final link = RemoteLink.fromJson((row as Map).cast<String, dynamic>());
        final uri = Uri.tryParse(link.serverUrl);
        if (uri == null ||
            !{'https', 'http', 'sftp'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw const FormatException('Invalid remote link');
        }
        await into(remoteLinks).insertOnConflictUpdate(link.toCompanion(true));
      }
      if (data['queue'] != null) {
        final ids = <String>[];
        for (final row in data['queue'] as List) {
          final id = (row as Map)['bookId'] as String;
          if (!ids.contains(id)) ids.add(id);
        }
        await replaceQueue(ids);
      }
      for (final row in (data['tracks'] as List? ?? [])) {
        final t = BookTrack.fromJson((row as Map).cast<String, dynamic>());
        if (t.trackIndex < 0 || (t.durationMs != null && t.durationMs! < 0)) {
          throw const FormatException('Invalid track timing');
        }
        await into(bookTracks).insertOnConflictUpdate(t.toCompanion(true));
      }
      final chaptersJson = (data['chapters'] as List?) ?? [];
      for (final m in chaptersJson) {
        final mm = (m as Map).cast<String, dynamic>();
        await into(chapters).insertOnConflictUpdate(
          ChaptersCompanion.insert(
            id: mm['id'] as String,
            bookId: mm['bookId'] as String,
            title: mm['title'] as String,
            startMs: mm['startMs'] as int,
            endMs: mm['endMs'] as int,
            filePath: Value(mm['filePath'] as String?),
            trackIndex: Value(mm['trackIndex'] as int? ?? 0),
          ),
        );
      }
      final bookmarksJson = (data['bookmarks'] as List?) ?? [];
      for (final m in bookmarksJson) {
        final mm = (m as Map).cast<String, dynamic>();
        await into(bookmarks).insertOnConflictUpdate(
          BookmarksCompanion.insert(
            id: mm['id'] as String,
            bookId: mm['bookId'] as String,
            title: mm['title'] as String,
            note: Value(mm['note'] as String?),
            kind: Value(mm['kind'] as String? ?? 'manual'),
            filePath: mm['filePath'] as String,
            positionMs: mm['positionMs'] as int,
            bookPositionMs: mm['bookPositionMs'] as int,
            createdAtMs: mm['createdAtMs'] as int,
            chapterIndex: Value(mm['chapterIndex'] as int?),
          ),
        );
      }
      final historyJson = (data['history'] as List?) ?? [];
      for (final m in historyJson) {
        final mm = (m as Map).cast<String, dynamic>();
        await into(listeningHistory).insertOnConflictUpdate(
          ListeningHistoryCompanion.insert(
            id: mm['id'] as String,
            bookId: mm['bookId'] as String,
            startedAtMs: mm['startedAtMs'] as int,
            endedAtMs: Value(mm['endedAtMs'] as int?),
            startMs: Value(mm['startMs'] as int? ?? 0),
            endMs: Value(mm['endMs'] as int? ?? 0),
            listenedMs: Value(mm['listenedMs'] as int? ?? 0),
            speed: Value((mm['speed'] as num?)?.toDouble() ?? 1.0),
          ),
        );
      }
      final passageBooks = <String>{};
      for (final passage in passages) {
        final bookId = passage.bookId.value;
        if (!passageBooks.contains(bookId) && await getBook(bookId) == null) {
          throw const FormatException('Played passage book is missing');
        }
        passageBooks.add(bookId);
        final existing =
            await (select(playedPassages)
                  ..where(
                    (p) =>
                        p.bookId.equals(bookId) &
                        p.filePath.equals(passage.filePath.value) &
                        p.startMs.equals(passage.startMs.value) &
                        p.endMs.equals(passage.endMs.value) &
                        p.heardAtMs.equals(passage.heardAtMs.value),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (existing == null) await into(playedPassages).insert(passage);
        // Version-five backups have retained ranges but no cumulative map.
        await mergeCoverageRange(
          bookId: bookId,
          filePath: passage.filePath.value,
          startMs: passage.startMs.value,
          endMs: passage.endMs.value,
        );
      }
      for (final bookId in passageBooks) {
        await prunePlayedPassages(bookId);
      }
      final coverageBooks = <String>{};
      for (final range in coverage) {
        final bookId = range.bookId.value;
        if (!coverageBooks.contains(bookId) && await getBook(bookId) == null) {
          throw const FormatException('Playback coverage book is missing');
        }
        coverageBooks.add(bookId);
        await mergeCoverageRange(
          bookId: bookId,
          filePath: range.filePath.value,
          startMs: range.startMs.value,
          endMs: range.endMs.value,
        );
      }
      for (final entry in journal) {
        await saveJournalEntry(entry, restoring: true);
      }
    });
  }

  static String encodePaths(List<String> paths) => jsonEncode(paths);
  static List<String> decodePaths(String json) =>
      (jsonDecode(json) as List).cast<String>();
}
