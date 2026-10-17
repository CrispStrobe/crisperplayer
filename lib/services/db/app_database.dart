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
  TextColumn get filePathsJson => text()(); // JSON array
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
  TextColumn get kind => text().withDefault(const Constant('manual'))(); // manual/auto
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

  // For testing / custom path
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  // Books
  Future<List<Book>> get allBooks => select(books).get();
  Stream<List<Book>> watchAllBooks() => select(books).watch();
  Future<Book?> getBook(String id) => (select(books)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Book?> watchBook(String id) => (select(books)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<void> upsertBook(BooksCompanion c) => into(books).insertOnConflictUpdate(c);
  Future<void> deleteBook(String id) => (delete(books)..where((t) => t.id.equals(id))).go();

  // Chapters
  Future<List<Chapter>> chaptersFor(String bookId) => (select(chapters)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.asc(t.startMs)])).get();
  Stream<List<Chapter>> watchChapters(String bookId) => (select(chapters)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.asc(t.startMs)])).watch();
  Future<void> replaceChapters(String bookId, List<ChaptersCompanion> list) async {
    await batch((b) {
      b.deleteWhere(chapters, (t) => t.bookId.equals(bookId));
      b.insertAll(chapters, list);
    });
  }

  // Bookmarks
  Future<List<Bookmark>> bookmarksFor(String bookId) => (select(bookmarks)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).get();
  Stream<List<Bookmark>> watchBookmarks(String bookId) => (select(bookmarks)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).watch();
  Stream<List<Bookmark>> watchAllBookmarks() => (select(bookmarks)..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).watch();
  Future<void> insertBookmark(BookmarksCompanion c) => into(bookmarks).insert(c);
  Future<void> deleteBookmark(String id) => (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  Future<void> updateBookmark(String id, String title, String? note) async {
    await (update(bookmarks)..where((t) => t.id.equals(id))).write(BookmarksCompanion(title: Value(title), note: Value(note)));
  }

  // History
  Future<void> insertHistory(ListeningHistoryCompanion c) => into(listeningHistory).insert(c);
  Future<List<ListeningHistoryData>> historyFor(String bookId) => (select(listeningHistory)..where((t) => t.bookId.equals(bookId))..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])).get();
  Stream<List<ListeningHistoryData>> watchHistory() => (select(listeningHistory)..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])).watch();
  Future<List<ListeningHistoryData>> recentHistory({int limit = 100}) => (select(listeningHistory)..orderBy([(t) => OrderingTerm.desc(t.startedAtMs)])..limit(limit)).get();
  Future<void> updateHistoryEnd(String id, int endedAtMs, int endMs, int listenedMs) async {
    await (update(listeningHistory)..where((t) => t.id.equals(id))).write(ListeningHistoryCompanion(endedAtMs: Value(endedAtMs), endMs: Value(endMs), listenedMs: Value(listenedMs)));
  }

  // Helpers
  static String encodePaths(List<String> paths) => jsonEncode(paths);
  static List<String> decodePaths(String json) => (jsonDecode(json) as List).cast<String>();
}

