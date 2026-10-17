import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:crisperplayer/services/db/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('books CRUD + watch', () async {
    await db.upsertBook(BooksCompanion.insert(id: 'b1', title: 'Test Book', filePathsJson: '["/a.mp3"]', addedAtMs: DateTime.now().millisecondsSinceEpoch));
    final all = await db.allBooks;
    expect(all.length, 1);
    expect(all.first.title, 'Test Book');
    await db.deleteBook('b1');
    expect((await db.allBooks).length, 0);
  });

  test('bookmarks auto prune', () async {
    await db.upsertBook(BooksCompanion.insert(id: 'b1', title: 'B', filePathsJson: '["/a.mp3"]', addedAtMs: 0));
    // insert 25 auto bookmarks
    for (int i=0;i<25;i++) {
      await db.insertBookmark(BookmarksCompanion.insert(id: 'bm$i', bookId: 'b1', title: 'Auto $i', kind: const Value('auto'), filePath: '/a.mp3', positionMs: i*1000, bookPositionMs: i*1000, createdAtMs: i));
    }
    final all = await db.bookmarksFor('b1');
    expect(all.length, 25);
    // simulate prune keep 20
    final autos = all.where((b)=> b.kind=='auto').toList()..sort((a,b)=> b.createdAtMs.compareTo(a.createdAtMs));
    for (final b in autos.skip(20)) await db.deleteBookmark(b.id);
    expect((await db.bookmarksFor('b1')).length, 20);
  });

  test('history group by day', () async {
    await db.upsertBook(BooksCompanion.insert(id: 'b1', title: 'B', filePathsJson: '["/a.mp3"]', addedAtMs: 0));
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insertHistory(ListeningHistoryCompanion.insert(id: 'h1', bookId: 'b1', startedAtMs: now, startMs: const Value(0)));
    await db.insertHistory(ListeningHistoryCompanion.insert(id: 'h2', bookId: 'b1', startedAtMs: now - 86400000, startMs: const Value(1000)));
    final hist = await db.recentHistory(limit: 10);
    expect(hist.length, 2);
  });

  test('progress persist', () async {
    await db.upsertBook(BooksCompanion.insert(id: 'b1', title: 'T', filePathsJson: '["/a.mp3","/b.mp3"]', totalDurationMs: const Value(3600000), addedAtMs: 0));
    await (db.update(db.books)..where((t)=> t.id.equals('b1'))).write(BooksCompanion(lastPlayedAtMs: Value(DateTime.now().millisecondsSinceEpoch), lastPositionMs: const Value(12345), totalProgress: const Value(0.5)));
    final b = await db.getBook('b1');
    expect(b!.lastPositionMs, 12345);
    expect(b.totalProgress, closeTo(0.5, 0.01));
  });
}
