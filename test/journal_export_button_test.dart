import 'dart:async';

import 'package:crisperplayer/models/listening_journal.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/listening_journal_report.dart';
import 'package:crisperplayer/widgets/journal_export_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Any accidental playback access in the injected UI path fails the test.
class _UnusedPlaybackService implements PlaybackService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected playback access: ${invocation.memberName}');
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('journal-export-button')));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('journal-export-confirm'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'CSV and path omission are default, cancellation creates nothing',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          JournalExportButton(
            playback: _UnusedPlaybackService(),
            filterDescription: 'All books · Last seven days',
            exporter: (request) async {
              calls++;
              return null;
            },
          ),
        ),
      );
      await _open(tester);
      expect(find.text('All books · Last seven days'), findsOneWidget);
      expect(find.textContaining('every matching entry'), findsOneWidget);
      expect(find.textContaining('restorable backup'), findsOneWidget);
      final paths = find.byKey(const ValueKey('journal-export-paths'));
      expect(tester.widget<CheckboxListTile>(paths).value, isFalse);
      await tester.tap(paths);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(paths).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('journal-export-cancel')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await _open(tester);
      expect(tester.widget<CheckboxListTile>(paths).value, isFalse);
      expect(find.text('CSV'), findsOneWidget);
      await _confirm(tester);
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets(
    'report scope is captured before the dialog even if filters change',
    (tester) async {
      final initialPassage = JournalPassageFilter.range(
        bookId: 'original',
        filePath: '/private/original.mp3',
        startMs: 12345,
        endMs: 45678,
      );
      final filters = ValueNotifier(
        JournalReportFilters(
          bookId: 'original',
          fromUtcMs: 1000,
          beforeUtcMs: 9000,
          passage: initialPassage,
        ),
      );
      addTearDown(filters.dispose);
      JournalReportRequest? captured;
      final pending = Completer<JournalReportExportResult?>();
      final playback = _UnusedPlaybackService();
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<JournalReportFilters>(
            valueListenable: filters,
            builder: (context, value, child) => JournalExportButton(
              playback: playback,
              bookId: value.bookId,
              fromUtcMs: value.fromUtcMs,
              beforeUtcMs: value.beforeUtcMs,
              passage: value.passage,
              exporter: (request) {
                captured = request;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await _open(tester);
      filters.value = const JournalReportFilters(bookId: 'changed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('journal-export-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('journal-export-paths')));
      await _confirm(tester);
      expect(captured, isNotNull);
      expect(captured!.format, JournalReportFormat.json);
      expect(captured!.includeFilePaths, isTrue);
      expect(captured!.filters.bookId, 'original');
      expect(captured!.filters.fromUtcMs, 1000);
      expect(captured!.filters.beforeUtcMs, 9000);
      expect(captured!.filters.passage, initialPassage);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('journal-export-button')),
      );
      expect(button.onPressed, isNull);
      pending.complete(
        const JournalReportExportResult(
          path: '/reports/journal.json',
          entryCount: 423,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved 423 journal entries'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('journal-export-button')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('export failures are visible and leave retry available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        JournalExportButton(
          playback: _UnusedPlaybackService(),
          exporter: (request) async => throw StateError('Storage is full'),
        ),
      ),
    );
    await _open(tester);
    await _confirm(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not export the journal report'),
      findsOneWidget,
    );
    expect(find.textContaining('Storage is full'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('journal-export-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('options remain usable at 320px with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      _app(
        JournalExportButton(
          playback: _UnusedPlaybackService(),
          filterDescription: 'A long book title · Track 13 · 00:02:03–00:04:56',
          exporter: (request) async {
            calls++;
            return null;
          },
        ),
        textScale: 2,
      ),
    );
    await _open(tester);
    expect(tester.takeException(), isNull);
    await _confirm(tester);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
