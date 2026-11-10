import 'dart:io';

import 'package:crisperplayer/models/return_trail.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'adopting restored legacy audio preserves its trail and scopes path updates to the book',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'crisper_trail_import_',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final source = await File(
          '${root.path}/chapter.mp3',
        ).writeAsBytes([1, 2, 3]);
        final library = LibraryService(
          db,
          storageDirectory: () async => Directory('${root.path}/managed'),
          probeDuration: (_) async => const Duration(seconds: 90),
        );
        for (final id in ['restored', 'other']) {
          await db.upsertBook(
            BooksCompanion.insert(
              id: id,
              title: id,
              filePathsJson: AppDatabase.encodePaths([source.path]),
              addedAtMs: 1,
              lastPositionFilePath: Value(source.path),
              lastPositionMs: const Value(60000),
            ),
          );
          await ReturnTrailService(db).record(
            bookId: id,
            filePath: source.path,
            startMs: 10000,
            endMs: 50000,
            heardAtMs: 1,
          );
        }

        final tracks = await library.ensureTracks(
          (await db.getBook('restored'))!,
        );
        final managedPath = tracks.single.filePath;
        expect(managedPath, isNot(source.path));
        expect(await File(managedPath).readAsBytes(), [1, 2, 3]);
        expect(await source.readAsBytes(), [1, 2, 3]);
        expect(
          (await db.playedPassagesFor('restored')).single.filePath,
          managedPath,
        );
        expect(
          (await db.playedPassagesFor('other')).single.filePath,
          source.path,
        );
        expect((await db.coverageFor('restored')).single.filePath, managedPath);
        expect((await db.coverageFor('other')).single.filePath, source.path);
        expect(
          (await db.getBook('restored'))!.lastPositionFilePath,
          managedPath,
        );

        final plan = await ReturnTrailService(db).plan(
          anchor: TrailAnchor(
            bookId: 'restored',
            filePath: managedPath,
            positionMs: 60000,
          ),
        );
        expect(plan.clips, hasLength(1));
        expect(plan.clips.single.filePath, managedPath);
        expect(
          (plan.clips.single.startMs, plan.clips.single.endMs),
          (10000, 50000),
        );
        expect(plan.mediaDuration, const Duration(seconds: 40));
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}
