import 'dart:io';

import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
import 'package:crisperplayer/widgets/journal_export_button.dart';
import 'package:crisperplayer/widgets/listening_coverage_sheet.dart';
import 'package:crisperplayer/widgets/listening_journal_view.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  } while ((!ready() ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty) &&
      elapsed.elapsed < const Duration(seconds: 10));
  expect(ready(), isTrue, reason: 'The real journal operation must complete');
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _close(WidgetTester tester, PlaybackHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var done = false;
  Object? error;
  h.dispose().then(
    (_) => done = true,
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await _wait(tester, () => done);
  expect(error, isNull);
}

Future<String> _book(PlaybackHarness h, String id) async {
  final path = (await File('${h.root.path}/$id.mp3').writeAsBytes([0])).path;
  await h.db.upsertBook(
    BooksCompanion.insert(
      id: id,
      title: id == 'map' ? 'The remembered journey' : 'Another book',
      filePathsJson: AppDatabase.encodePaths([path]),
      addedAtMs: 0,
      totalDurationMs: const Value(120000),
    ),
  );
  await h.db.replaceTracks(id, [
    BookTracksCompanion.insert(
      bookId: id,
      trackIndex: 0,
      filePath: path,
      durationMs: const Value(120000),
    ),
  ]);
  return path;
}

Future<void> _played(
  PlaybackHarness h,
  String path,
  int id,
  DateTime date, {
  int startMs = 10000,
  int endMs = 70000,
  String? reason,
}) => ListeningJournalService(h.db).recordPlayed(
  id: _id(id),
  bookId: 'map',
  filePath: path,
  startMs: startMs,
  endMs: endMs,
  startedAtMs: date.millisecondsSinceEpoch,
  endedAtMs: date.millisecondsSinceEpoch + endMs - startMs,
  utcOffsetMinutes: date.timeZoneOffset.inMinutes,
  reason: reason,
);

Widget _app(Widget body, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

Finder _scrollable(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(Scrollable),
);

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  String scroll = 'listening-journal-scroll',
}) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: _scrollable(scroll),
    maxScrolls: 80,
  );
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester) async {
  tester
      .state<ScrollableState>(_scrollable('listening-journal-scroll'))
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'map opens dated play-throughs without seeking and explicit resume stays paused',
    (tester) async {
      final h = PlaybackHarness();
      late String path;
      await tester.runAsync(() async {
        await h.init();
        path = await _book(h, 'map');
        await _played(h, path, 1, DateTime(2025, 11, 10, 10));
        await _played(
          h,
          path,
          2,
          DateTime(2026, 11, 9, 10),
          startMs: 45000,
          endMs: 65000,
          reason: 'return_trail',
        );
        // A seek at the selected point must not appear as playback evidence.
        await ListeningJournalService(h.db).recordEvent(
          id: _id(3),
          bookId: 'map',
          kind: 'seek',
          filePath: path,
          positionMs: 60000,
          targetFilePath: path,
          targetPositionMs: 90000,
          atMs: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
          utcOffsetMinutes: 0,
        );
        await ReturnTrailService(h.db).record(
          bookId: 'map',
          filePath: path,
          startMs: 0,
          endMs: 90000,
          heardAtMs: h.clock.millisecondsSinceEpoch,
        );
        await h.playback.loadBook('map');
        await h.playback.seek(const Duration(seconds: 20));
        await h.playback.play();
      });
      try {
        await tester.pumpWidget(
          _app(ListeningCoverageSheet(playback: h.playback, bookId: 'map')),
        );
        final timeline = find.byKey(
          const ValueKey('listening-coverage-timeline-0'),
        );
        await _wait(tester, () => timeline.evaluate().isNotEmpty);
        await _reveal(tester, timeline, scroll: 'listening-coverage-scroll');
        await tester.tapAt(tester.getRect(timeline).center);
        await tester.pump();
        final dates = find.byKey(const ValueKey('listening-coverage-dates-0'));
        await _reveal(tester, dates, scroll: 'listening-coverage-scroll');
        await tester.tap(dates);
        await _wait(
          tester,
          () => find.byType(ListeningJournalView).evaluate().isNotEmpty,
        );
        final view = tester.widget<ListeningJournalView>(
          find.byType(ListeningJournalView),
        );
        expect(view.initialPassage!.positionMs, 60000);
        expect(view.initialPassage!.filePath, path);
        expect(find.text('When you played this passage'), findsOneWidget);
        expect(h.backend.position, const Duration(seconds: 20));
        expect(h.backend.playing, isTrue);
        expect(h.settings.listeningJournalEnabled, isFalse);
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(2)}')));
        expect(find.text('Return Trail replay'), findsOneWidget);
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.text('Played'), findsOneWidget);
        expect(find.byKey(ValueKey('journal-entry-${_id(3)}')), findsNothing);
        final open = find.byKey(ValueKey('journal-open-${_id(1)}-end'));
        await _reveal(tester, open);
        await tester.tap(open);
        await _wait(tester, () => h.backend.position.inSeconds == 70);
        expect(h.backend.playing, isFalse);
        final bookmarks = await tester.runAsync(() => h.db.bookmarksFor('map'));
        expect(
          bookmarks!
              .singleWhere((b) => b.title == 'Before journal jump')
              .positionMs,
          20000,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ListeningJournalView), findsNothing);
        expect(find.text('Selected: track 1 · 01:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'passage lookup composes date and export filters and changing books clears it',
    (tester) async {
      final h = PlaybackHarness();
      late String path;
      await tester.runAsync(() async {
        await h.init();
        path = await _book(h, 'map');
        final otherPath = await _book(h, 'other');
        await _played(h, path, 1, DateTime(2025, 11, 10, 10));
        await _played(h, path, 2, DateTime(2026, 11, 10, 10));
        await ListeningJournalService(h.db).recordEvent(
          id: _id(3),
          bookId: 'other',
          kind: 'pause',
          filePath: otherPath,
          positionMs: 5000,
          atMs: DateTime(2025, 11, 10, 11).millisecondsSinceEpoch,
          utcOffsetMinutes: 0,
        );
      });
      final passage = JournalPassageFilter.point(
        bookId: 'map',
        filePath: path,
        positionMs: 60000,
      );
      try {
        await tester.pumpWidget(
          _app(
            ListeningJournalView(
              playback: h.playback,
              settings: h.settings,
              initialPassage: passage,
              initialPassageLabel: 'Track 1',
              now: () => DateTime(2026, 11, 10, 12),
            ),
          ),
        );
        await _wait(
          tester,
          () => find.byType(JournalExportButton).evaluate().isNotEmpty,
        );
        final year = find.byKey(const ValueKey('journal-dates-yearAgo'));
        await _reveal(tester, year);
        await tester.tap(year);
        await _wait(
          tester,
          () => find.text('Nov 10, 2025').evaluate().isNotEmpty,
        );
        await _reveal(tester, find.byType(JournalExportButton));
        final export = tester.widget<JournalExportButton>(
          find.byType(JournalExportButton),
        );
        expect(export.passage, passage);
        expect(export.bookId, 'map');
        expect(export.fromUtcMs, DateTime(2025, 11, 10).millisecondsSinceEpoch);
        expect(
          export.beforeUtcMs,
          DateTime(2025, 11, 11).millisecondsSinceEpoch,
        );
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.byKey(ValueKey('journal-entry-${_id(2)}')), findsNothing);
        await _top(tester);
        final bookFilter = find.byKey(
          const ValueKey('journal-book-filter-map'),
        );
        await _reveal(tester, bookFilter);
        await tester.tap(bookFilter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Another book').last);
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('journal-book-filter-other'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.byKey(const ValueKey('journal-passage-filter')),
          findsNothing,
        );
        await _reveal(tester, find.byType(JournalExportButton));
        final changed = tester.widget<JournalExportButton>(
          find.byType(JournalExportButton),
        );
        expect(changed.passage, isNull);
        expect(changed.bookId, 'other');
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(3)}')));
        expect(find.text('Paused'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'empty passage lookup stays honest and scrolls at 200 percent text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = PlaybackHarness();
      late String path;
      await tester.runAsync(() async {
        await h.init();
        path = await _book(h, 'map');
        await _played(h, path, 1, DateTime(2025, 11, 10, 10));
      });
      try {
        await tester.pumpWidget(
          _app(
            ListeningJournalView(
              playback: h.playback,
              settings: h.settings,
              initialPassage: JournalPassageFilter.range(
                bookId: 'map',
                filePath: path,
                startMs: 90000,
                endMs: 120000,
              ),
              initialPassageLabel: 'Track 1',
            ),
            textScale: 2,
          ),
        );
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('journal-passage-filter'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Track 1 · 01:30–02:00'), findsOneWidget);
        final empty = find.byKey(const ValueKey('journal-empty'));
        await _reveal(tester, empty);
        expect(
          find.textContaining('does not prove the passage was never played'),
          findsOneWidget,
        );
        await _top(tester);
        final clear = find.byKey(const ValueKey('journal-clear-passage'));
        await _reveal(tester, clear);
        await tester.tap(clear);
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('journal-passage-filter'))
              .evaluate()
              .isEmpty,
        );
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.text('Played'), findsOneWidget);
        expect(h.settings.listeningJournalEnabled, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );
}
