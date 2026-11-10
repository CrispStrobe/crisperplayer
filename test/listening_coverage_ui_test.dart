import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:crisperplayer/widgets/listening_coverage_sheet.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  } while ((!ready() ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty) &&
      deadline.elapsed < const Duration(seconds: 5));
  expect(ready(), isTrue, reason: 'The real map update must complete');
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _close(WidgetTester tester, PlaybackHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  Object? error;
  harness.dispose().then(
    (_) => closed = true,
    onError: (Object e) {
      error = e;
      closed = true;
    },
  );
  await _waitFor(tester, () => closed);
  expect(error, isNull);
}

Future<void> _showCard(
  WidgetTester tester,
  PlaybackHarness harness, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListeningCoverageCard(
            playback: harness.playback,
            bookId: 'map',
          ),
        ),
      ),
    ),
  );
  await _waitFor(
    tester,
    () => find.textContaining('recorded').evaluate().isNotEmpty,
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('listening-coverage-card')));
  await _waitFor(
    tester,
    () => find
        .byKey(const ValueKey('listening-coverage-summary'))
        .evaluate()
        .isNotEmpty,
  );
}

Finder _scrollable() => find.descendant(
  of: find.byKey(const ValueKey('listening-coverage-scroll')),
  matching: find.byType(Scrollable),
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _scrollable());
  await tester.pump();
}

Future<void> _record(PlaybackHarness harness, int track, int from, int to) =>
    ReturnTrailService(harness.db).record(
      bookId: 'map',
      filePath: '/map/$track.mp3',
      startMs: from * 1000,
      endMs: to * 1000,
      heardAtMs: harness.clock.millisecondsSinceEpoch,
    );

void main() {
  testWidgets('map percentages and subsecond gaps keep exact boundaries', (
    tester,
  ) async {
    final h = PlaybackHarness();
    await tester.runAsync(() async {
      await h.init();
      await h.book('map', [100]);
      await h.playback.loadBook('map');
      final store = ReturnTrailService(h.db);
      for (final interval in [(0, 10001), (10501, 29500)]) {
        await store.record(
          bookId: 'map',
          filePath: '/map/0.mp3',
          startMs: interval.$1,
          endMs: interval.$2,
          heardAtMs: h.clock.millisecondsSinceEpoch,
        );
      }
    });
    try {
      await _showCard(tester, h);
      expect(find.text('00:29 played · 29% recorded'), findsOneWidget);
      await _open(tester);
      final gaps = find.byKey(const ValueKey('listening-coverage-gaps-0'));
      await _reveal(tester, gaps);
      await tester.tap(gaps);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('00:10.001–00:10.501'));
      expect(
        find.text('500 milliseconds without recorded playback'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets(
    'map follows the unique union and inspecting or seeking does not fill gaps',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await h.book('map', [120, 120]);
        await h.book('other', [120]);
        await h.playback.loadBook('map');
        await _record(h, 0, 0, 30);
        await _record(h, 0, 60, 90);
        await _record(h, 1, 30, 60);
        await h.playback.seekTrack(0, const Duration(seconds: 10));
        await h.playback.play();
      });
      try {
        await _showCard(tester, h);
        expect(find.text('01:30 played · 37% recorded'), findsOneWidget);
        await tester.runAsync(() => _record(h, 0, 10, 40));
        await _waitFor(
          tester,
          () => find.text('01:40 played · 41% recorded').evaluate().isNotEmpty,
        );
        await _open(tester);
        expect(find.text('No playback recorded'), findsOneWidget);
        expect(find.textContaining('Older listening'), findsOneWidget);
        final timeline = find.byKey(
          const ValueKey('listening-coverage-timeline-0'),
        );
        await _reveal(tester, timeline);
        final rect = tester.getRect(timeline);
        await tester.tapAt(rect.center);
        await tester.pump();
        expect(find.text('Selected: track 1 · 01:00'), findsOneWidget);
        expect(h.backend.position, const Duration(seconds: 10));
        expect(h.backend.playing, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(find.text('Selected: track 1 · 01:30'), findsOneWidget);
        expect(h.backend.position, const Duration(seconds: 10));
        final jump = find.byKey(const ValueKey('listening-coverage-jump-0'));
        await _reveal(tester, jump);
        await tester.tap(jump);
        await _waitFor(
          tester,
          () => find
              .text('Opened at 01:30. Playback is paused.')
              .evaluate()
              .isNotEmpty,
        );
        expect(h.backend.position, const Duration(seconds: 90));
        expect(h.backend.playing, isFalse);
        final coverage = await tester.runAsync(
          () => h.playback.listeningCoverage(),
        );
        expect(coverage!.playedMs, 100000);
        final painted = tester.widget<ListeningCoverageTimeline>(timeline);
        expect(painted.playheadMs, 90000);
        expect(painted.playedMs, 70000);

        await tester.runAsync(() async {
          await h.playback.loadBook('other');
          await h.playback.play();
        });
        await tester.pump();
        expect(tester.widget<FilledButton>(jump).onPressed, isNull);
        expect(h.playback.currentBookId, 'other');
        expect(h.backend.playing, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'next gap previews and wraps clearly, and jumping ends Return Trail paused',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await h.book('map', [120]);
        await h.playback.loadBook('map');
        await _record(h, 0, 0, 20);
        await _record(h, 0, 40, 80);
        await h.playback.seekTrack(0, const Duration(seconds: 110));
      });
      try {
        await _showCard(tester, h);
        await _open(tester);
        final next = find.byKey(const ValueKey('listening-coverage-next-gap'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('listening-coverage-selected-header')),
          findsOneWidget,
        );
        expect(find.text('Selected: track 1 · 01:50'), findsWidgets);
        expect(h.backend.position, const Duration(seconds: 110));
        await tester.tap(next);
        await tester.pump();
        expect(find.text('Wrapped to an earlier gap.'), findsWidgets);
        expect(find.text('Selected: track 1 · 00:20'), findsWidgets);
        expect(h.backend.position, const Duration(seconds: 110));
        await tester.runAsync(
          () => h.playback.startReturnTrail(expectedBookId: 'map'),
        );
        await tester.pump();
        expect(
          find.text('Jump here ends Return Trail and opens this point paused.'),
          findsWidgets,
        );
        final jump = find.byKey(
          const ValueKey('listening-coverage-jump-header'),
        );
        await tester.ensureVisible(jump);
        await tester.tap(jump);
        await _waitFor(
          tester,
          () => find
              .text('Opened at 00:20. Playback is paused.')
              .evaluate()
              .isNotEmpty,
        );
        expect(h.playback.isReturnTrailActive, isFalse);
        expect(h.backend.position, const Duration(seconds: 20));
        expect(h.backend.playing, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'unknown durations stay honest and the map scrolls at 200 percent text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await h.book('map', [120]);
        await h.playback.loadBook('map');
        await _record(h, 0, 20, 40);
        await _record(h, 0, 60, 80);
        await (h.db.update(h.db.bookTracks)
              ..where((track) => track.bookId.equals('map')))
            .write(const BookTracksCompanion(durationMs: Value(null)));
      });
      try {
        await _showCard(tester, h, textScale: 2);
        expect(
          find.text('00:40 recorded · total length unknown'),
          findsOneWidget,
        );
        await _open(tester);
        expect(
          find.byKey(const ValueKey('listening-coverage-next-gap')),
          findsNothing,
        );
        final timeline = find.byKey(
          const ValueKey('listening-coverage-timeline-0'),
        );
        await _reveal(tester, timeline);
        expect(find.text('00:40 played · end unknown'), findsOneWidget);
        expect(
          find.text('Recorded through 01:20 · end unknown'),
          findsOneWidget,
        );
        expect(find.textContaining('%'), findsNothing);
        final widget = tester.widget<ListeningCoverageTimeline>(timeline);
        expect(widget.extentMs, 80000);
        expect(widget.durationKnown, isFalse);
        final semantics = tester.ensureSemantics();
        try {
          final node = tester.getSemantics(
            find.bySemanticsLabel('Track 1 listening map'),
          );
          expect(node.getSemanticsData().value, contains('Track end unknown'));
          tester.semantics.increase(
            find.semantics.byLabel('Track 1 listening map'),
          );
          await tester.pump();
          expect(find.text('Selected: track 1 · 00:30'), findsOneWidget);
          expect(h.backend.position, Duration.zero);
        } finally {
          semantics.dispose();
        }
        await _reveal(
          tester,
          find.byKey(const ValueKey('listening-coverage-jump-0')),
        );
        // A decoder can discover the length later. The same live map then
        // exposes exact gaps, whose expanded controls must also fit large text.
        await tester.runAsync(
          () =>
              (h.db.update(h.db.bookTracks)
                    ..where((track) => track.bookId.equals('map')))
                  .write(const BookTracksCompanion(durationMs: Value(120000))),
        );
        final gaps = find.byKey(const ValueKey('listening-coverage-gaps-0'));
        await _waitFor(tester, () => gaps.evaluate().isNotEmpty);
        await _reveal(tester, gaps);
        await tester.tap(gaps);
        await tester.pumpAndSettle();
        await _reveal(tester, find.text('00:00–00:20'));
        expect(find.text('00:00–00:20'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );
}
