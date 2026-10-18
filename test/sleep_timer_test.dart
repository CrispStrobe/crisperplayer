import 'package:flutter_test/flutter_test.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [120]);
    await h.playback.loadBook('a');
  });
  tearDown(() => h.dispose());
  test(
      'chapter sleep stops at captured boundary even after entering the next chapter',
      () async {
    await h.db.replaceChapters('a', [
      ChaptersCompanion.insert(
          id: 'c1', bookId: 'a', title: 'First', startMs: 0, endMs: 60000),
      ChaptersCompanion.insert(
          id: 'c2',
          bookId: 'a',
          title: 'Second',
          startMs: 60000,
          endMs: 120000),
    ]);
    // Reload to obtain current metadata, then run the real position listener.
    await h.playback.loadBook('a');
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 59));
    h.playback.setSleepTimer(Duration.zero, endOfChapter: true);
    expect(h.playback.isWaitingForChapterEnd, isTrue);
    h.backend.move(const Duration(milliseconds: 60500));
    await h.flush();
    expect(h.backend.playing, isFalse);
    expect(h.playback.isWaitingForChapterEnd, isFalse);
    expect((await h.db.historyFor('a')).single.endedAtMs, isNotNull);
  });
  test('chapter sleep survives automatic physical track transition', () async {
    await h.book('b', [60, 90]);
    await h.playback.loadBook('b');
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 59));
    h.playback.setSleepTimer(Duration.zero, endOfChapter: true);
    h.backend.move(Duration.zero, index: 1);
    await h.flush();
    expect(h.backend.playing, isFalse);
  });
  test('timer expiry pauses through production pause and persists progress',
      () async {
    await h.playback.play();
    await h.flush();
    h.backend.move(const Duration(seconds: 20));
    h.playback.setSleepTimer(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await h.flush();
    expect(h.backend.playing, isFalse);
    expect(h.playback.sleepRemaining, Duration.zero);
    expect((await h.db.getBook('a'))!.lastPositionMs, 20000);
    expect((await h.db.historyFor('a')).single.endedAtMs, isNotNull);
  });
  test('cancel prevents pause and switching books cancels a pending timer',
      () async {
    await h.playback.play();
    await h.flush();
    h.playback.setSleepTimer(Duration.zero, endOfChapter: true);
    h.playback.cancelSleepTimer();
    h.backend.move(const Duration(seconds: 120));
    await h.flush();
    expect(h.backend.playing, isTrue);
    h.playback.setSleepTimer(const Duration(minutes: 10));
    await h.book('b', [60]);
    await h.playback.loadBook('b');
    expect(h.playback.sleepRemaining, Duration.zero);
    expect(h.playback.sleepEndOfChapter, isFalse);
  });
}
