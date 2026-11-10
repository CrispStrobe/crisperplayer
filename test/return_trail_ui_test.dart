import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:crisperplayer/widgets/bookmark_tile.dart';
import 'package:crisperplayer/widgets/return_trail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = Stopwatch()..start();
  bool interfaceReady() {
    if (find.byType(LinearProgressIndicator).evaluate().isNotEmpty)
      return false;
    final pause = find.byKey(const ValueKey('return-trail-pause'));
    if (pause.evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(pause).onPressed == null) {
      return false;
    }
    final start = find.byKey(const ValueKey('return-trail-start'));
    if (start.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(start).onPressed == null) {
      return false;
    }
    return true;
  }

  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  } while ((!ready() || !interfaceReady()) &&
      deadline.elapsed < const Duration(seconds: 5));
  expect(ready(), isTrue, reason: 'The real playback command must complete');
  expect(
    interfaceReady(),
    isTrue,
    reason: 'The trail interface must finish updating',
  );
  // Pump only the route animation, not minutes of fake time while SQLite is
  // working on the real event loop or a preview is waiting in the command queue.
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _close(WidgetTester tester, PlaybackHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  Object? closeError;
  harness.dispose().then(
    (_) => closed = true,
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  await _waitFor(tester, () => closed);
  expect(closeError, isNull);
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
          child: ReturnTrailCard(playback: harness.playback, bookId: 'trail'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('return-trail-card')));
  await tester.pump();
}

Future<void> _seedTrail(PlaybackHarness harness) async {
  final service = ReturnTrailService(harness.db);
  var at = harness.clock.millisecondsSinceEpoch;
  for (final interval in [(0, 20), (45, 65), (100, 160)]) {
    await service.record(
      bookId: 'trail',
      filePath: '/trail/0.mp3',
      startMs: interval.$1 * 1000,
      endMs: interval.$2 * 1000,
      heardAtMs: at,
    );
    at += 20000;
  }
  await harness.playback.seekBook(const Duration(seconds: 180));
}

void main() {
  testWidgets(
    'empty Return Trail is honest and scrolls at 200 percent text on a small phone',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = PlaybackHarness();
      await tester.runAsync(() async {
        await harness.init();
        await harness.book('trail', [240]);
        await harness.playback.loadBook('trail');
      });
      try {
        await _showCard(tester, harness, textScale: 2);
        await _waitFor(
          tester,
          () => find
              .textContaining('Your trail starts with your next listen')
              .evaluate()
              .isNotEmpty,
        );
        final explanation = find.textContaining(
          'Recording starts with this version',
        );
        await tester.ensureVisible(explanation);
        expect(explanation, findsOneWidget);
        expect(find.byKey(const ValueKey('return-trail-start')), findsNothing);
        expect(harness.playback.isReturnTrailActive, isFalse);
        expect(harness.backend.playing, isFalse);
        for (final seconds in [30, 60, 120]) {
          expect(
            find.byKey(ValueKey('return-trail-budget-$seconds')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byTooltip('Close Return Trail'));
        await tester.tap(find.byTooltip('Close Return Trail'));
        await tester.pumpAndSettle();
        expect(find.text('Return Trail'), findsOneWidget);
      } finally {
        await _close(tester, harness);
      }
    },
  );

  testWidgets(
    'real recorded passages preview at speed, play, pause, reopen and restore the protected place',
    (tester) async {
      final harness = PlaybackHarness();
      await tester.runAsync(() async {
        await harness.init();
        await harness.book('trail', [240]);
        await harness.playback.loadBook('trail');
        await harness.playback.setSpeed(2);
        await _seedTrail(harness);
      });
      try {
        await _showCard(tester, harness);
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('return-trail-start'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('3 passages to revisit'), findsOneWidget);
        expect(
          find.text('About 00:50 listening at 2.0× · 01:40 of original audio'),
          findsOneWidget,
        );
        expect(find.text('Track 1 · 00:00–00:20'), findsOneWidget);
        expect(find.text('Last played passage'), findsOneWidget);
        expect(find.textContaining('0.mp3 · 03:00'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-budget-30')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-budget-30')));
        await _waitFor(
          tester,
          () => find
              .text('About 00:30 listening at 2.0× · 01:00 of original audio')
              .evaluate()
              .isNotEmpty,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-start')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-start')));
        await _waitFor(
          tester,
          () => harness.playback.isReturnTrailActive && harness.backend.playing,
        );
        expect(harness.playback.returnTrailPlan!.anchor.positionMs, 180000);

        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-pause')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-pause')));
        await _waitFor(tester, () => !harness.backend.playing);
        expect(harness.playback.isReturnTrailActive, isTrue);
        expect(find.text('Resume trail'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('return-trail-pause')));
        await _waitFor(tester, () => harness.backend.playing);

        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-next')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-next')));
        await _waitFor(
          tester,
          () => harness.playback.returnTrailClipIndex == 1,
        );
        await tester.ensureVisible(find.byTooltip('Close Return Trail'));
        await tester.tap(find.byTooltip('Close Return Trail'));
        await tester.pumpAndSettle();
        expect(harness.playback.isReturnTrailActive, isTrue);
        expect(
          find.text('Catching up · passage 2 of 3'),
          findsOneWidget,
          reason: 'playing=${harness.backend.playing}, state=${harness.playback.state.status}, index=${harness.playback.returnTrailClipIndex}; text=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
        );
        expect(
          find.text('Your place is saved · open trail to return'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('return-trail-card')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-return')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-return')));
        await _waitFor(tester, () => !harness.playback.isReturnTrailActive);
        expect(harness.backend.position, const Duration(seconds: 180));
        expect(harness.backend.playing, isFalse);
        expect(
          find.text('Back at your saved place. Playback is paused.'),
          findsOneWidget,
        );

        // The saved anchor is also a durable, recognizable bookmark.
        final saved = await tester.runAsync(() async {
          final bookmarks = await harness.db.bookmarksFor('trail');
          return bookmarks.firstWhere(
            (bookmark) => bookmark.kind == 'return-trail',
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BookmarkTile(
                bookmark: saved!,
                onTap: () {},
                onDelete: () {},
                onEdit: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Return Trail saved place'), findsOneWidget);
        expect(find.byIcon(Icons.restore), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, harness);
      }
    },
  );

  testWidgets(
    'continue here adopts the replay position and a stale sheet cannot control another book',
    (tester) async {
      final harness = PlaybackHarness();
      await tester.runAsync(() async {
        await harness.init();
        await harness.book('trail', [240]);
        await harness.book('other', [180]);
        await harness.playback.loadBook('trail');
        await _seedTrail(harness);
      });
      try {
        await _showCard(tester, harness);
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('return-trail-start'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-start')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-start')));
        await _waitFor(
          tester,
          () => harness.playback.isReturnTrailActive && harness.backend.playing,
        );
        final replayPosition = harness.backend.position;
        await tester.ensureVisible(
          find.byKey(const ValueKey('return-trail-continue')),
        );
        await tester.tap(find.byKey(const ValueKey('return-trail-continue')));
        await _waitFor(
          tester,
          () =>
              !harness.playback.isReturnTrailActive && harness.backend.playing,
        );
        expect(harness.backend.position, replayPosition);
        expect(harness.backend.position, isNot(const Duration(seconds: 180)));
        expect(
          find.text('Continuing from this passage.'),
          findsOneWidget,
          reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '),
        );

        await tester.runAsync(() => harness.playback.loadBook('other'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('The playing book changed.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('return-trail-start')), findsNothing);
        expect(find.byKey(const ValueKey('return-trail-return')), findsNothing);
        expect(harness.playback.currentBookId, 'other');
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, harness);
      }
    },
  );
}
