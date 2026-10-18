import 'dart:async';
import 'dart:convert';
import 'package:crisperplayer/screens/sync_settings_screen.dart';
import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/main.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native desktop import, playback, CLI, UI, and disk persistence',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('crisper_native_');
      final databaseFile = File('${root.path}/library.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(databaseFile));
      SharedPreferences.setMockInitialValues({'onboarding_done': true});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs)..onboardingDone = true;
      final library = LibraryService(db, storageDirectory: () async => root);
      final player = AudioPlayer(handleInterruptions: false);
      final playback = PlaybackService(
        db: db,
        library: library,
        bookmarks: BookmarkService(db),
        history: HistoryService(db),
        settings: settings,
        audioPlayer: player,
      );
      final descriptor = File('${root.path}/cli.json');
      final server = DesktopControlService(
        library: library,
        playback: playback,
        descriptor: descriptor,
      );
      final client = ControlClient(descriptor);
      var databaseClosed = false;
      try {
        await playback.init();
        await playback.setVolume(
          0,
        ); // Exercise the native decoder without playing a tone aloud.
        await server.start();
        // Command-line macOS launches can begin with the scheduler paused.
        // These UI tests explicitly drive the app as a foreground application.
        if (Platform.isMacOS) {
          debugPrint(
            'Native UI lifecycle: ${tester.binding.lifecycleState}, frames: ${tester.binding.framesEnabled}',
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsProvider.overrideWith((ref) => settings),
              libraryServiceProvider.overrideWithValue(library),
              playbackProvider.overrideWithValue(playback),
            ],
            child: CrisperPlayerApp(settings: settings, prefs: prefs),
          ),
        );
        await tester.pumpAndSettle();
        final source = await writeTestWav(
          File('${root.path}/Native smoke test.wav'),
        );
        final result = await client.importFile(source) as Map;
        final bookId = result['bookId'] as String;
        await source.delete();
        final nested = Directory('${root.path}/nested');
        for (final name in [
          'Author/Book 2/CD 10/chapter1.wav',
          'Author/Book 2/CD 2/chapter99.wav',
          'Author/Book 10/chapter.wav',
        ]) {
          final file = File('${nested.path}/$name');
          await file.parent.create(recursive: true);
          await writeTestWav(file, seconds: name.contains('CD 2/') ? 2 : 3);
        }
        final planned = await client.importLibrary(nested.path, dryRun: true);
        expect(planned['books'], hasLength(2));
        final importedLibrary = await client.importLibrary(nested.path);
        expect(importedLibrary['complete'], isTrue);
        final nestedBooks = (await library.allBooks())
            .where((book) => book.id != bookId)
            .toList();
        expect(nestedBooks, hasLength(2));
        final discBook = nestedBooks.singleWhere(
          (book) => book.title == 'Book 2',
        );
        final discTracks = await db.tracksFor(discBook.id);
        expect(discTracks.map((track) => track.durationMs), [2000, 3000]);
        expect(discBook.totalDurationMs, 5000);
        for (final book in nestedBooks) {
          await library.deleteBook(book.id);
        }
        await nested.delete(recursive: true);
        await tester.pumpAndSettle();
        expect(find.textContaining('Native smoke test'), findsWidgets);
        await tester.tap(find.textContaining('Native smoke test').first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Bookmarks'), findsOneWidget);
        final book = (await db.getBook(bookId))!;
        expect(book.totalDurationMs, closeTo(12000, 100));
        final owned = File(AppDatabase.decodePaths(book.filePathsJson).single);
        expect(await owned.exists(), isTrue);
        await client.command('play', {'bookId': bookId});
        // Native AVFoundation position must advance, not merely report playing.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        expect(player.position.inMilliseconds, greaterThan(200));
        await tester.pump();
        final pauseButton = find.widgetWithIcon(FilledButton, Icons.pause);
        await tester.ensureVisible(pauseButton);
        await tester.tap(pauseButton);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect(player.playing, isFalse);
        final paused = player.position;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect((player.position - paused).inMilliseconds.abs(), lessThan(100));
        await client.command('seek', {'seconds': 4});
        expect(player.position.inMilliseconds, closeTo(4000, 100));
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        try {
          final seek = find.semantics.byLabel('Playback position');
          tester.semantics.decrease(seek);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();
          expect(player.position.inMilliseconds, closeTo(0, 100));
        } finally {
          semantics.dispose();
        }
        await client.command('seek', {'seconds': 4});
        await db.replaceChapters(bookId, [
          for (var i = 0; i < 2; i++)
            ChaptersCompanion.insert(
              id: 'native-chapter-$i',
              bookId: bookId,
              title: 'Chapter ${i + 1}',
              startMs: i * 6000,
              endMs: (i + 1) * 6000,
              filePath: Value(owned.path),
              trackIndex: const Value(0),
            ),
        ]);
        await playback.loadBook(bookId);
        await client.command('next-chapter');
        expect(player.position.inMilliseconds, closeTo(6000, 100));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Previous chapter'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect(player.position.inMilliseconds, closeTo(0, 100));
        await client.command('seek', {'seconds': 4});
        await client.command('speed', {'value': 1.5});
        expect(player.speed, 1.5);
        await client.command('bookmark', {'title': 'Native bookmark'});
        expect(
          (await db.bookmarksFor(bookId)).any(
            (b) => b.title == 'Native bookmark' && b.bookPositionMs == 4000,
          ),
          isTrue,
        );
        await client.command('book-edit', {
          'bookId': bookId,
          'changes': {
            'title': 'Native edited book',
            'series': 'Native saga',
            'seriesOrder': 2,
            'collection': 'Smoke tests',
          },
        });
        await tester.pumpAndSettle();
        expect(find.text('Native edited book'), findsWidgets);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit book details'));
        await tester.pumpAndSettle();
        final authorField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Author',
        );
        await tester.enterText(authorField, 'Native edited author');
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect((await db.getBook(bookId))!.author, 'Native edited author');
        await client.command('book-settings', {
          'bookId': bookId,
          'values': {'speed': 1.75, 'seekSeconds': 15},
        });
        expect(player.speed, 1.75);
        final second =
            await client.importFiles([owned], title: 'Queued native book')
                as Map;
        final secondId = second['bookId'] as String;
        await client.command('queue-add', {'bookId': secondId});
        final queued = await client.command('queue') as List;
        expect((queued.single as Map)['book']['id'], secondId);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Up next'));
        await tester.pumpAndSettle();
        expect(find.text('Queued native book'), findsOneWidget);
        await tester.tap(find.byTooltip('Remove from queue'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect(await db.queue(), isEmpty);
        Navigator.of(tester.element(find.text('Up next'))).pop();
        await tester.pumpAndSettle();
        await client.command('load', {'bookId': secondId});
        await tester.pumpAndSettle();
        expect(find.text('Queued native book'), findsWidgets);
        expect(player.speed, settings.playbackSpeed);
        await client.command('load', {'bookId': bookId});
        await tester.pumpAndSettle();
        expect(find.text('Native edited book'), findsWidgets);
        expect(player.speed, 1.75);
        await client.command('play');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await client.command('pause');
        expect(await db.historyFor(bookId), isNotEmpty);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await server.dispose();
        await playback.dispose();
        final savedPosition = (await db.getBook(bookId))!.lastPositionMs;
        await db.close();
        databaseClosed = true;
        final reopened = AppDatabase.forTesting(NativeDatabase(databaseFile));
        try {
          expect(
            (await reopened.getBook(bookId))!.lastPositionMs,
            savedPosition,
          );
          expect(await reopened.bookmarksFor(bookId), isNotEmpty);
          expect(await reopened.historyFor(bookId), isNotEmpty);
        } finally {
          await reopened.close();
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await server.dispose();
        if (!databaseClosed) {
          await playback.dispose();
          await db.close();
        }
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'native NAS connection UI, Keychain, HTTP download and audio import',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('crisper_native_nas_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final library = LibraryService(db, storageDirectory: () async => root);
      final secure = KeychainCredentialStore(
        key:
            'crisperplayer.test.remote.${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = RemoteLibraryService(library, credentials: secure);
      final fixture = await writeTestWav(File('${root.path}/fixture.wav'));
      final audio = await fixture.readAsBytes();
      final nas = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final url = 'http://127.0.0.1:${nas.port}/dav/';
      final releaseTransfer = Completer<void>();
      final ranges = <String?>[];
      nas.listen((request) async {
        try {
          if (request.method == 'PROPFIND') {
            request.response.statusCode = 207;
            request.response.write(
              '<multistatus xmlns="DAV:"><response><href>/dav/Book.wav</href><propstat><prop><displayname>Book.wav</displayname><resourcetype/></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>',
            );
          } else {
            final range = request.headers.value('range');
            ranges.add(range);
            final offset = range == null
                ? 0
                : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
            request.response.headers.set('etag', '"native-fixture-v1"');
            if (offset > 0) {
              request.response.statusCode = 206;
              request.response.headers.set(
                'content-range',
                'bytes $offset-${audio.length - 1}/${audio.length}',
              );
            }
            request.response.headers.contentLength = audio.length - offset;
            request.response.bufferOutput = false;
            final first = (offset + 65536).clamp(0, audio.length);
            request.response.add(audio.sublist(offset, first));
            await request.response.flush();
            await releaseTransfer.future;
            request.response.add(audio.sublist(first));
          }
          await request.response.close();
        } on IOException {
          /* The UI paused the first request. */
        } on StateError {
          /* The UI paused the first request. */
        }
      });
      try {
        // Command-line macOS launches can begin with the scheduler paused.
        // These UI tests explicitly drive the app as a foreground application.
        if (Platform.isMacOS) {
          debugPrint(
            'Native UI lifecycle: ${tester.binding.lifecycleState}, frames: ${tester.binding.framesEnabled}',
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [remoteLibraryProvider.overrideWith((ref) => service)],
            child: const MaterialApp(home: SyncSettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add server'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('WebDAV / NAS').last);
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Native NAS');
        await tester.enterText(fields.at(1), url);
        await tester.enterText(fields.at(2), 'test-user');
        await tester.enterText(fields.at(3), 'test-password');
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(find.text('Native NAS'), findsOneWidget);
        final stored = await secure.read();
        expect(stored, contains('test-user'));
        expect(stored, contains('test-password'));
        await tester.tap(find.text('Native NAS'));
        await tester.pumpAndSettle();
        expect(find.text('Book.wav'), findsOneWidget);
        await tester.tap(find.text('Book.wav'));
        for (var tick = 0; tick < 100 && service.downloadedBytes == 0; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(
          service.downloadedBytes,
          greaterThan(0),
          reason: 'Transfer state: ${service.status()}, requests: $ranges',
        );
        await tester.tap(find.text('Pause download'));
        releaseTransfer.complete();
        await tester.pumpAndSettle();
        expect(service.downloads.single.phase, 'paused');
        expect(await db.allBooks, isEmpty);
        await tester.tap(find.text('Downloads (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Resume download'));
        await tester.pumpAndSettle();
        expect(ranges.last, startsWith('bytes='));
        expect(service.downloads, isEmpty);
        final books = await db.allBooks;
        expect(books, hasLength(1));
        expect(books.single.totalDurationMs, closeTo(12000, 100));
        expect(await db.select(db.remoteLinks).get(), hasLength(1));
        expect(
          await File(
            (jsonDecode(books.single.filePathsJson) as List).single as String,
          ).readAsBytes(),
          audio,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!releaseTransfer.isCompleted) releaseTransfer.complete();
        await secure.delete();
        await nas.close(force: true);
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
