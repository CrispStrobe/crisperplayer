import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/services/audio/listening_journal_recorder.dart';
import 'package:crisperplayer/services/audio/played_range_recorder.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;

  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [100, 100, 100]);
    await h.playback.loadBook('a');
  });
  tearDown(() => h.dispose());

  void advance(int seconds, {int? positionSeconds, int? index}) {
    h.clock = h.clock.add(Duration(seconds: seconds));
    h.backend.move(
      Duration(
        seconds: positionSeconds ?? h.backend.position.inSeconds + seconds,
      ),
      index: index,
    );
  }

  Future<List<ListeningJournalEntry>> entries() async =>
      (await h.playback.listeningJournal(limit: 200)).entries;

  test(
    'journal is opt-in, while existing cumulative coverage still records',
    () async {
      expect(h.settings.listeningJournalEnabled, isFalse);
      await h.playback.play();
      advance(20);
      await h.playback.pause();
      expect(await entries(), isEmpty);
      expect((await h.playback.listeningCoverage()).playedMs, 20000);
    },
  );

  test(
    'live opt-in starts now and opt-out retains only the consent window',
    () async {
      await h.playback.play();
      advance(10);
      await h.playback.setListeningJournalEnabled(true);
      final enabledAt = h.clock.millisecondsSinceEpoch;
      advance(20);
      await h.playback.setListeningJournalEnabled(false);
      final disabledAt = h.clock.millisecondsSinceEpoch;
      advance(15);
      await h.playback.pause();
      final played = (await entries()).where((entry) => entry.isPlayed).single;
      expect((played.startMs, played.endMs), (10000, 30000));
      expect((played.startedAtMs, played.endedAtMs), (enabledAt, disabledAt));
      expect(h.settings.listeningJournalEnabled, isFalse);
      await h.playback.setListeningJournalEnabled(true);
      expect((await entries()).where((entry) => entry.isPlayed), hasLength(1));
    },
  );

  test(
    'dated replays stay separate and explicit jumps retain both endpoints',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(20);
      await h.playback.seek(const Duration(seconds: 10));
      advance(10);
      await h.playback.nextChapter();
      advance(5);
      await h.playback.pause();
      final all = await entries();
      final played = all.where((entry) => entry.isPlayed).toList()
        ..sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
      expect(
        played.map((entry) => (entry.filePath, entry.startMs, entry.endMs)),
        [
          ('/a/0.mp3', 0, 20000),
          ('/a/0.mp3', 10000, 20000),
          ('/a/1.mp3', 0, 5000),
        ],
      );
      expect(played.map((entry) => entry.id).toSet(), hasLength(3));
      final chapterJump = all.singleWhere(
        (entry) => entry.reason == 'next_chapter',
      );
      expect(chapterJump.kind, 'seek');
      expect((chapterJump.filePath, chapterJump.startMs), ('/a/0.mp3', 20000));
      expect(
        (chapterJump.targetFilePath, chapterJump.targetPositionMs),
        ('/a/1.mp3', 0),
      );
      expect(chapterJump.chapterTitle, 'Chapter 0');
      final pause = all.singleWhere((entry) => entry.kind == 'pause');
      expect((pause.filePath, pause.startMs), ('/a/1.mp3', 5000));
      expect((await h.playback.listeningCoverage()).playedMs, 25000);
    },
  );

  test(
    'periodic reads extend one passage and do not create checkpoint rows',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(1);
      final first = (await entries()).singleWhere((entry) => entry.isPlayed);
      h.clock = h.clock.add(const Duration(milliseconds: 100));
      await entries(); // Same decoder position, later wall-clock observation.
      for (var i = 2; i <= 12; i++) {
        h.clock = DateTime(2026).add(Duration(seconds: i));
        h.backend.move(Duration(seconds: i));
        await entries();
      }
      final last = (await entries()).singleWhere((entry) => entry.isPlayed);
      expect(last.id, first.id);
      expect((last.startMs, last.endMs), (0, 12000));
      expect(last.elapsedMs, 12000);
    },
  );

  test(
    'passage reads and complete snapshots capture live evidence without moving playback',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(20);
      final snapshot = await h.playback.listeningJournalSnapshot(
        passage: JournalPassageFilter.point(
          bookId: 'a',
          filePath: '/a/0.mp3',
          positionMs: 19999,
        ),
      );
      expect(snapshot, hasLength(1));
      expect(snapshot.single.isPlayed, isTrue);
      expect((snapshot.single.startMs, snapshot.single.endMs), (0, 20000));
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(h.backend.playing, isTrue);
      expect(h.backend.position.inSeconds, 20);
      advance(5);
      final page = await h.playback.listeningJournal(
        passage: JournalPassageFilter.range(
          bookId: 'a',
          filePath: '/a/0.mp3',
          startMs: 22000,
          endMs: 23000,
        ),
      );
      expect(page.entries.single.id, snapshot.single.id);
      expect(page.entries.single.endMs, 25000);
      expect(snapshot.single.endMs, 20000);
      expect(h.backend.playing, isTrue);
      expect(h.backend.position.inSeconds, 25);
      final whole = await h.playback.listeningJournalSnapshot(bookId: 'a');
      expect(whole.where((entry) => entry.kind == 'play'), hasLength(1));
      expect(whole.where((entry) => entry.isPlayed), hasLength(1));
    },
  );

  test(
    'speed, pause and buffer boundaries preserve separate real intervals',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(10);
      await h.playback.setSpeed(2, expectedBookId: 'a');
      advance(5, positionSeconds: 20);
      await h.playback.pause();
      h.clock = h.clock.add(const Duration(hours: 1));
      await h.playback.play();
      advance(5, positionSeconds: 25); // Smart rewind opens at 15 first.
      h.backend.buffer();
      advance(10, positionSeconds: 60);
      h.backend.ready();
      advance(5, positionSeconds: 70);
      final played = (await entries()).where((entry) => entry.isPlayed).toList()
        ..sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
      expect(played.map((entry) => (entry.startMs, entry.endMs, entry.speed)), [
        (0, 10000, 1.0),
        (10000, 20000, 2.0),
        (15000, 25000, 2.0),
        (60000, 70000, 2.0),
      ]);
      expect(played[0].elapsedMs, 10000);
      expect(played[1].elapsedMs, 5000);
      expect(
        (await entries()).any((entry) => entry.reason == 'smart_rewind'),
        isTrue,
      );
    },
  );

  test(
    'Return Trail replays have dates but do not expand normal coverage',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(40);
      await h.playback.seek(const Duration(seconds: 80));
      await h.playback.startReturnTrail();
      final clip = h.playback.returnTrailPlan!.clips.first;
      advance(5, positionSeconds: clip.startMs ~/ 1000 + 5);
      await h.playback.finishReturnTrail();
      final replays = (await entries()).where(
        (entry) => entry.isPlayed && entry.reason == 'return_trail',
      );
      expect(replays, hasLength(1));
      expect(replays.single.mediaDurationMs, 5000);
      expect(
        (await entries()).any(
          (entry) => entry.kind == 'seek' && entry.reason == 'return_trail',
        ),
        isTrue,
      );
      final returned = (await entries()).singleWhere(
        (entry) =>
            entry.kind == 'seek' && entry.reason == 'return_trail_return',
      );
      expect(returned.targetPositionMs, 80000);
      expect(h.backend.position.inSeconds, 80);
      expect((await h.playback.listeningCoverage()).playedMs, 40000);
    },
  );

  test(
    'a year-old stop can be reopened paused with a bookmark of the current place',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      final beginning = h.clock;
      await h.playback.play();
      advance(25);
      await h.playback.pause();
      h.clock = DateTime(2027, 1, 1, 12);
      await h.book('b', [200]);
      await h.playback.loadBook('b');
      await h.playback.play();
      advance(50);
      final page = await h.playback.listeningJournal(
        bookId: 'a',
        fromUtcMs: beginning.millisecondsSinceEpoch,
        beforeUtcMs: DateTime(2026, 1, 2).millisecondsSinceEpoch,
      );
      final stop = page.entries.singleWhere((entry) => entry.kind == 'pause');
      final bookmarkId = await h.playback.resumeJournalPosition(
        bookId: stop.bookId,
        filePath: stop.filePath,
        positionMs: stop.startMs,
      );
      expect(h.playback.currentBookId, 'a');
      expect(h.backend.position.inSeconds, 25);
      expect(h.backend.playing, isFalse);
      final bookmark = (await h.db.bookmarksFor(
        'b',
      )).singleWhere((entry) => entry.id == bookmarkId);
      expect(bookmark.title, 'Before journal jump');
      expect(bookmark.positionMs, 50000);
      h.clock = h.clock.add(const Duration(minutes: 10));
      await h.playback.play();
      expect(
        h.backend.position.inSeconds,
        25,
      ); // Explicit target is not rewound.
    },
  );

  test(
    'invalid historic destinations do not disturb active playback',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(20);
      await expectLater(
        h.playback.resumeJournalPosition(
          bookId: 'a',
          filePath: '/missing.mp3',
          positionMs: 0,
        ),
        throwsStateError,
      );
      await expectLater(
        h.playback.resumeJournalPosition(
          bookId: 'a',
          filePath: '/a/0.mp3',
          positionMs: 100001,
        ),
        throwsRangeError,
      );
      expect(h.backend.playing, isTrue);
      expect(h.backend.position.inSeconds, 20);
      expect(
        (await h.db.bookmarksFor(
          'a',
        )).where((entry) => entry.title == 'Before journal jump'),
        isEmpty,
      );
      await expectLater(
        h.playback.setSpeed(1.5, expectedBookId: 'other'),
        throwsStateError,
      );
      expect(h.backend.speed, 1);
      await expectLater(h.playback.setSpeed(double.nan), throwsArgumentError);
      expect(h.backend.speed, 1);
    },
  );

  test(
    'clearing while playing starts fresh and cannot resurrect earlier checkpoints',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(20);
      await entries();
      await h.playback.clearListeningJournal();
      expect(await entries(), isEmpty);
      advance(10);
      final played = (await entries()).singleWhere((entry) => entry.isPlayed);
      expect((played.startMs, played.endMs), (20000, 30000));
      await h.playback.pause();
      await h.db.clearAllHistory();
      expect(await entries(), isEmpty);
    },
  );

  test(
    'natural source completion includes final audio and explicit completion',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(99);
      advance(1, positionSeconds: 0, index: 1);
      advance(10);
      final all = await entries();
      expect(
        all
            .where((entry) => entry.isPlayed && entry.filePath == '/a/0.mp3')
            .single
            .endMs,
        100000,
      );
      expect(
        all
            .where((entry) => entry.isPlayed && entry.filePath == '/a/1.mp3')
            .single
            .startMs,
        0,
      );
      await h.playback.seekTrack(2, const Duration(seconds: 99));
      h.clock = h.clock.add(const Duration(seconds: 1));
      h.backend.position = const Duration(seconds: 100);
      h.backend.complete();
      final end = await entries();
      expect(end.where((entry) => entry.kind == 'complete'), hasLength(1));
      expect(
        end
            .where((entry) => entry.isPlayed && entry.filePath == '/a/2.mp3')
            .single
            .endMs,
        100000,
      );
    },
  );

  test('unknown duration resume requires a recorded physical offset', () async {
    await h.playback.setListeningJournalEnabled(true);
    await (h.db.update(h.db.bookTracks)
          ..where((track) => track.bookId.equals('a')))
        .write(const BookTracksCompanion(durationMs: Value(null)));
    await h.playback.play();
    advance(10);
    await h.playback.pause();
    await h.playback.resumeJournalPosition(
      bookId: 'a',
      filePath: '/a/0.mp3',
      positionMs: 5000,
    );
    expect(h.backend.position.inSeconds, 5);
    await expectLater(
      h.playback.resumeJournalPosition(
        bookId: 'a',
        filePath: '/a/0.mp3',
        positionMs: 11000,
      ),
      throwsStateError,
    );
    expect(h.backend.position.inSeconds, 5);
  });

  test(
    'clearing all history pauses and cannot revive deleted sessions or passages',
    () async {
      await h.playback.setListeningJournalEnabled(true);
      await h.playback.play();
      advance(20);
      await entries();
      await h.playback.clearListeningHistory();
      expect(h.backend.playing, isFalse);
      await h.flush();
      expect(await entries(), isEmpty);
      expect(await h.db.historyFor('a'), isEmpty);
      expect(await h.db.playedPassagesFor('a'), isEmpty);
      expect((await h.playback.listeningCoverage()).playedMs, 0);
      await h.playback.play();
      advance(10);
      await h.playback.pause();
      final played = (await entries()).singleWhere((entry) => entry.isPlayed);
      expect((played.startMs, played.endMs), (20000, 30000));
      expect((await h.playback.listeningCoverage()).playedMs, 10000);
      expect(await h.db.historyFor('a'), hasLength(1));
    },
  );

  test('journal retention exceeds the recent 200-passage buffer', () async {
    await h.playback.setListeningJournalEnabled(true);
    await h.playback.play();
    for (var i = 0; i < 206; i++) {
      await h.playback.seek(Duration(seconds: i.isEven ? 0 : 5));
      advance(1);
    }
    await h.playback.pause();
    final rows = await h.db.select(h.db.listeningJournal).get();
    expect(rows.where((entry) => entry.kind == 'played'), hasLength(206));
    expect(await h.db.playedPassagesFor('a'), hasLength(200));
    final page = await ListeningJournalService(h.db).page(limit: 200);
    expect(page.nextCursor, isNotNull);
  });

  test(
    'acknowledging an older journal checkpoint preserves newer samples and stable ID',
    () {
      final recorder = ListeningJournalRecorder();
      final samples = PlayedRangeRecorder(retainPending: false);
      void sample(int position, int time) {
        final range = samples.sample(
          bookId: 'a',
          filePath: '/a/0.mp3',
          positionMs: position,
          observedAtMs: time,
          speed: 1,
        );
        if (range != null) {
          recorder.record(range, speed: 1, utcOffsetMinutes: 60);
        }
      }

      sample(0, 0);
      sample(1000, 1000);
      final saving = recorder.pending.single;
      sample(1000, 1100);
      sample(2000, 2000);
      recorder.acknowledge(saving);
      expect(recorder.pending.single.id, saving.id);
      expect(recorder.pending.single.endMs, 2000);
      recorder.acknowledge(recorder.pending.single);
      expect(recorder.pending, isEmpty);
      sample(3000, 3000);
      expect(recorder.pending.single.id, saving.id);
      expect(recorder.pending.single.startMs, 0);
    },
  );
}
