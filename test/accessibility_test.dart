import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/player_screen.dart';
import 'package:crisperplayer/widgets/mini_player.dart';
import 'package:crisperplayer/widgets/sleep_timer_sheet.dart';
import 'package:crisperplayer/widgets/speed_sheet.dart';
import 'dart:ui' show SemanticsAction;
import 'package:crisperplayer/widgets/playback_seek_slider.dart';
import 'package:crisperplayer/widgets/waveform_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  for (final mini in [false, true]) {
    testWidgets(
      '${mini ? 'mini' : 'full'} player fits a small phone at 200% text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = PlaybackHarness();
        final data = (await tester.runAsync(() async {
          await harness.init();
          await harness.book('a11y', [3600]);
          await harness.playback.loadBook('a11y');
          return (
            await harness.db.getBook('a11y'),
            await harness.db.chaptersFor('a11y'),
          );
        }))!;
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                playbackProvider.overrideWithValue(harness.playback),
                bookProvider(
                  'a11y',
                ).overrideWith((ref) => Stream.value(data.$1)),
                chaptersProvider(
                  'a11y',
                ).overrideWith((ref) => Stream.value(data.$2)),
                bookmarksProvider(
                  'a11y',
                ).overrideWith((ref) => Stream.value([])),
              ],
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: mini
                    ? const Scaffold(body: MiniPlayer())
                    : const PlayerScreen(bookId: 'a11y'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final semantics = tester.ensureSemantics();
          try {
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
          } finally {
            semantics.dispose();
          }
          if (!mini) {
            await tester.ensureVisible(find.byTooltip('More speeds'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }

  for (final sleep in [false, true]) {
    testWidgets(
      '${sleep ? 'sleep' : 'speed'} sheet scrolls at 200% text in landscape',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(568, 320);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = PlaybackHarness();
        await tester.runAsync(harness.init);
        try {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => sleep
                        ? showSleepTimerSheet(context, harness.playback)
                        : showSpeedSheet(context, harness.playback),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Done'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }
  testWidgets(
    'seek announces elapsed and total time and moves by the configured interval',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sought = <Duration>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaybackSeekSlider(
                position: const Duration(hours: 1),
                duration: const Duration(hours: 17),
                step: const Duration(seconds: 15),
                onSeek: sought.add,
              ),
            ),
          ),
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Playback position'),
        );
        expect(node.getSemanticsData().value, '1 hour of 17 hours');
        expect(
          node.getSemanticsData().increasedValue,
          '1 hour, 15 seconds of 17 hours',
        );
        tester.semantics.increase(find.semantics.byLabel('Playback position'));
        tester.semantics.decrease(find.semantics.byLabel('Playback position'));
        expect(sought, [
          const Duration(hours: 1, seconds: 15),
          const Duration(minutes: 59, seconds: 45),
        ]);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'seek clamps screen-reader steps and disables unavailable duration',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sought = <Duration>[];
      Future<void> show(Duration position, Duration duration) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlaybackSeekSlider(
                  position: position,
                  duration: duration,
                  onSeek: sought.add,
                ),
              ),
            ),
          );
      try {
        await show(const Duration(seconds: 4), const Duration(seconds: 5));
        var node = tester.getSemantics(
          find.bySemanticsLabel('Playback position'),
        );
        tester.semantics.increase(find.semantics.byLabel('Playback position'));
        tester.semantics.decrease(find.semantics.byLabel('Playback position'));
        expect(sought, [const Duration(seconds: 5), Duration.zero]);
        await show(Duration.zero, Duration.zero);
        node = tester.getSemantics(find.bySemanticsLabel('Playback position'));
        expect(node.getSemanticsData().value, 'Duration unavailable');
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.increase),
          isFalse,
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.decrease),
          isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'measured waveform never animates amplitudes, with or without reduced motion',
    (tester) async {
      Future<void> show(bool reduced) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const WaveformView(isPlaying: true),
          ),
        ),
      );
      await show(true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await show(false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);
      await show(true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
