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
        await db.replaceChapters(bookId, [
          for (var i = 0; i < 2; i++)
            ChaptersCompanion.insert(id: 'native-chapter-$i', bookId: bookId,
              title: 'Chapter ${i + 1}', startMs: i * 6000, endMs: (i + 1) * 6000,
              filePath: Value(owned.path), trackIndex: const Value(0)),
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
}
