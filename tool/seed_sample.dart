import 'dart:io';
import 'package:drift/native.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/drift.dart';

Future<void> main() async {
  final sample = File('/home/claudeuser/jfk-test.m4a');
  if (!await sample.exists()) {
    print('no sample at /home/claudeuser/jfk-test.m4a');
    return;
  }
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final id = 'sample-jfk';
  await db.upsertBook(BooksCompanion.insert(
    id: id,
    title: 'JFK Sample (m4a)',
    author: const Value('Test'),
    filePathsJson: '["${sample.path}"]',
    totalDurationMs: const Value(12000),
    addedAtMs: DateTime.now().millisecondsSinceEpoch,
  ));
  print('seeded $id with ${sample.path}');
  final books = await db.allBooks;
  print('books: ${books.map((b)=> b.title).join(', ')}');
  await db.close();
}
