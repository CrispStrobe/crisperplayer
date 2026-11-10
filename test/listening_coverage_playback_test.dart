import 'dart:io';

import 'package:crisperplayer/services/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [200]);
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

  Future<void> prepareReview() async {
    await h.playback.play();
    advance(40);
    await h.playback.seek(const Duration(seconds: 90));
    await h.playback.startReturnTrail();
  }

  test(
    'coverage flushes current playback and measures recorded union rather than resume position',
    () async {
      await h.playback.play();
      advance(20);
      await h.playback.seek(const Duration(seconds: 60));
      advance(20);

      final coverage = await h.playback.listeningCoverage();
      expect(coverage.bookId, 'a');
      expect(h.backend.position.inSeconds, 80);
      expect(h.backend.playing, isTrue);
      expect(coverage.playedMs, 40000);
      expect(coverage.durationMs, 200000);
      expect(coverage.fraction, closeTo(0.2, 0.000001));
      expect(coverage.tracks.single.played.map((r) => (r.startMs, r.endMs)), [
        (0, 20000),
        (60000, 80000),
      ]);
      expect(coverage.tracks.single.gaps.map((r) => (r.startMs, r.endMs)), [
        (20000, 60000),
        (80000, 200000),
      ]);
    },
  );

  test('ordinary replay overlap counts once in lifetime coverage', () async {
    await h.playback.play();
    advance(20);
    await h.playback.seek(const Duration(seconds: 10));
    advance(20);
    final coverage = await h.playback.listeningCoverage();
    expect(coverage.playedMs, 30000);
    expect(coverage.tracks.single.played.map((r) => (r.startMs, r.endMs)), [
      (0, 30000),
    ]);
  });

  test(
    'earliest playback survives more than 200 recent passages through the coordinator',
    () async {
      await h.book('long', [1000]);
      await h.playback.loadBook('long');
      await h.playback.play();
      advance(1);
      for (var i = 1; i <= 205; i++) {
        await h.playback.seek(Duration(seconds: i * 3));
        advance(1);
      }
      final coverage = await h.playback.listeningCoverage();
      expect(await h.db.playedPassagesFor('long'), hasLength(200));
      expect(
        (await h.db.playedPassagesFor('long')).every((p) => p.startMs > 0),
        isTrue,
      );
      expect(coverage.playedMs, 206000);
      expect(coverage.tracks.single.played, hasLength(206));
      expect(coverage.tracks.single.played.first.startMs, 0);
      expect(coverage.tracks.single.played.first.endMs, 1000);
    },
  );

  test(
    'paused and buffering decoder movement does not fill listening gaps',
    () async {
      await h.playback.play();
      advance(10);
      await h.playback.pause();
      advance(20, positionSeconds: 40);
      await h.playback.play();
      advance(10);
      h.backend.buffer();
      advance(20, positionSeconds: 90);
      h.backend.ready();
      advance(10);
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 30000);
      expect(coverage.tracks.single.played.map((r) => (r.startMs, r.endMs)), [
        (0, 10000),
        (40000, 50000),
        (90000, 100000),
      ]);
    },
  );

  test(
    'Return Trail review cannot expand or double-count lifetime coverage',
    () async {
      await prepareReview();
      final before = await h.playback.listeningCoverage();
      advance(10);
      final during = await h.playback.listeningCoverage();
      expect(h.playback.isReturnTrailActive, isTrue);
      expect(during.playedMs, before.playedMs);
      expect(during.tracks.single.played.map((r) => (r.startMs, r.endMs)), [
        (0, 40000),
      ]);
      await h.playback.finishReturnTrail();
      expect((await h.playback.listeningCoverage()).playedMs, 40000);
    },
  );

  test(
    'unknown file durations report recorded time without a fabricated whole-book percentage',
    () async {
      final paths = [
        for (var i = 0; i < 2; i++)
          (await File('${h.root.path}/unknown-$i.mp3').writeAsBytes([0])).path,
      ];
      await h.db.upsertBook(
        BooksCompanion.insert(
          id: 'unknown',
          title: 'Unknown duration',
          filePathsJson: AppDatabase.encodePaths(paths),
          addedAtMs: 0,
        ),
      );
      await h.db.replaceTracks('unknown', [
        for (var i = 0; i < 2; i++)
          BookTracksCompanion.insert(
            bookId: 'unknown',
            trackIndex: i,
            filePath: paths[i],
          ),
      ]);
      await h.playback.loadBook('unknown');
      await h.playback.play();
      advance(20);
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 20000);
      expect(coverage.durationMs, isNull);
      expect(coverage.fraction, isNull);
      expect(coverage.tracks.every((t) => t.fraction == null), isTrue);
      expect(coverage.tracks.every((t) => t.gaps.isEmpty), isTrue);
      expect(coverage.tracks.first.timelineExtentMs, 20000);
      await expectLater(
        h.playback.seekCoverage(
          bookId: 'unknown',
          filePath: paths.first,
          positionMs: 20001,
        ),
        throwsRangeError,
      );
      expect(h.backend.playing, isTrue);
      expect(h.backend.position.inMilliseconds, 20000);
      await h.playback.seekCoverage(
        bookId: 'unknown',
        filePath: paths.first,
        positionMs: 10000,
      );
      expect(h.backend.position.inMilliseconds, 10000);
      expect(h.backend.playing, isFalse);
      expect((await h.playback.listeningCoverage()).playedMs, 20000);
    },
  );

  test(
    'reading another book does not navigate or interrupt current playback',
    () async {
      await h.book('b', [100]);
      await h.playback.play();
      advance(10);
      final coverage = await h.playback.listeningCoverage(bookId: 'b');
      expect(coverage.bookId, 'b');
      expect(coverage.playedMs, 0);
      expect(h.playback.currentBookId, 'a');
      expect(h.backend.playing, isTrue);
      expect(h.backend.position.inSeconds, 10);
      expect((await h.playback.listeningCoverage()).playedMs, 10000);
    },
  );

  test(
    'map navigation pauses at the chosen point without marking its skipped path as played',
    () async {
      await h.playback.play();
      advance(20);
      await h.playback.seekCoverage(
        bookId: 'a',
        filePath: '/a/0.mp3',
        positionMs: 80000,
      );
      expect(h.backend.playing, isFalse);
      expect(h.backend.position.inMilliseconds, 80000);
      expect((await h.db.getBook('a'))!.lastPositionMs, 80000);
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 20000);
      expect(coverage.tracks.single.played.single.endMs, 20000);
    },
  );

  test(
    'deliberate map navigation exits Return Trail, preserves its bookmark and stays paused',
    () async {
      await prepareReview();
      await h.playback.seekCoverage(
        bookId: 'a',
        filePath: '/a/0.mp3',
        positionMs: 70000,
      );
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.playing, isFalse);
      expect(h.backend.position.inMilliseconds, 70000);
      expect((await h.db.getBook('a'))!.lastPositionMs, 70000);
      expect(
        (await h.db.bookmarksFor(
          'a',
        )).where((b) => b.kind == 'return-trail').single.positionMs,
        90000,
      );
      expect((await h.playback.listeningCoverage()).playedMs, 40000);
    },
  );

  test(
    'stale, missing-track and invalid-offset map requests leave active playback and review intact',
    () async {
      await h.book('b', [100]);
      await prepareReview();
      final plan = h.playback.returnTrailPlan;
      final originalPosition = h.backend.position;
      await expectLater(
        h.playback.seekCoverage(
          bookId: 'b',
          filePath: '/b/0.mp3',
          positionMs: 0,
        ),
        throwsStateError,
      );
      await expectLater(
        h.playback.seekCoverage(
          bookId: 'a',
          filePath: '/missing.mp3',
          positionMs: 0,
        ),
        throwsStateError,
      );
      await expectLater(
        h.playback.seekCoverage(
          bookId: 'a',
          filePath: '/a/0.mp3',
          positionMs: -1,
        ),
        throwsRangeError,
      );
      await expectLater(
        h.playback.seekCoverage(
          bookId: 'a',
          filePath: '/a/0.mp3',
          positionMs: 200001,
        ),
        throwsRangeError,
      );
      expect(h.playback.currentBookId, 'a');
      expect(h.playback.returnTrailPlan, same(plan));
      expect(h.backend.position, originalPosition);
      expect(h.backend.playing, isTrue);
      expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
      expect((await h.playback.listeningCoverage()).playedMs, 40000);
    },
  );

  test(
    'completion captures a plausible final decoder position without requiring another position event',
    () async {
      await h.playback.play();
      advance(199);
      h.clock = h.clock.add(const Duration(seconds: 1));
      h.backend.position = const Duration(seconds: 200);
      h.backend.complete();
      await h.flush();
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 200000);
      expect(coverage.fraction, 1);
      expect(coverage.tracks.single.gaps, isEmpty);
    },
  );

  test(
    'a plausible natural adjacent-track transition records the previous final second',
    () async {
      await h.book('multi', [20, 30]);
      await h.playback.loadBook('multi');
      await h.playback.play();
      advance(19);
      advance(1, positionSeconds: 0, index: 1);
      advance(10);
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 30000);
      expect(coverage.tracks.first.played.single.endMs, 20000);
      expect(coverage.tracks.first.gaps, isEmpty);
      expect(coverage.tracks[1].played.single.endMs, 10000);
    },
  );

  test(
    'seeking to the next file never records the unplayed tail of the previous file',
    () async {
      await h.book('multi', [20, 30]);
      await h.playback.loadBook('multi');
      await h.playback.play();
      advance(19);
      await h.playback.seekTrack(1);
      advance(5);
      final coverage = await h.playback.listeningCoverage();
      expect(coverage.playedMs, 24000);
      expect(coverage.tracks.first.played.single.endMs, 19000);
      expect(coverage.tracks.first.gaps.single.startMs, 19000);
      expect(coverage.tracks.first.gaps.single.endMs, 20000);
    },
  );
}
