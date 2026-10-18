import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version-one library upgrades without losing books or bookmarks',
      () async {
    final dir = await Directory.systemTemp.createTemp('crisper_migration_');
    final file = File('${dir.path}/library.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await db.upsertBook(BooksCompanion.insert(
          id: 'a',
          title: 'Original',
          filePathsJson: '["/a.mp3"]',
          addedAtMs: 1));
      await db.insertBookmark(BookmarksCompanion.insert(
          id: 'bm',
          bookId: 'a',
          title: 'Place',
          filePath: '/a.mp3',
          positionMs: 1000,
          bookPositionMs: 1000,
          createdAtMs: 1));
      // The v1 schema is identical except for the absence of book_tracks.
      await db.customStatement('DROP TABLE book_tracks');
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect((await db.getBook('a'))!.title, 'Original');
      expect(await db.bookmarksFor('a'), hasLength(1));
      expect(await db.tracksFor('a'), isEmpty);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test(
      'export/import roundtrip preserves tracks; repeated import keeps children',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      await db.upsertBook(BooksCompanion.insert(
          id: 'a',
          title: 'Original',
          filePathsJson: '["/a.mp3"]',
          addedAtMs: 1));
      await db.replaceTracks('a', [
        BookTracksCompanion.insert(
            bookId: 'a',
            trackIndex: 0,
            filePath: '/a.mp3',
            durationMs: const Value(10000))
      ]);
      await db.insertBookmark(BookmarksCompanion.insert(
          id: 'bm',
          bookId: 'a',
          title: 'Place',
          filePath: '/a.mp3',
          positionMs: 1000,
          bookPositionMs: 1000,
          createdAtMs: 1));
      final exported = await db.exportAllJson();
      await db.importAllJson(exported);
      expect((await db.tracksFor('a')).single.durationMs, 10000);
      expect(await db.bookmarksFor('a'), hasLength(1));
      // A book-only update must not delete its existing related rows.
      await db.importAllJson({
        'books': [
          {
            'id': 'a',
            'title': 'Updated',
            'filePathsJson': '["/a.mp3"]',
            'addedAtMs': 1
          }
        ]
      });
      expect(await db.bookmarksFor('a'), hasLength(1));
      expect(await db.tracksFor('a'), hasLength(1));
    } finally {
      await db.close();
    }
  });
  test('malformed imports roll back all rows and future versions are rejected',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      final data = {
        'version': 2,
        'books': [
          {'id': 'a', 'title': 'Valid', 'filePathsJson': '[]', 'addedAtMs': 1},
          {'id': 'b', 'title': 123},
        ]
      };
      await expectLater(db.importAllJson(data), throwsA(anything));
      expect(await db.allBooks, isEmpty);
      await expectLater(
          db.importAllJson({'version': 99}), throwsFormatException);
    } finally {
      await db.close();
    }
  });
}
