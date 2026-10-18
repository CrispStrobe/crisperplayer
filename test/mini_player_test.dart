import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  testWidgets(
    'mini player shows whole-book progress and close saves then unloads',
    (tester) async {
      final h = PlaybackHarness();
      final book = await tester.runAsync(() async {
        await h.init();
        await h.book('a', [30, 60]);
        await h.playback.loadBook('a');
        await h.playback.seekBook(const Duration(seconds: 35));
        return (await h.db.getBook('a'))!;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackProvider.overrideWithValue(h.playback),
            bookProvider('a').overrideWith((ref) => Stream.value(book)),
          ],
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('00:35 / 01:30'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(35 / 90, .001),
      );
      await tester.runAsync(() => tester.tap(find.byTooltip('Close player')));
      await tester.runAsync(h.flush);
      expect(h.playback.currentBookId, isNull);
      final stored = await tester.runAsync(() => h.db.getBook('a'));
      expect(stored!.lastPositionMs, 5000);
      expect(stored.lastPositionFilePath, '/a/1.mp3');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.dispose);
    },
  );
}
