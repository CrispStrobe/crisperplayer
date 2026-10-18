import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:crisperplayer/models/playback_state.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [60, 180, 30]);
  });
  tearDown(() => h.dispose());

  test('play returns while audio plays and opens exactly one session',
      () async {
    await h.playback.loadBook('a');
    await h.playback.play().timeout(const Duration(seconds: 1));
    await h.flush();
    expect(h.backend.playing, isTrue);
    var rows = await h.db.historyFor('a');
    expect(rows, hasLength(1));
    expect(rows.single.endedAtMs, isNull);
    await h.playback.play();
    await h.flush();
    expect(await h.db.historyFor('a'), hasLength(1));
    h.backend.move(const Duration(seconds: 25));
    await h.playback.pause();
    await h.flush();
    rows = await h.db.historyFor('a');
    expect(rows.single.endedAtMs, isNotNull);
    expect(rows.single.startMs, 0);
    expect(rows.single.endMs, 25000);
    expect(h.backend.playing, isFalse);
  });
  test(
      'switching books saves and closes the old book before loading the new one',
      () async {
    await h.book('b', [90]);
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 42));
    await h.playback.loadBook('b');
    await h.flush();
    expect((await h.db.getBook('a'))!.lastPositionMs, 42000);
    final session = (await h.db.historyFor('a')).single;
    expect(session.endedAtMs, isNotNull);
    expect(session.endMs, 42000);
    expect(await h.db.historyFor('b'), isEmpty);
    expect(h.playback.currentBookId, 'b');
    expect(h.backend.playing, isFalse);
    await h.playback.play();
    await h.flush();
    expect(await h.db.historyFor('b'), hasLength(1));
  });
  test('backgrounding checkpoints progress without ending listening', () async {
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 20));
    await h.playback.handleAppPaused();
    expect(h.backend.playing, isTrue);
    expect((await h.db.historyFor('a')).single.endedAtMs, isNull);
    expect((await h.db.getBook('a'))!.lastPositionMs, 20000);
    h.backend.move(const Duration(seconds: 30));
    await h.playback.pause();
    await h.flush();
    expect((await h.db.historyFor('a')).single.endMs, 30000);
  });
  test('unequal durations drive seek, skip and book progress', () async {
    await h.playback.loadBook('a');
    await h.playback.seekBook(const Duration(seconds: 100));
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, const Duration(seconds: 40));
    expect(h.playback.bookPosition, const Duration(seconds: 100));
    expect((await h.db.getBook('a'))!.totalProgress, closeTo(100 / 270, .0001));
    await h.playback.seekBook(const Duration(seconds: 60));
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, Duration.zero);
    await h.playback.skipBack(10);
    expect(h.backend.currentIndex, 0);
    expect(h.backend.position, const Duration(seconds: 50));
    await h.playback.skipForward(30);
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, const Duration(seconds: 20));
    await h.playback.seekBook(const Duration(hours: 10));
    expect(h.backend.currentIndex, 2);
    expect(h.backend.position, const Duration(seconds: 30));
    await h.playback.seekBook(const Duration(seconds: -10));
    expect(h.backend.currentIndex, 0);
    expect(h.backend.position, Duration.zero);
  });
  test('rapid skip commands each advance from the last completed seek',
      () async {
    await h.playback.loadBook('a');
    await Future.wait([h.playback.skipForward(10), h.playback.skipForward(10)]);
    expect(h.backend.position, const Duration(seconds: 20));
  });
  test('chapter navigation selects the physical file', () async {
    await h.playback.loadBook('a');
    final chapters = await h.db.chaptersFor('a');
    await h.playback.seekChapter(chapters[2]);
    expect(h.backend.currentIndex, 2);
    expect(h.backend.position, Duration.zero);
  });
  test('completion persists progress, closes history and pauses the player',
      () async {
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 30), index: 2);
    h.backend.complete();
    await h.flush();
    expect(h.backend.playing, isFalse);
    expect((await h.db.getBook('a'))!.isFinished, isTrue);
    expect((await h.db.historyFor('a')).single.endedAtMs, isNotNull);
  });
  test(
      'bookmark opens its book and file, including a later track at position zero',
      () async {
    await h.book('b', [30, 90]);
    final id = await BookmarkService(h.db).addManual(
        bookId: 'b',
        filePath: '/b/1.mp3',
        position: Duration.zero,
        bookPosition: const Duration(seconds: 30));
    final bookmark =
        (await h.db.bookmarksFor('b')).firstWhere((b) => b.id == id);
    await h.playback.loadBook('a');
    await h.playback.seekBookmark(bookmark);
    expect(h.playback.currentBookId, 'b');
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, Duration.zero);
    await h.playback.loadBook('a');
    await h.playback.loadBook('b');
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, Duration.zero);
  });
  test('settings immediately update audio and disable automatic bookmarks',
      () async {
    await h.playback.loadBook('a');
    h.settings.playbackSpeed = 1.5;
    h.settings.skipSilence = true;
    h.settings.volume = .4;
    h.settings.seekSeconds = 10;
    h.settings.autoBookmarkEnabled = false;
    await h.flush();
    expect(h.backend.speed, 1.5);
    expect(h.backend.skipSilence, isTrue);
    expect(h.backend.volume, .4);
    await h.playback.seek(const Duration(seconds: 20));
    await h.playback.skipForward();
    expect(h.backend.position, const Duration(seconds: 30));
    await h.playback.pause();
    expect(await h.db.bookmarksFor('a'), isEmpty);
  });
  test('speed changes split history into sessions with correct speed',
      () async {
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    await h.playback.setSpeed(1.5);
    await h.flush();
    await h.playback.pause();
    await h.flush();
    final rows = await h.db.historyFor('a');
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.speed).toSet(), {1.0, 1.5});
    expect(rows.every((r) => r.endedAtMs != null), isTrue);
  });
  test('smart rewind operates across track boundaries after a long pause',
      () async {
    await h.playback.loadBook('a');
    await h.playback.seekBook(const Duration(seconds: 62));
    await h.playback.pause();
    h.clock = h.clock.add(const Duration(minutes: 2));
    await h.playback.play();
    await h.flush();
    expect(h.backend.currentIndex, 0);
    expect(h.backend.position, const Duration(seconds: 57));
  });
  test('failed load clears book identity and allows retry', () async {
    h.backend.failLoad = true;
    await expectLater(h.playback.loadBook('a'), throwsStateError);
    expect(h.playback.currentBookId, isNull);
    expect(h.playback.state.status, PlaybackStatus.error);
    h.backend.failLoad = false;
    await h.playback.loadBook('a');
    expect(h.playback.currentBookId, 'a');
  });
  test('deleting the active book stops playback and cascades metadata',
      () async {
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    await h.library.deleteBook('a');
    await h.flush();
    expect(h.backend.playing, isFalse);
    expect(h.playback.currentBookId, isNull);
    expect(await h.db.getBook('a'), isNull);
    expect(await h.db.tracksFor('a'), isEmpty);
    expect(await h.db.historyFor('a'), isEmpty);
  });
  test('resume preference controls startup restoration, without autoplay',
      () async {
    await (h.db.update(h.db.books)..where((t) => t.id.equals('a'))).write(
        BooksCompanion(
            lastPlayedAtMs: const Value(1),
            lastPositionFilePath: const Value('/a/1.mp3'),
            lastPositionMs: const Value(12000)));
    h.settings.resumeOnLaunch = false;
    await h.playback.restoreLastBook();
    expect(h.playback.currentBookId, isNull);
    h.settings.resumeOnLaunch = true;
    await h.playback.restoreLastBook();
    expect(h.playback.currentBookId, 'a');
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position, const Duration(seconds: 12));
    expect(h.backend.playing, isFalse);
  });
}
