import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant('Unknown'))();
  TextColumn get coverPath => text().withDefault(const Constant(''))();
  TextColumn get filePathsJson => text()();
  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();
  IntColumn get addedAtMs => integer()();
  IntColumn get lastPlayedAtMs => integer().nullable()();
  TextColumn get lastPositionFilePath => text().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  RealColumn get totalProgress => real().withDefault(const Constant(0))();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
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
  TextColumn get bookId => text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
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
  TextColumn get bookId => text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
  IntColumn get startedAtMs => integer()();
  IntColumn get endedAtMs => integer().nullable()();
  IntColumn get startMs => integer().withDefault(const Constant(0))();
  IntColumn get endMs => integer().withDefault(const Constant(0))();
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Books, Chapters, Bookmarks, ListeningHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'crisperplayer'));
  AppDatabase.forTesting(super.e);
  @override
  int get schemaVersion => 1;
  Future<List<Book>> get allBooks => select(books).get();
  Stream<List<Book>> watchAllBooks() => select(books).watch();
  Future<Book?> getBook(String id) => (select(books)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Book?> watchBook(String id) => (select(books)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<void> upsertBook(BooksCompanion c) => into(books).insertOnConflictUpdate(c);
  Future<void> deleteBook(String id) => (delete(books)..where((t) => t.id.equals(id))).go();
  Future<List<Chapter>> chaptersFor(String bookId) => (select(chapters)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.asc(t.startMs)])).get();
  Stream<List<Chapter>> watchChapters(String bookId) => (select(chapters)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.asc(t.startMs)])).watch();
  Future<void> replaceChapters(String bookId, List<ChaptersCompanion> list) async { await batch((b) { b.deleteWhere(chapters, (t) => t.bookId.equals(bookId)); b.insertAll(chapters, list); }); }
  Future<List<Bookmark>> bookmarksFor(String bookId) => (select(bookmarks)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).get();
  Stream<List<Bookmark>> watchBookmarks(String bookId) => (select(bookmarks)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).watch();
  Stream<List<Bookmark>> watchAllBookmarks() => (select(bookmarks)..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).watch();
  Future<void> insertBookmark(BookmarksCompanion c) => into(bookmarks).insert(c);
  Future<void> deleteBookmark(String id) => (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  Future<void> updateBookmark(String id, String title, String? note) async { await (update(bookmarks)..where((t) => t.id.equals(id))).write(BookmarksCompanion(title: Value(title), note: Value(note))); }
  Future<void> insertHistory(ListeningHistoryCompanion c) => into(listeningHistory).insert(c);
  Future<List<ListeningHistoryData>> historyFor(String bookId) => (select(listeningHistory)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])).get();
  Stream<List<ListeningHistoryData>> watchHistory() => (select(listeningHistory)..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])).watch();
  Future<List<ListeningHistoryData>> recentHistory({int limit = 100}) => (select(listeningHistory)..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])..limit(limit)).get();
  Future<void> updateHistoryEnd(String id, int endedAtMs, int endMs, int listenedMs) async { await (update(listeningHistory)..where((t) => t.id.equals(id))).write(ListeningHistoryCompanion(endedAtMs: Value(endedAtMs), endMs: Value(endMs), listenedMs: Value(listenedMs))); }
  Future<void> clearAllHistory() => delete(listeningHistory).go();
  Future<void> clearAllBookmarks() => delete(bookmarks).go();
  Future<void> clearHistoryForBook(String bookId) => (delete(listeningHistory)..where((t) => t.bookId.equals(bookId))).go();
  Future<void> clearBookmarksForBook(String bookId) => (delete(bookmarks)..where((t) => t.bookId.equals(bookId))).go();
  Future<Map<String, dynamic>> exportAllJson() async {
    final bks = await select(books).get();
    final chs = await select(chapters).get();
    final bms = await select(bookmarks).get();
    final hist = await select(listeningHistory).get();
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': bks.map((e) => {'id': e.id, 'title': e.title, 'author': e.author, 'coverPath': e.coverPath, 'filePathsJson': e.filePathsJson, 'totalDurationMs': e.totalDurationMs, 'addedAtMs': e.addedAtMs, 'lastPlayedAtMs': e.lastPlayedAtMs, 'lastPositionFilePath': e.lastPositionFilePath, 'lastPositionMs': e.lastPositionMs, 'totalProgress': e.totalProgress, 'isFinished': e.isFinished}).toList(),
      'chapters': chs.map((e) => {'id': e.id, 'bookId': e.bookId, 'title': e.title, 'startMs': e.startMs, 'endMs': e.endMs, 'filePath': e.filePath, 'trackIndex': e.trackIndex}).toList(),
      'bookmarks': bms.map((e) => {'id': e.id, 'bookId': e.bookId, 'title': e.title, 'note': e.note, 'kind': e.kind, 'filePath': e.filePath, 'positionMs': e.positionMs, 'bookPositionMs': e.bookPositionMs, 'createdAtMs': e.createdAtMs, 'chapterIndex': e.chapterIndex}).toList(),
      'history': hist.map((e) => {'id': e.id, 'bookId': e.bookId, 'startedAtMs': e.startedAtMs, 'endedAtMs': e.endedAtMs, 'startMs': e.startMs, 'endMs': e.endMs, 'listenedMs': e.listenedMs, 'speed': e.speed}).toList(),
    };
  }
  Future<void> importAllJson(Map<String, dynamic> data) async {
    await batch((b) {
      final booksJson = (data['books'] as List?) ?? [];
      for (final m in booksJson) { final mm = (m as Map).cast<String, dynamic>(); b.insert(books, BooksCompanion.insert(id: mm['id'] as String, title: mm['title'] as String, author: Value(mm['author'] as String? ?? 'Unknown'), coverPath: Value(mm['coverPath'] as String? ?? ''), filePathsJson: mm['filePathsJson'] as String, totalDurationMs: Value(mm['totalDurationMs'] as int? ?? 0), addedAtMs: mm['addedAtMs'] as int, lastPlayedAtMs: Value(mm['lastPlayedAtMs'] as int?), lastPositionFilePath: Value(mm['lastPositionFilePath'] as String?), lastPositionMs: Value(mm['lastPositionMs'] as int? ?? 0), totalProgress: Value((mm['totalProgress'] as num?)?.toDouble() ?? 0.0), isFinished: Value(mm['isFinished'] as bool? ?? false)), mode: InsertMode.insertOrReplace); }
      final chaptersJson = (data['chapters'] as List?) ?? [];
      for (final m in chaptersJson) { final mm = (m as Map).cast<String, dynamic>(); b.insert(chapters, ChaptersCompanion.insert(id: mm['id'] as String, bookId: mm['bookId'] as String, title: mm['title'] as String, startMs: mm['startMs'] as int, endMs: mm['endMs'] as int, filePath: Value(mm['filePath'] as String?), trackIndex: Value(mm['trackIndex'] as int? ?? 0)), mode: InsertMode.insertOrReplace); }
      final bookmarksJson = (data['bookmarks'] as List?) ?? [];
      for (final m in bookmarksJson) { final mm = (m as Map).cast<String, dynamic>(); b.insert(bookmarks, BookmarksCompanion.insert(id: mm['id'] as String, bookId: mm['bookId'] as String, title: mm['title'] as String, note: Value(mm['note'] as String?), kind: Value(mm['kind'] as String? ?? 'manual'), filePath: mm['filePath'] as String, positionMs: mm['positionMs'] as int, bookPositionMs: mm['bookPositionMs'] as int, createdAtMs: mm['createdAtMs'] as int, chapterIndex: Value(mm['chapterIndex'] as int?)), mode: InsertMode.insertOrReplace); }
      final historyJson = (data['history'] as List?) ?? [];
      for (final m in historyJson) { final mm = (m as Map).cast<String, dynamic>(); b.insert(listeningHistory, ListeningHistoryCompanion.insert(id: mm['id'] as String, bookId: mm['bookId'] as String, startedAtMs: mm['startedAtMs'] as int, endedAtMs: Value(mm['endedAtMs'] as int?), startMs: Value(mm['startMs'] as int? ?? 0), endMs: Value(mm['endMs'] as int? ?? 0), listenedMs: Value(mm['listenedMs'] as int? ?? 0), speed: Value((mm['speed'] as num?)?.toDouble() ?? 1.0)), mode: InsertMode.insertOrReplace); }
    });
  }
  static String encodePaths(List<String> paths) => jsonEncode(paths);
  static List<String> decodePaths(String json) => (jsonDecode(json) as List).cast<String>();
}

// --- Added for Settings export/import + clear ---

extension AppDatabaseMaintenance on AppDatabase {
  Future<void> clearAllHistory() => delete(listeningHistory).go();
  Future<void> clearAllBookmarks() => delete(bookmarks).go();
  Future<void> clearAllChapters() => delete(chapters).go();

  Future<Map<String, dynamic>> exportAllJson() async {
    final b = await select(books).get();
    final c = await select(chapters).get();
    final m = await select(bookmarks).get();
    final h = await select(listeningHistory).get();
    return {
      'books': b.map((e) => e.toJson()).toList(),
      'chapters': c.map((e) => e.toJson()).toList(),
      'bookmarks': m.map((e) => e.toJson()).toList(),
      'history': h.map((e) => e.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
      'version': 1,
    };
  }

  Future<void> importAllJson(Map<String, dynamic> data) async {
    await batch((b) {
      if (data['books'] is List) {
        for (final j in (data['books'] as List).cast<Map<String, dynamic>>()) {
          b.insert(books, BooksCompanion(
            id: Value(j['id'] as String),
            title: Value(j['title'] as String),
            author: Value(j['author'] as String? ?? 'Unknown'),
            coverPath: Value(j['coverPath'] as String? ?? ''),
            filePathsJson: Value(j['filePathsJson'] as String? ?? AppDatabase.encodePaths([])),
            totalDurationMs: Value(j['totalDurationMs'] as int? ?? 0),
            addedAtMs: Value(j['addedAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch),
            lastPlayedAtMs: Value(j['lastPlayedAtMs'] as int?),
            lastPositionFilePath: Value(j['lastPositionFilePath'] as String?),
            lastPositionMs: Value(j['lastPositionMs'] as int? ?? 0),
            totalProgress: Value((j['totalProgress'] as num?)?.toDouble() ?? 0),
            isFinished: Value(j['isFinished'] as bool? ?? false),
          ), onConflict: DoUpdate((old) => BooksCompanion.custom(), target: [books.id]));
        }
      }
      if (data['chapters'] is List) {
        for (final j in (data['chapters'] as List).cast<Map<String, dynamic>>()) {
          b.insert(chapters, ChaptersCompanion(
            id: Value(j['id'] as String),
            bookId: Value(j['bookId'] as String),
            title: Value(j['title'] as String),
            startMs: Value(j['startMs'] as int),
            endMs: Value(j['endMs'] as int),
            filePath: Value(j['filePath'] as String?),
            trackIndex: Value(j['trackIndex'] as int? ?? 0),
          ), onConflict: DoUpdate((old) => ChaptersCompanion.custom(), target: [chapters.id]));
        }
      }
      if (data['bookmarks'] is List) {
        for (final j in (data['bookmarks'] as List).cast<Map<String, dynamic>>()) {
          b.insert(bookmarks, BookmarksCompanion(
            id: Value(j['id'] as String),
            bookId: Value(j['bookId'] as String),
            title: Value(j['title'] as String),
            note: Value(j['note'] as String?),
            kind: Value(j['kind'] as String? ?? 'manual'),
            filePath: Value(j['filePath'] as String),
            positionMs: Value(j['positionMs'] as int),
            bookPositionMs: Value(j['bookPositionMs'] as int),
            createdAtMs: Value(j['createdAtMs'] as int),
            chapterIndex: Value(j['chapterIndex'] as int?),
          ), onConflict: DoUpdate((old) => BookmarksCompanion.custom(), target: [bookmarks.id]));
        }
      }
      if (data['history'] is List) {
        for (final j in (data['history'] as List).cast<Map<String, dynamic>>()) {
          b.insert(listeningHistory, ListeningHistoryCompanion(
            id: Value(j['id'] as String),
            bookId: Value(j['bookId'] as String),
            startedAtMs: Value(j['startedAtMs'] as int),
            endedAtMs: Value(j['endedAtMs'] as int?),
            startMs: Value(j['startMs'] as int? ?? 0),
            endMs: Value(j['endMs'] as int? ?? 0),
            listenedMs: Value(j['listenedMs'] as int? ?? 0),
            speed: Value((j['speed'] as num?)?.toDouble() ?? 1.0),
          ), onConflict: DoUpdate((old) => ListeningHistoryCompanion.custom(), target: [listeningHistory.id]));
        }
      }
    });
  }
}
