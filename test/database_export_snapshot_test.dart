import 'dart:async';

import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'export remains restorable during a concurrent library import',
    () async {
      final barrier = _AfterBooksRead();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(barrier),
      );
      addTearDown(db.close);
      Future<void> addBook(String id) => db.upsertBook(
        BooksCompanion.insert(
          id: id,
          title: id,
          filePathsJson: '["/$id.mp3"]',
          addedAtMs: 1,
        ),
      );
      await addBook('existing');

      barrier.enabled = true;
      final exporting = db.exportAllJson();
      await barrier.booksRead.future;
      final importing = db.transaction(() async {
        await addBook('arriving');
        await ListeningJournalService(db).recordPlayed(
          bookId: 'arriving',
          filePath: '/arriving.mp3',
          startMs: 0,
          endMs: 10000,
          startedAtMs: 1000,
          endedAtMs: 11000,
          utcOffsetMinutes: 0,
        );
      });
      // Allow an unrelated operation to run between table reads. A consistent
      // export must keep its earlier snapshot, even if that operation is ready.
      await Future<void>.delayed(Duration.zero);
      barrier.continueReading.complete();
      final snapshot = await exporting;
      await importing;

      expect((await db.allBooks).map((book) => book.id), contains('arriving'));
      expect((await ListeningJournalService(db).page()).entries, hasLength(1));
      await db.close();
      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      await restored.importAllJson(snapshot);
      expect((await restored.allBooks).map((book) => book.id), ['existing']);
      expect((await ListeningJournalService(restored).page()).entries, isEmpty);
    },
  );
}

class _AfterBooksRead extends QueryInterceptor {
  bool enabled = false;
  final booksRead = Completer<void>();
  final continueReading = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runSelect(executor, statement, args);
    if (enabled && statement.contains('FROM "books"')) {
      enabled = false;
      booksRead.complete();
      await continueReading.future;
    }
    return result;
  }
}
