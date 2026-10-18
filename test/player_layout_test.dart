import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/player_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  for (final size in [
    const Size(800, 600),
    const Size(390, 660),
    const Size(660, 360),
  ]) {
    testWidgets(
      'transport stays visible at $size and chapter selection stays stable',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = PlaybackHarness();
        final data = await tester.runAsync(() async {
          await h.init();
          await h.book('layout', [3600]);
          await (h.db.update(
            h.db.books,
          )..where((t) => t.id.equals('layout'))).write(
            BooksCompanion(
              id: const Value('layout'),
              title: const Value(
                'Miles Cameron 01 Soulstealer — The Soulflake Conspiracies with a very long audiobook title',
              ),
            ),
          );
          await h.playback.loadBook('layout');
          return (
            await h.db.getBook('layout'),
            await h.db.chaptersFor('layout'),
          );
        });
        final book = data!.$1;
        final chapters = data.$2;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(h.db),
              playbackProvider.overrideWithValue(h.playback),
              bookProvider('layout').overrideWith((ref) => Stream.value(book)),
              chaptersProvider(
                'layout',
              ).overrideWith((ref) => Stream.value(chapters)),
              bookmarksProvider(
                'layout',
              ).overrideWith((ref) => Stream.value([])),
            ],
            child: const MaterialApp(home: PlayerScreen(bookId: 'layout')),
          ),
        );
        await tester.pumpAndSettle();
        final transport = find.byKey(const ValueKey('player-play-pause'));
        final rect = tester.getRect(transport);
        expect(rect.top, greaterThan(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(transport.hitTestable(), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);
        final chip = find.byKey(ValueKey('chapter-${chapters.first.id}'));
        await tester.ensureVisible(chip);
        final element = tester.element(chip);
        await tester.runAsync(() => h.playback.setSpeed(2));
        await tester.pump();
        expect(find.text('0% • 30:00 left'), findsOneWidget);
        await tester.runAsync(h.playback.play);
        for (var i = 1; i < 10; i++) {
          h.backend.move(Duration(seconds: i));
          await tester.pump(const Duration(milliseconds: 100));
          final widget = tester.widget<ChoiceChip>(chip);
          expect(widget.selected, isTrue);
          expect(widget.showCheckmark, isFalse);
          expect(tester.element(chip), same(element));
          expect(transport.hitTestable(), findsOneWidget);
        }
        await tester.runAsync(h.playback.pause);
        await tester.pump();
        await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.space));
        await tester.runAsync(h.flush);
        expect(h.backend.playing, isTrue);
        await tester.runAsync(h.playback.pause);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      },
    );
  }
}
