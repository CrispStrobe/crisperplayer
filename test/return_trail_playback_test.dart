import 'dart:async';
import 'dart:io';

import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

class _FailingSeekBackend extends FakeAudioBackend {
  bool failSeek = false;
  bool completeDuringSeek = false;
  Completer<void>? seekGate;
  Completer<void>? seekEntered;

  @override
  Future<void> seek(Duration position, {int? index}) async {
    if (failSeek) throw StateError('Decoder seek failed');
    if (seekGate != null) {
      seekEntered?.complete();
      await seekGate!.future;
    }
    if (completeDuringSeek) complete();
    await super.seek(position, index: index);
  }
}

class _FailingSeekHarness extends PlaybackHarness {
  final _faultBackend = _FailingSeekBackend();

  @override
  _FailingSeekBackend get backend => _faultBackend;
}

Future<void> _seedTrail(PlaybackHarness h) async {
  await h.playback.loadBook('a');
  await h.playback.seekTrack(1, const Duration(seconds: 90));
  final tracks = await h.db.tracksFor('a');
  final store = ReturnTrailService(h.db);
  final now = h.clock.millisecondsSinceEpoch;
  await store.record(
    bookId: 'a',
    filePath: tracks[0].filePath,
    startMs: 20000,
    endMs: 50000,
    heardAtMs: now - 120000,
  );
  await store.record(
    bookId: 'a',
    filePath: tracks[1].filePath,
    startMs: 10000,
    endMs: 40000,
    heardAtMs: now - 60000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [120, 180]);
  });
  tearDown(() => h.dispose());

  test(
    'only real playing samples are persisted and commanded seeks leave gaps',
    () async {
      await h.playback.loadBook('a');
      h.backend.move(const Duration(seconds: 10));
      await h.flush();
      expect(await h.db.playedPassagesFor('a'), isEmpty);
      await h.playback.seek(Duration.zero);
      await h.playback.play();
      h.clock = h.clock.add(const Duration(seconds: 5));
      h.backend.move(const Duration(seconds: 5));
      await h.playback.seek(const Duration(seconds: 60));
      h.clock = h.clock.add(const Duration(seconds: 5));
      h.backend.move(const Duration(seconds: 65));
      await h.playback.pause();

      final passages = await h.db.playedPassagesFor('a');
      expect(passages.map((p) => (p.startMs, p.endMs)), [
        (60000, 65000),
        (0, 5000),
      ]);
      expect(passages.every((p) => p.filePath == '/a/0.mp3'), isTrue);
    },
  );

  test(
    'buffering resets evidence so decoder recovery cannot invent a passage',
    () async {
      await h.playback.loadBook('a');
      await h.playback.play();
      h.clock = h.clock.add(const Duration(seconds: 5));
      h.backend.move(const Duration(seconds: 5));
      h.backend.buffer();
      h.clock = h.clock.add(const Duration(seconds: 25));
      h.backend.move(const Duration(seconds: 30));
      h.backend.ready();
      h.clock = h.clock.add(const Duration(seconds: 5));
      h.backend.move(const Duration(seconds: 35));
      await h.playback.pause();
      expect(
        (await h.db.playedPassagesFor('a')).map((p) => (p.startMs, p.endMs)),
        [(30000, 35000), (0, 5000)],
      );
    },
  );

  test('preview leaves playback and saved place untouched', () async {
    await _seedTrail(h);
    await h.playback.play();
    final before = (await h.db.getBook('a'))!;
    final plan = await h.playback.previewReturnTrail(expectedBookId: 'a');
    expect(plan.clips, hasLength(2));
    expect(plan.anchor.filePath, '/a/1.mp3');
    expect(plan.anchor.positionMs, 90000);
    expect(h.playback.isReturnTrailActive, isFalse);
    expect(h.backend.playing, isTrue);
    expect(h.backend.position.inMilliseconds, 90000);
    expect((await h.db.getBook('a'))!.lastPositionMs, before.lastPositionMs);
    expect(await h.db.bookmarksFor('a'), isEmpty);
  });

  test(
    'replay, background checkpoint and pause preserve the durable return anchor',
    () async {
      await _seedTrail(h);
      final initialPassages = (await h.db.playedPassagesFor(
        'a',
      )).map((p) => p.toJson()).toList();
      await h.playback.startReturnTrail(expectedBookId: 'a');
      expect(h.playback.isReturnTrailActive, isTrue);
      expect(h.backend.currentIndex, 0);
      expect(h.backend.playing, isTrue);
      h.clock = h.clock.add(const Duration(seconds: 5));
      h.backend.move(const Duration(seconds: 25));
      await h.playback.handleAppLifecycleState(AppLifecycleState.paused);
      await h.playback.pause();

      final saved = (await h.db.getBook('a'))!;
      expect(saved.lastPositionFilePath, '/a/1.mp3');
      expect(saved.lastPositionMs, 90000);
      expect(await h.db.historyFor('a'), isEmpty);
      expect(
        (await h.db.playedPassagesFor('a')).map((p) => p.toJson()).toList(),
        initialPassages,
      );
      final bookmarks = await h.db.bookmarksFor('a');
      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.kind, 'return-trail');
      expect(bookmarks.single.filePath, '/a/1.mp3');
      expect(bookmarks.single.positionMs, 90000);
      expect(h.playback.isReturnTrailActive, isTrue);
    },
  );

  test(
    'disposing during a replay leaves original resume and recovery bookmark',
    () async {
      await _seedTrail(h);
      await h.playback.startReturnTrail();
      h.backend.move(const Duration(seconds: 24));
      await h.playback.dispose();
      final saved = (await h.db.getBook('a'))!;
      expect(saved.lastPositionFilePath, '/a/1.mp3');
      expect(saved.lastPositionMs, 90000);
      expect((await h.db.bookmarksFor('a')).single.positionMs, 90000);
    },
  );

  test(
    'return restores exact file-local position even with an unknown earlier duration',
    () async {
      final paths = [
        for (var i = 0; i < 2; i++)
          (await File('${h.root.path}/$i.mp3').writeAsBytes([0])).path,
      ];
      await (h.db.update(h.db.books)..where((b) => b.id.equals('a'))).write(
        BooksCompanion(filePathsJson: Value(AppDatabase.encodePaths(paths))),
      );
      await h.db.replaceTracks('a', [
        for (var i = 0; i < 2; i++)
          BookTracksCompanion.insert(
            bookId: 'a',
            trackIndex: i,
            filePath: paths[i],
          ),
      ]);
      await _seedTrail(h);
      expect(h.playback.bookDuration, isNull);
      await h.playback.startReturnTrail();
      h.backend.move(const Duration(seconds: 25));
      await h.playback.finishReturnTrail();
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position.inMilliseconds, 90000);
      expect(h.backend.playing, isFalse);
      expect((await h.db.getBook('a'))!.lastPositionFilePath, paths[1]);
    },
  );

  test(
    'last excerpt completion restores the anchor without consuming Up next',
    () async {
      await _seedTrail(h);
      await h.book('b', [60]);
      await h.db.replaceQueue(['b']);
      await h.playback.startReturnTrail();
      await h.playback.nextReturnTrailClip();
      h.backend.complete();
      await h.flush();
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.playback.currentBookId, 'a');
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position.inMilliseconds, 90000);
      expect(h.backend.playing, isFalse);
      expect((await h.db.queue()).map((q) => q.bookId), ['b']);
      expect((await h.db.getBook('a'))!.isFinished, isFalse);
    },
  );

  test(
    'duplicate start retains the original anchor and single recovery bookmark',
    () async {
      await _seedTrail(h);
      await h.playback.startReturnTrail();
      h.backend.move(const Duration(seconds: 25));
      await h.playback.startReturnTrail();
      expect(h.playback.returnTrailPlan!.anchor.positionMs, 90000);
      expect(h.playback.returnTrailPlan!.anchor.filePath, '/a/1.mp3');
      expect(await h.db.bookmarksFor('a'), hasLength(1));
    },
  );

  test(
    'explicit continue adopts only the chosen excerpt and starts normal playback',
    () async {
      await _seedTrail(h);
      await h.playback.startReturnTrail();
      h.backend.move(const Duration(seconds: 25));
      await h.playback.finishReturnTrail(continueHere: true);
      await h.flush();
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.currentIndex, 0);
      expect(h.backend.position.inMilliseconds, 25000);
      expect(h.backend.playing, isTrue);
      final saved = (await h.db.getBook('a'))!;
      expect(saved.lastPositionFilePath, '/a/0.mp3');
      expect(saved.lastPositionMs, 25000);
      expect((await h.db.bookmarksFor('a')).single.positionMs, 90000);
      expect(await h.db.historyFor('a'), hasLength(1));
    },
  );

  test(
    'sleep expiry pauses a replay and pending boundary events cannot resume it',
    () async {
      await _seedTrail(h);
      await h.playback.startReturnTrail();
      h.playback.setSleepTimer(const Duration(minutes: 1));
      h.clock = h.clock.add(const Duration(minutes: 2));
      await h.playback.handleAppLifecycleState(AppLifecycleState.resumed);
      await h.flush();
      expect(h.backend.playing, isFalse);
      h.backend.move(const Duration(seconds: 50));
      h.backend.complete();
      await h.flush();
      expect(h.backend.playing, isFalse);
      expect(h.playback.returnTrailClipIndex, 0);
      expect(h.playback.isReturnTrailActive, isTrue);
      expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    },
  );

  test('stale book requests cannot start or preview another book', () async {
    await _seedTrail(h);
    await h.book('b', [60]);
    await h.playback.loadBook('b');
    await expectLater(
      h.playback.previewReturnTrail(expectedBookId: 'a'),
      throwsStateError,
    );
    await expectLater(
      h.playback.startReturnTrail(expectedBookId: 'a'),
      throwsStateError,
    );
    expect(h.playback.currentBookId, 'b');
    expect(h.playback.isReturnTrailActive, isFalse);
    expect(await h.db.bookmarksFor('b'), isEmpty);
  });

  test(
    'invalid budgets and an empty trail do not create recovery bookmarks',
    () async {
      await h.playback.loadBook('a');
      await h.playback.play();
      await expectLater(
        h.playback.startReturnTrail(budget: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(h.backend.playing, isTrue);
      await expectLater(h.playback.startReturnTrail(), throwsStateError);
      expect(h.backend.playing, isTrue);
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(await h.db.bookmarksFor('a'), isEmpty);
    },
  );

  test(
    'marking the active book unread exits review before resetting its place',
    () async {
      await _seedTrail(h);
      await h.playback.startReturnTrail();
      await h.playback.markBook('a', 'unread');
      await h.flush();
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.currentIndex, 0);
      expect(h.backend.position, Duration.zero);
      expect(h.backend.playing, isFalse);
      final book = (await h.db.getBook('a'))!;
      expect(book.lastPositionMs, 0);
      expect(book.totalProgress, 0);
      expect(book.isFinished, isFalse);
      expect(
        (await h.db.bookmarksFor(
          'a',
        )).where((b) => b.kind == 'return-trail').single.positionMs,
        90000,
      );
    },
  );

  test(
    'an explicit bookmark navigation leaves review and adopts the chosen file',
    () async {
      await _seedTrail(h);
      await h.db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'chosen',
          bookId: 'a',
          title: 'Chosen passage',
          filePath: '/a/1.mp3',
          positionMs: 70000,
          bookPositionMs: 190000,
          createdAtMs: 1,
        ),
      );
      final chosen = (await h.db.bookmarksFor('a')).single;
      await h.playback.startReturnTrail();
      await h.playback.seekBookmark(chosen);
      await h.flush();
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position.inMilliseconds, 70000);
      expect((await h.db.getBook('a'))!.lastPositionMs, 70000);
    },
  );

  test('a failed excerpt seek retains a retryable protected anchor', () async {
    await h.dispose();
    final failing = _FailingSeekHarness();
    h = failing;
    await h.init();
    await h.book('a', [120, 180]);
    await _seedTrail(h);
    failing.backend.failSeek = true;
    await expectLater(h.playback.startReturnTrail(), throwsStateError);
    expect(h.playback.isReturnTrailActive, isTrue);
    expect(h.backend.playing, isFalse);
    expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    expect((await h.db.bookmarksFor('a')).single.positionMs, 90000);
    await expectLater(h.playback.finishReturnTrail(), throwsStateError);
    expect(h.playback.isReturnTrailActive, isTrue);
    expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    failing.backend.failSeek = false;
    await h.playback.finishReturnTrail();
    expect(h.playback.isReturnTrailActive, isFalse);
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position.inMilliseconds, 90000);
  });

  test(
    'Play after a failed seek retries the selected excerpt before emitting audio',
    () async {
      await h.dispose();
      final failing = _FailingSeekHarness();
      h = failing;
      await h.init();
      await h.book('a', [120, 180]);
      await _seedTrail(h);
      failing.backend.failSeek = true;
      await expectLater(h.playback.startReturnTrail(), throwsStateError);
      failing.backend.failSeek = false;
      await h.playback.play();
      expect(h.backend.currentIndex, 0);
      expect(h.backend.position.inMilliseconds, 20000);
      expect(h.backend.playing, isTrue);
      expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    },
  );

  test(
    'completion emitted during an excerpt seek cannot skip the new excerpt',
    () async {
      await h.dispose();
      final transitioning = _FailingSeekHarness();
      h = transitioning;
      await h.init();
      await h.book('a', [120, 180]);
      await _seedTrail(h);
      transitioning.backend.completeDuringSeek = true;
      await h.playback.startReturnTrail();
      await h.flush();
      expect(h.playback.isReturnTrailActive, isTrue);
      expect(h.playback.returnTrailClipIndex, 0);
      expect(h.backend.currentIndex, 0);
      expect(h.backend.position.inMilliseconds, 20000);
      expect(h.backend.playing, isTrue);

      await h.playback.nextReturnTrailClip();
      await h.flush();
      expect(h.playback.isReturnTrailActive, isTrue);
      expect(h.playback.returnTrailClipIndex, 1);
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position.inMilliseconds, 10000);
      expect(h.backend.playing, isTrue);
      expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    },
  );

  test(
    'pause requested during a pending excerpt seek prevents automatic resume',
    () async {
      await h.dispose();
      final delayed = _FailingSeekHarness();
      h = delayed;
      await h.init();
      await h.book('a', [120, 180]);
      await _seedTrail(h);
      final gate = Completer<void>();
      final entered = Completer<void>();
      delayed.backend.seekGate = gate;
      delayed.backend.seekEntered = entered;
      final starting = h.playback.startReturnTrail();
      await entered.future;
      final pausing = h.playback.pause();
      gate.complete();
      await starting;
      await pausing;
      delayed.backend.seekGate = null;
      delayed.backend.seekEntered = null;
      expect(h.playback.isReturnTrailActive, isTrue);
      expect(h.backend.playing, isFalse);
      expect((await h.db.getBook('a'))!.lastPositionMs, 90000);
    },
  );
}
