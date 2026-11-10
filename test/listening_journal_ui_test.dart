import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/history_screen.dart';
import 'package:crisperplayer/screens/settings_screen.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/listening_journal_service.dart';
import 'package:crisperplayer/theme/app_theme.dart';
import 'package:crisperplayer/widgets/listening_journal_view.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

Future<void> _close(
  WidgetTester tester,
  PlaybackHarness h, {
  bool providerOwnsSettings = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var done = false;
  var stage = 'playback';
  Object? error;
  () async {
    await h.playback.dispose();
    stage = 'database';
    await h.db.close();
    stage = 'settings';
    if (!providerOwnsSettings) h.settings.dispose();
    stage = 'directory';
    await h.root.delete(recursive: true);
  }().then(
    (_) => done = true,
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  final elapsed = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    // Drift defers cancelled watch-query removal with Timer.run. Advance the
    // fake clock as well as the real SQLite event loop before closing its DB.
    await tester.pump(const Duration(milliseconds: 1));
  } while (!done && elapsed.elapsed < const Duration(seconds: 5));
  expect(done, isTrue, reason: 'Cleanup blocked at $stage');
  expect(error, isNull);
}

Future<void> _book(PlaybackHarness h, String id, String title) async {
  final paths = [
    for (var i = 0; i < 2; i++)
      (await File('${h.root.path}/$id-$i.mp3').writeAsBytes([0])).path,
  ];
  await h.db.upsertBook(
    BooksCompanion.insert(
      id: id,
      title: title,
      filePathsJson: AppDatabase.encodePaths(paths),
      addedAtMs: 0,
      totalDurationMs: const Value(600000),
    ),
  );
  await h.db.replaceTracks(id, [
    for (var i = 0; i < 2; i++)
      BookTracksCompanion.insert(
        bookId: id,
        trackIndex: i,
        filePath: paths[i],
        durationMs: const Value(300000),
      ),
  ]);
  await h.db.replaceChapters(id, [
    for (var i = 0; i < 2; i++)
      ChaptersCompanion.insert(
        id: '$id-$i',
        bookId: id,
        title: i == 0 ? 'The journey begins' : 'A different direction',
        startMs: i * 300000,
        endMs: (i + 1) * 300000,
        filePath: Value(paths[i]),
        trackIndex: Value(i),
      ),
  ]);
}

Future<void> _event(
  PlaybackHarness h,
  int id,
  DateTime when, {
  String bookId = 'a',
  String kind = 'pause',
  int positionMs = 25000,
  String? reason,
}) async {
  final tracks = await h.db.tracksFor(bookId);
  await ListeningJournalService(h.db).recordEvent(
    id: _id(id),
    bookId: bookId,
    kind: kind,
    filePath: tracks[0].filePath,
    positionMs: positionMs,
    atMs: when.millisecondsSinceEpoch,
    utcOffsetMinutes: when.timeZoneOffset.inMinutes,
    targetFilePath: kind == 'seek' ? tracks[1].filePath : null,
    targetPositionMs: kind == 'seek' ? 120000 : null,
    reason: reason,
    chapterTitle: 'The journey begins',
  );
}

Future<void> _played(
  PlaybackHarness h,
  int id,
  DateTime when, {
  String? reason,
}) async {
  final track = (await h.db.tracksFor('a')).first;
  await ListeningJournalService(h.db).recordPlayed(
    id: _id(id),
    bookId: 'a',
    filePath: track.filePath,
    startMs: 10000,
    endMs: 40000,
    startedAtMs: when.millisecondsSinceEpoch,
    endedAtMs: when.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    utcOffsetMinutes: when.timeZoneOffset.inMinutes,
    reason: reason,
    chapterTitle: 'The journey begins',
    speed: 1.25,
  );
}

Future<void> _show(
  WidgetTester tester,
  PlaybackHarness h, {
  DateTime? now,
  double textScale = 1,
  GlobalKey? captureKey,
  ThemeData? theme,
  JournalPassageFilter? passage,
}) async {
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Listening journal')),
      body: ListeningJournalView(
        playback: h.playback,
        settings: h.settings,
        now: () => now ?? DateTime(2026, 11, 10, 15),
        initialPassage: passage,
        initialPassageLabel: 'Track 1',
      ),
    ),
  );
  if (captureKey != null) app = RepaintBoundary(key: captureKey, child: app);
  await tester.pumpWidget(app);
  await _wait(
    tester,
    () =>
        find.byKey(const ValueKey('journal-date-range')).evaluate().isNotEmpty,
  );
}

Finder _scrollable() => find.descendant(
  of: find.byKey(const ValueKey('listening-journal-scroll')),
  matching: find.byType(Scrollable),
);

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double step = 400,
}) async {
  await tester.scrollUntilVisible(
    target,
    step,
    scrollable: _scrollable(),
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(_scrollable());
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'journal is opt-in and turning recording off preserves existing entries',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _event(h, 1, DateTime(2025, 11, 10, 9, 30));
      });
      try {
        await _show(tester, h);
        final toggle = find.byKey(const ValueKey('journal-recording-switch'));
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.tap(toggle);
        await _wait(tester, () => h.settings.listeningJournalEnabled);
        await tester.tap(toggle);
        await _wait(tester, () => !h.settings.listeningJournalEnabled);
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.text('Paused'), findsOneWidget);
        expect(
          (await tester.runAsync(
            () => ListeningJournalService(h.db).page(),
          ))!.entries,
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'date and book filters retrieve year-old entries without including adjacent days',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _book(h, 'b', 'A Book of Small Wonders');
        await _event(h, 1, DateTime(2025, 11, 10, 9, 30));
        await _event(
          h,
          2,
          DateTime(2025, 11, 10, 10),
          bookId: 'b',
          kind: 'stop',
        );
        await _event(h, 3, DateTime(2025, 11, 9, 10), kind: 'play');
        await _event(h, 4, DateTime(2026, 11, 10, 10), kind: 'complete');
      });
      try {
        await _show(tester, h);
        await tester.tap(find.byKey(const ValueKey('journal-dates-yearAgo')));
        await _wait(
          tester,
          () => find.text('Nov 10, 2025').evaluate().isNotEmpty,
        );
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(2)}')));
        expect(find.text('Stopped'), findsOneWidget);
        expect(find.byKey(ValueKey('journal-entry-${_id(4)}')), findsNothing);
        await _top(tester);
        await _reveal(
          tester,
          find.byKey(const ValueKey('journal-book-filter-all')),
        );
        await tester.tap(find.byKey(const ValueKey('journal-book-filter-all')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('The Long Way Home').last);
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('journal-book-filter-a'))
              .evaluate()
              .isNotEmpty,
        );
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.text('Paused'), findsOneWidget);
        expect(find.text('Stopped'), findsNothing);
        expect(find.text('Started playback'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets('A year ago clamps leap day to the previous February 28', (
    tester,
  ) async {
    final h = PlaybackHarness();
    await tester.runAsync(() async {
      await h.init();
      await _book(h, 'a', 'The Long Way Home');
      await _event(h, 1, DateTime(2027, 2, 28, 12));
      await _event(h, 2, DateTime(2027, 3, 1, 12), kind: 'stop');
    });
    try {
      await _show(tester, h, now: DateTime(2028, 2, 29, 12));
      await tester.tap(find.byKey(const ValueKey('journal-dates-yearAgo')));
      await _wait(
        tester,
        () => find.text('Feb 28, 2027').evaluate().isNotEmpty,
      );
      await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Stopped'), findsNothing);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets('cursor pagination reaches old entries beyond the first 50', (
    tester,
  ) async {
    final h = PlaybackHarness();
    await tester.runAsync(() async {
      await h.init();
      await _book(h, 'a', 'The Long Way Home');
      for (var i = 1; i <= 55; i++) {
        await _event(h, i, DateTime(2025, 11, 10, 10, i), positionMs: i * 1000);
      }
    });
    try {
      await _show(tester, h);
      final load = find.byKey(const ValueKey('journal-load-more'));
      await _reveal(tester, load, step: 2000);
      await tester.tap(load);
      await _wait(tester, () => find.text('Loading…').evaluate().isEmpty);
      await _reveal(
        tester,
        find.byKey(ValueKey('journal-entry-${_id(1)}')),
        step: 1000,
      );
      expect(find.byKey(ValueKey('journal-entry-${_id(1)}')), findsOneWidget);
      expect(load, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets(
    'explicit jumps show both positions and open a historical destination paused with recovery',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _book(h, 'b', 'A Book of Small Wonders');
        await h.playback.loadBook('b');
        await h.playback.seek(const Duration(seconds: 42));
        await _event(
          h,
          1,
          DateTime(2025, 11, 10, 9),
          kind: 'seek',
          reason: 'next_chapter',
        );
      });
      try {
        await _show(tester, h);
        await _reveal(
          tester,
          find.byKey(ValueKey('journal-open-${_id(1)}-to')),
        );
        expect(find.text('Jumped to the next chapter'), findsOneWidget);
        expect(find.textContaining('From: Track 1'), findsOneWidget);
        expect(find.textContaining('To: Track 2'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('journal-open-${_id(1)}-to')));
        await _wait(
          tester,
          () =>
              h.playback.currentBookId == 'a' &&
              h.backend.position.inSeconds == 120,
        );
        expect(h.backend.currentIndex, 1);
        expect(h.backend.playing, isFalse);
        await _reveal(
          tester,
          find.textContaining('Your previous place is saved'),
        );
        final recovery = (await tester.runAsync(
          () => h.db.bookmarksFor('b'),
        ))!.where((bookmark) => bookmark.title == 'Before journal jump').single;
        expect(recovery.positionMs, 42000);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'played rows distinguish Return Trail repeats from ordinary playback',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _played(h, 1, DateTime(2025, 11, 10, 9));
        await _played(h, 2, DateTime(2025, 11, 10, 10), reason: 'return_trail');
      });
      try {
        await _show(tester, h);
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(2)}')));
        expect(find.text('Return Trail replay'), findsOneWidget);
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(1)}')));
        expect(find.text('Played'), findsOneWidget);
        expect(find.textContaining('30 seconds of audio'), findsWidgets);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'clear asks explicitly and removes all dates even while a date filter is active',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _event(h, 1, DateTime(2025, 11, 10, 9));
        await _event(h, 2, DateTime(2026, 11, 10, 9));
      });
      try {
        await _show(tester, h);
        await tester.tap(find.byKey(const ValueKey('journal-dates-yearAgo')));
        await _wait(
          tester,
          () => find.text('Nov 10, 2025').evaluate().isNotEmpty,
        );
        final clear = find.byKey(const ValueKey('journal-clear'));
        await _reveal(tester, clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.textContaining('every book and date'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(
            () => ListeningJournalService(h.db).page(),
          ))!.entries,
          hasLength(2),
        );
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('journal-confirm-clear')));
        await _wait(
          tester,
          () => find.text('Listening journal cleared').evaluate().isNotEmpty,
        );
        expect(
          (await tester.runAsync(
            () => ListeningJournalService(h.db).page(),
          ))!.entries,
          isEmpty,
        );
        expect(h.settings.listeningJournalEnabled, isFalse);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'journal controls and rows fit a small phone at 200% text with accessible actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await _book(h, 'a', 'The Long Way Home: A Very Long Audiobook Title');
        await _event(
          h,
          1,
          DateTime(2025, 11, 10, 9),
          kind: 'seek',
          reason: 'skip_forward',
        );
      });
      try {
        await _show(tester, h, textScale: 2);
        expect(tester.takeException(), isNull);
        final semantics = tester.ensureSemantics();
        try {
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await _reveal(
            tester,
            find.byKey(ValueKey('journal-open-${_id(1)}-to')),
            step: 200,
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await _top(tester);
          final clear = find.byKey(const ValueKey('journal-clear'));
          await _reveal(tester, clear, step: 200);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'History exposes Journal and Sessions, and Settings uses the same optional recording control',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(h.init);
      try {
        Widget providerApp(Widget screen) => ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(h.db),
            playbackProvider.overrideWithValue(h.playback),
            settingsProvider.overrideWith((ref) => h.settings),
          ],
          child: MaterialApp(home: screen),
        );
        await tester.pumpWidget(providerApp(const HistoryScreen()));
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('journal-recording-switch'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Journal'), findsOneWidget);
        await tester.tap(find.text('Sessions'));
        await tester.pumpAndSettle();
        expect(
          find.text('No listening history yet. Play a book to see history.'),
          findsOneWidget,
        );
        await tester.pumpWidget(providerApp(const SettingsScreen()));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('journal-recording-switch')),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(
          find.byKey(const ValueKey('journal-recording-switch')),
        );
        await _wait(tester, () => h.settings.listeningJournalEnabled);
        expect(find.text('Open listening journal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h, providerOwnsSettings: true);
      }
    },
  );

  testWidgets(
    'journal visual review uses actual widgets and recorded data',
    (tester) async {
      final destination =
          Platform.environment['CRISPER_JOURNAL_SCREENSHOT_DIR']!;
      final fontDirectory = Platform.environment['CRISPER_JOURNAL_FONT_DIR'];
      if (fontDirectory == null) {
        throw StateError(
          'Set CRISPER_JOURNAL_FONT_DIR for readable visual review',
        );
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        for (final font in [
          ('PreviewFont', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final loader = FontLoader(font.$1)
            ..addFont(
              File(
                '$fontDirectory/${font.$2}',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
        await h.init();
        await _book(h, 'a', 'The Long Way Home');
        await _played(h, 1, DateTime(2025, 11, 10, 9, 20));
        await _event(
          h,
          2,
          DateTime(2025, 11, 10, 9, 25),
          kind: 'seek',
          reason: 'next_chapter',
        );
        await _event(
          h,
          3,
          DateTime(2025, 11, 10, 9, 30),
          kind: 'pause',
          positionMs: 142000,
        );
      });
      final key = GlobalKey();
      final base = AppTheme.lightTheme;
      final theme = base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'PreviewFont'),
        primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: 'PreviewFont',
        ),
        appBarTheme: base.appBarTheme.copyWith(
          titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: 'PreviewFont',
          ),
        ),
      );
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(destination).create(recursive: true);
          await File(
            '$destination/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      try {
        await _show(tester, h, captureKey: key, theme: theme);
        await tester.tap(find.byKey(const ValueKey('journal-dates-yearAgo')));
        await _wait(
          tester,
          () => find.text('Nov 10, 2025').evaluate().isNotEmpty,
        );
        await capture('journal-filters');
        await _reveal(tester, find.byKey(ValueKey('journal-entry-${_id(3)}')));
        await capture('journal-entries');
        final tracks = await tester.runAsync(() => h.db.tracksFor('a'));
        await _show(
          tester,
          h,
          captureKey: key,
          theme: theme,
          passage: JournalPassageFilter.point(
            bookId: 'a',
            filePath: tracks!.first.filePath,
            positionMs: 25000,
          ),
        );
        await capture('journal-passage');
        final export = find.byKey(const ValueKey('journal-export-button'));
        await _reveal(tester, export);
        await tester.tap(export);
        await tester.pumpAndSettle();
        await capture('journal-export');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
    skip: Platform.environment['CRISPER_JOURNAL_SCREENSHOT_DIR'] == null,
  );
}
