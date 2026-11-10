import 'dart:convert';
import '../../models/book_preferences.dart';
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
    PlaybackQueue,
    RemoteLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'crisperplayer'));
  AppDatabase.forTesting(super.e);
  @override
  int get schemaVersion => 5;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPlayedPassageIndex();
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
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> _createPlayedPassageIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS played_passages_book_recency '
    'ON played_passages (book_id, heard_at_ms DESC, id DESC)',
  );

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
  });
  Future<void> clearAllBookmarks() => delete(bookmarks).go();
  Future<void> clearHistoryForBook(String bookId) => transaction(() async {
    await (delete(
      listeningHistory,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (delete(playedPassages)..where((t) => t.bookId.equals(bookId))).go();
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
    return {
      'version': schemaVersion,
      'queue': (await queue()).map((e) => e.toJson()).toList(),
      'remoteLinks': (await select(
        remoteLinks,
      ).get()).map((e) => e.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'playedPassages': passages.map((p) => p.toJson()).toList(),
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
      }
      for (final bookId in passageBooks) {
        await prunePlayedPassages(bookId);
      }
    });
  }

  static String encodePaths(List<String> paths) => jsonEncode(paths);
  static List<String> decodePaths(String json) =>
      (jsonDecode(json) as List).cast<String>();
}
