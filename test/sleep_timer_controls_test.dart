import 'package:crisperplayer/widgets/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  testWidgets(
    'custom sleep timer validates input, supports Enter and extension',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await h.book('sleep', [3600]);
        await h.playback.loadBook('sleep');
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSleepTimerSheet(context, h.playback),
                  child: const Text('Open timer'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open timer'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('sleep-custom-minutes'));
        await tester.ensureVisible(input);
        await tester.enterText(input, '0');
        await tester.ensureVisible(find.text('Start custom timer'));
        await tester.tap(find.text('Start custom timer'));
        await tester.pump();
        expect(
          find.text('Enter a whole number from 1 to 1440.'),
          findsOneWidget,
        );
        expect(h.playback.sleepRemaining, Duration.zero);
        await tester.enterText(input, '17');
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(h.playback.sleepRemaining, const Duration(minutes: 17));
        expect(h.playback.sleepEndOfChapter, isTrue);
        expect(h.settings.sleepTimerDefault, const Duration(minutes: 17));
        await tester.ensureVisible(find.text('+5 minutes'));
        await tester.tap(find.text('+5 minutes'));
        await tester.pump();
        expect(h.playback.sleepRemaining, const Duration(minutes: 22));
        expect(h.playback.sleepEndOfChapter, isTrue);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(h.playback.sleepRemaining, Duration.zero);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
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
