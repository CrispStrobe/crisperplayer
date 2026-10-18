import 'dart:convert';
import 'package:crisperplayer/models/book_preferences.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_stats.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [60]);
    await h.book('b', [90]);
  });
  tearDown(() => h.dispose());

  test(
    'speed is remembered per book; app defaults and other books remain independent',
    () async {
      expect(BookPreferences.decode('{"speed":2}')['speed'], isA<double>());
    h.settings.playbackSpeed = 1.2;
      await h.playback.loadBook('a');
      await h.playback.setSpeed(1.75);
      expect(h.settings.playbackSpeed, 1.2);
      await h.playback.loadBook('b');
      expect(h.backend.speed, 1.2);
      await h.playback.loadBook('a');
      expect(h.backend.speed, 1.75);
      h.settings.volume = .4;
      await h.flush();
      expect(h.backend.speed, 1.75);
      await h.playback.updateBookPreferences('a', {}, reset: true);
      expect(h.backend.speed, 1.2);
      await h.playback.updateBookPreferences('a', {'speed': 2});
      await h.playback.updateBookPreferences('a', {'speed': null});
      expect(await h.library.preferences('a'), isEmpty);
      expect(h.backend.speed, 1.2);
    },
  );
  test(
    'per-book skip interval, silence and smart rewind override defaults',
    () async {
      await h.playback.loadBook('a');
      await h.playback.updateBookPreferences('a', {
        'seekSeconds': 15,
        'skipSilence': true,
        'smartRewindSeconds': 10,
        'smartRewindAfterSeconds': 30,
      });
      await h.playback.seekBook(const Duration(seconds: 20));
      await h.playback.skipForward();
      expect(h.backend.position.inSeconds, 35);
      expect(h.backend.skipSilence, isTrue);
      await h.playback.pause();
      h.clock = h.clock.add(const Duration(seconds: 31));
      await h.playback.play();
      expect(h.backend.position.inSeconds, 25);
      await h.playback.updateBookPreferences('a', {'smartRewindSeconds': 0});
      await h.playback.pause();
      h.clock = h.clock.add(const Duration(minutes: 2));
      await h.playback.play();
      expect(h.backend.position.inSeconds, 25);
      await expectLater(
        h.playback.updateBookPreferences('a', {'speed': double.nan}),
        throwsFormatException,
      );
      expect(
        () => BookPreferences.validate({'unknown': null}),
        throwsFormatException,
      );
    },
  );
  test(
    'queue ordering is persistent, unique and removed entries stay removed',
    () async {
      await h.playback.enqueue('a');
      await h.playback.enqueue('b');
      await h.playback.enqueue('b', position: 0);
      expect((await h.db.queue()).map((e) => e.bookId), ['b', 'a']);
      await h.playback.enqueue('b', position: 1);
      expect((await h.db.queue()).map((e) => e.bookId), ['a', 'b']);
      await h.playback.removeFromQueue('a');
      expect((await h.db.queue()).map((e) => e.bookId), ['b']);
      await h.playback.playNextQueued();
      await h.flush();
      expect(h.playback.currentBookId, 'b');
      expect(h.backend.playing, isTrue);
      expect(await h.db.queue(), isEmpty);
    },
  );
  test('completion advances to queued book and applies its settings', () async {
    await h.library.setPreferences('b', {'speed': 1.5});
    await h.playback.loadBook('a');
    await h.playback.enqueue('b');
    await h.playback.play();
    h.backend.move(const Duration(seconds: 60));
    h.backend.complete();
    await h.flush();
    expect(h.playback.currentBookId, 'b');
    expect(h.backend.playing, isTrue);
    expect(h.backend.speed, 1.5);
    expect(await h.db.queue(), isEmpty);
    expect((await h.db.getBook('a'))!.isFinished, isTrue);
  });
  test('sleep timer prevents automatic continuation at completion', () async {
    await h.playback.loadBook('a');
    await h.playback.enqueue('b');
    await h.playback.play();
    h.playback.setSleepTimer(const Duration(minutes: 5));
    h.backend.move(const Duration(seconds: 60));
    h.backend.complete();
    await h.flush();
    expect(h.playback.currentBookId, 'a');
    expect(h.backend.playing, isFalse);
    expect(await h.db.queue(), hasLength(1));
  });
  test('failed load keeps the queued entry', () async {
    await h.playback.enqueue('b');
    h.backend.failLoad = true;
    await expectLater(h.playback.playNextQueued(), throwsStateError);
    expect((await h.db.queue()).single.bookId, 'b');
  });
  test(
    'manual reading status survives flushes and unread keeps bookmarks',
    () async {
      await h.playback.loadBook('a');
      await h.playback.seekBook(const Duration(seconds: 12));
      await h.playback.addManualBookmark(title: 'Saved');
      await h.playback.markBook('a', 'finished');
      await h.flush();
      expect((await h.db.getBook('a'))!.isFinished, isTrue);
      expect((await h.db.getBook('a'))!.totalProgress, 1);
      await h.playback.markBook('a', 'unfinished');
      await h.flush();
      expect((await h.db.getBook('a'))!.isFinished, isFalse);
      expect((await h.db.getBook('a'))!.lastPositionMs, 12000);
      await h.playback.markBook('a', 'unread');
      await h.flush();
      final book = (await h.db.getBook('a'))!;
      expect(book.lastPositionMs, 0);
      expect(book.totalProgress, 0);
      expect(book.lastPlayedAtMs, isNull);
      expect(await h.db.bookmarksFor('a'), isNotEmpty);
    },
  );
  test('backup preserves series, collection, preferences and queue', () async {
    await h.library.editBook('a', {
      'series': 'Saga',
      'seriesOrder': 2,
      'collection': 'Favorites',
    });
    await h.library.setPreferences('a', {'speed': 1.75});
    await h.playback.enqueue('b');
    final backup = await h.db.exportAllJson();
    final copy = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      await copy.importAllJson(
        jsonDecode(jsonEncode(backup)) as Map<String, dynamic>,
      );
      final book = (await copy.getBook('a'))!;
      expect(book.series, 'Saga');
      expect(book.seriesOrder, 2);
      expect(book.collection, 'Favorites');
      expect(
        BookPreferences.decode(book.playbackPreferencesJson)['speed'],
        1.75,
      );
      expect((await copy.queue()).single.bookId, 'b');
      await copy.deleteBook('b');
      expect(await copy.queue(), isEmpty);
    } finally {
      await copy.close();
    }
  });
  test(
    'listening statistics split sessions at midnight and use actual listening time',
    () {
      final now = DateTime(2026, 10, 18, 1);
      final start = DateTime(2026, 10, 17, 23, 50);
      final entries = [
        ListeningHistoryData(
          id: 's',
          bookId: 'a',
          startedAtMs: start.millisecondsSinceEpoch,
          endedAtMs: start
              .add(const Duration(minutes: 20))
              .millisecondsSinceEpoch,
          startMs: 0,
          endMs: 2400000,
          listenedMs: 1200000,
          speed: 2,
        ),
      ];
      final stats = listeningStats(entries, now: now);
      expect(stats['todayMs'], 600000);
      expect(stats['weekMs'], 1200000);
      expect(stats['totalMs'], 1200000);
    },
  );
}
