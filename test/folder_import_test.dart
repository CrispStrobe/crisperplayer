import 'dart:io';
import 'dart:async';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/utils/folder_import.dart';
import 'package:crisperplayer/widgets/folder_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('folder_plan_'),
  );
  tearDown(() async => root.delete(recursive: true));

  Future<File> audio(String path) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsBytes([1, 2, 3]);
  }

  test(
    'nested author books and numbered discs form distinct natural plans',
    () async {
      await audio('Author/Book 10/chapter1.MP3');
      await audio('Author/Book 2/CD 10/track1.wav');
      await audio('Author/Book 2/CD 2/track10.wav');
      await audio('Author/Book 2/CD 2/track2.wav');
      await audio('Author/Book 2/Bonus/story.opus');
      await audio('Author/Book 3/Part_1/one.mka');
      await audio('Author/Book 3/Part_2/two.mka');
      final books = await scanBookFolders(root.path);
      expect(books.map((b) => b.title), [
        'Book 2',
        'Bonus',
        'Book 3',
        'Book 10',
      ]);
      expect(books.first.files.map((f) => f.substring(root.path.length + 1)), [
        'Author/Book 2/CD 2/track2.wav',
        'Author/Book 2/CD 2/track10.wav',
        'Author/Book 2/CD 10/track1.wav',
      ]);
      expect(books[2].files, hasLength(2));
      expect(books.expand((b) => b.files), hasLength(7));
    },
  );

  test(
    'direct audio merges with discs; selecting a disc itself stays one book',
    () async {
      await audio('Book/introduction.wav');
      await audio('Book/Disc-1/chapter1.wav');
      await audio('Book/Disc-2/chapter2.wav');
      expect(
        (await scanBookFolders('${root.path}/Book')).single.files,
        hasLength(3),
      );
      expect(
        (await scanBookFolders('${root.path}/Book/Disc-1')).single.title,
        'Disc-1',
      );
    },
  );

  test(
    'skips hidden files, hidden folders and symbolic links',
    () async {
      final visible = await audio('Book/chapter1.wav');
      await audio('Book/._chapter1.wav');
      await audio('.cache/ghost.mp3');
      await audio('Book/.hidden/ghost.mp3');
      await Link('${root.path}/linked-book').create(visible.parent.path);
      await Link('${root.path}/linked.mp3').create(visible.path);
      await Link('${root.path}/Book/loop').create(root.path);
      await audio('Book/notes.txt');
      expect((await scanBookFolders(root.path)).single.files, [visible.path]);
    },
    skip: Platform.isWindows
        ? 'Creating links requires special privileges'
        : false,
  );

  test(
    'missing folder fails clearly; empty folder returns no candidates',
    () async {
      expect(await scanBookFolders(root.path), isEmpty);
      await expectLater(
        scanBookFolders('${root.path}/absent'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  testWidgets(
    'preview selection imports only the chosen book with folder title',
    (tester) async {
      final harness = PlaybackHarness();
      final books = (await tester.runAsync(() async {
        await audio('Book one/chapter.wav');
        await audio('Book two/chapter.wav');
        await harness.init();
        return scanBookFolders(root.path);
      }))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => FolderImportDialog(
                      books: books,
                      library: harness.library,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Book two'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.text('Import 1 book')));
        await tester.runAsync(() async {
          for (var i = 0; i < 100; i++) {
            if ((await harness.library.allBooks()).isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(find.text('Imported 1 book'), findsOneWidget);
        await tester.runAsync(() async {
          expect((await harness.library.allBooks()).single.title, 'Book one');
          expect(
            await File('${root.path}/Book one/chapter.wav').exists(),
            isTrue,
          );
        });
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(harness.dispose);
      }
    },
  );
  testWidgets(
    'stop finishes the active book and leaves later books untouched',
    (tester) async {
      final harness = PlaybackHarness();
      final gate = Completer<Duration?>();
      var probing = false;
      final books = (await tester.runAsync(() async {
        await audio('A/track.wav');
        await audio('B/track.wav');
        await harness.init();
        return scanBookFolders(root.path);
      }))!;
      final library = LibraryService(
        harness.db,
        storageDirectory: () async => Directory('${root.path}/owned'),
        probeDuration: (_) {
          probing = true;
          return gate.future;
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: FolderImportDialog(books: books, library: library),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Import 2 books'));
          for (var i = 0; i < 100 && !probing; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(probing, isTrue);
        await tester.pump();
        await tester.tap(find.text('Stop after this book'));
        await tester.pump();
        await tester.runAsync(() async {
          gate.complete(const Duration(seconds: 1));
          for (var i = 0; i < 100; i++) {
            if ((await library.allBooks()).isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(find.text('Imported 1 book'), findsOneWidget);
        await tester.runAsync(() async {
          expect((await library.allBooks()).single.title, 'A');
          expect(await File('${root.path}/B/track.wav').exists(), isTrue);
        });
      } finally {
        if (!gate.isCompleted) gate.complete(null);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
