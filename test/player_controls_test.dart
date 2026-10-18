import 'package:crisperplayer/utils/format.dart';
import 'package:crisperplayer/widgets/jump_to_time_dialog.dart';
import 'package:crisperplayer/widgets/volume_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  test(
    'timecodes accept seconds and clock formats and reject malformed values',
    () {
      expect(
        parseTimecode('01:02:03.125'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 125),
      );
      expect(parseTimecode('75:30'), const Duration(minutes: 75, seconds: 30));
      expect(
        parseTimecode('125.5'),
        const Duration(seconds: 125, milliseconds: 500),
      );
      for (final value in [
        '',
        '-1',
        'NaN',
        '1:60',
        '1:60:00',
        '1:2:3:4',
        '1.5:00',
      ]) {
        expect(
          () => parseTimecode(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );
  testWidgets(
    'jump dialog validates range, supports Enter and touch adjustments at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Duration? sought;
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
                onPressed: () async {
                  sought = await showJumpToTimeDialog(
                    context,
                    position: const Duration(seconds: 5),
                    duration: const Duration(hours: 2),
                  );
                },
                child: const Text('Edit time'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit time'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('jump-time-input'));
      await tester.enterText(input, '2:00:01');
      await tester.tap(find.text('Jump'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a time up to 2:00:00.'), findsOneWidget);
      expect(sought, isNull);
      await tester.enterText(input, '1:02:03');
      await tester.ensureVisible(find.text('+30 seconds'));
      await tester.tap(find.text('+30 seconds'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '1:02:33');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(sought, const Duration(hours: 1, minutes: 2, seconds: 33));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'volume slider, mute restore and persistence use the real coordinator',
    (tester) async {
      final h = (await tester.runAsync(() async {
        final harness = PlaybackHarness();
        await harness.init();
        return harness;
      }))!;
      try {
        await tester.runAsync(() => h.playback.setVolume(.4));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VolumeControlButton(playback: h.playback, volume: .4),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Playback volume'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mute'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(h.backend.volume, 0);
        expect(h.settings.volume, 0);
        expect(h.settings.unmutedVolume, .4);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Playback volume'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unmute'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(h.backend.volume, .4);
        expect(h.settings.volume, .4);
        await tester.tap(find.byTooltip('Increase volume by 5 percent'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(h.backend.volume, closeTo(.45, .001));
        expect(h.settings.volume, closeTo(.45, .001));
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('playback-volume-slider')),
        );
        expect(slider.semanticFormatterCallback!(.45), contains('45 percent'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        // UI callbacks register command futures in the widget fake-clock zone.
        // Pump those callbacks while allowing the real SQLite isolate to close.
        var closed = false;
        Object? closeError;
        h.dispose().then(
          (_) => closed = true,
          onError: (Object error) {
            closeError = error;
            closed = true;
          },
        );
        final deadline = Stopwatch()..start();
        while (!closed && deadline.elapsed < const Duration(seconds: 5)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
        }
        expect(closed, isTrue, reason: 'Playback and database must close');
        expect(closeError, isNull);
      }
    },
  );
}
