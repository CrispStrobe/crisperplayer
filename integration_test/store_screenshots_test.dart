import 'package:crisperplayer/services/audio/waveform_service.dart';
import 'dart:io';
import 'package:crisperplayer/main.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/audio_fixture.dart';

/// Captures actual production screens with imported, generated test audio.
/// No remote credentials, personal library or copyrighted audiobook is used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture real store screens with isolated sample library', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('crisper-store-');
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${root.path}/library.sqlite')),
    );
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs)..onboardingDone = true;
    final library = LibraryService(db, storageDirectory: () async => root);
    final bookmarks = BookmarkService(db);
    final playback = PlaybackService(
      db: db,
      library: library,
      bookmarks: bookmarks,
      history: HistoryService(db),
      settings: settings,
      audioPlayer: AudioPlayer(handleInterruptions: false),
    );
    final out = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/StoreScreenshots',
    );
    await out.create(recursive: true);
    var captured = 0;
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      const endpoint = String.fromEnvironment('STORE_SCREENSHOT_URL');
      if (endpoint.isEmpty) {
        await File(
          '${out.path}/$name.png',
        ).writeAsBytes(await binding.takeScreenshot(name));
      } else {
        final base = Uri.parse(endpoint);
        if (base.scheme != 'http' || base.host != '127.0.0.1') {
          throw StateError('Screenshot receiver must be loopback');
        }
        final http = HttpClient();
        try {
          final request = await http.postUrl(base.resolve('/screenshot/$name'));
          final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
          if (response.statusCode != 204) {
            throw StateError('Screenshot capture failed');
          }
          await response.drain<void>();
        } finally {
          http.close(force: true);
        }
      }
      captured++;
    }

    try {
      await playback.init();
      await playback.setVolume(0);
      final sources = <String>[];
      for (final name in [
        '01 Arrival',
        '02 The signal',
        '03 Under the stars',
      ]) {
        final file = await writeTestWav(
          File('${root.path}/$name.wav'),
          seconds: 90,
        );
        sources.add(file.path);
      }
      final first = (await library.importFiles(
        sources,
        title: 'The Quiet Observatory',
        author: 'CrispStrobe',
      ))!;
      await library.editBook(first, {
        'series': 'Night Stories',
        'seriesOrder': 1,
        'collection': 'Evening listening',
      });
      await library.importFiles(
        [sources.first],
        title: 'Letters from the Coast',
        author: 'CrispStrobe',
      );
      await library.importFiles(
        [sources.last],
        title: 'A Walk Beyond the Pines',
        author: 'CrispStrobe',
      );
      final tracks = await db.tracksFor(first);
      await library.updateProgress(
        first,
        tracks.first.filePath,
        const Duration(seconds: 32),
        const Duration(seconds: 32),
        const Duration(seconds: 270),
      );
      await bookmarks.addManual(
        bookId: first,
        filePath: tracks.first.filePath,
        position: const Duration(seconds: 18),
        bookPosition: const Duration(seconds: 18),
        title: 'The first signal',
        note: 'Return to this passage.',
      );
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
      await capture('01-library');
      await tester.tap(find.text('The Quiet Observatory').first);
      await tester.pumpAndSettle();
      await WaveformService.shared.generate(
        tracks.first.filePath,
        const Duration(seconds: 90),
      );
      await capture('02-player');
      await tester.ensureVisible(find.text('Show all chapters'));
      await tester.tap(find.text('Show all chapters'));
      await tester.pumpAndSettle();
      await capture('03-chapters');
      Navigator.of(tester.element(find.text('Show all chapters'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      await capture('04-bookmarks');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      await capture('05-sleep-timer');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(captured, 5);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.dispose();
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
