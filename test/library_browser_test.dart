import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/library_screen.dart';
import 'package:crisperplayer/theme/app_theme.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  for (final (size, scale) in const [
    (Size(320, 568), 1.0),
    (Size(320, 568), 2.0),
    (Size(568, 320), 1.0),
    (Size(568, 320), 2.0),
  ]) {
    testWidgets('library remains usable at $size with ${scale * 100}% text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = PlaybackHarness();
      late SettingsService uiSettings;
      final books = (await tester.runAsync(() async {
        await h.init();
        uiSettings = SettingsService(await SharedPreferences.getInstance());
        await h.book('a', [3600]);
        await h.book('b', [7200]);
        await h.library.editBook('a', {
          'title': 'Alpha: a long book title',
          'author': 'An author with a particularly long name',
          'series': 'A long series',
          'collection': 'Favorites',
        });
        await h.library.editBook('b', {
          'title': 'Beta',
          'author': 'Another author',
          'collection': 'Other',
        });
        await h.playback.loadBook('a');
        return h.library.allBooks();
      }))!;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(h.db),
              settingsProvider.overrideWith((ref) => uiSettings),
              playbackProvider.overrideWithValue(h.playback),
              libraryBooksProvider.overrideWith((ref) => Stream.value(books)),
              bookProvider('a').overrideWith(
                (ref) => Stream.value(books.singleWhere((b) => b.id == 'a')),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const LibraryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
        expect(
          find.byType(SliverList, skipOffstage: false),
          scale > 1 ? findsWidgets : findsNothing,
        );
        final field = find.byType(TextField);
        await tester.enterText(field, 'Beta');
        await tester.pumpAndSettle();
        expect(
          find.text('Alpha: a long book title'),
          findsOneWidget,
        ); // The pinned mini player.
        final beta = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Beta',
        );
        await tester.scrollUntilVisible(
          beta,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(beta, findsOneWidget);
        final clear = find.byKey(
          const ValueKey('clear-library-search'),
          skipOffstage: false,
        );
        await reveal(tester, clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Beta'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Beta'), findsOneWidget);
        for (final choice in const {
          'List': 'list',
          'Cover grid': 'grid',
          'Automatic': 'auto',
        }.entries) {
          final layout = find.byKey(
            const ValueKey('library-layout'),
            skipOffstage: false,
          );
          await reveal(tester, layout);
          await tester.tap(layout);
          await tester.pumpAndSettle();
          final item = find.ancestor(
            of: find.text(choice.key).last,
            matching: find.byType(CheckedPopupMenuItem<String>),
          );
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(h.settings.libraryView, choice.value);
          if (choice.value == 'list') {
            expect(find.text('Not started', skipOffstage: false), findsWidgets);
          }
          expect(tester.takeException(), isNull);
        }
        final status = find.byKey(
          const ValueKey('Reading status'),
          skipOffstage: false,
        );
        await reveal(tester, status);
        await tester.tap(status);
        await tester.pumpAndSettle();
        final finished = find.ancestor(
          of: find.text('Finished').last,
          matching: find.byType(CheckedPopupMenuItem<String>),
        );
        await tester.ensureVisible(finished);
        await tester.pumpAndSettle();
        await tester.tap(finished);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('No books match these filters.'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('No books match these filters.'), findsOneWidget);
        expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
        final semantics = tester.ensureSemantics();
        try {
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        } finally {
          semantics.dispose();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(h.dispose);
      }
    });
  }
  testWidgets('empty library scrolls with the largest text setting', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = PlaybackHarness();
    final uiSettings = (await tester.runAsync(() async {
      await h.init();
      return SettingsService(await SharedPreferences.getInstance());
    }))!;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => uiSettings),
            playbackProvider.overrideWithValue(h.playback),
            libraryBooksProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(3.2)),
              child: child!,
            ),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final empty = find.text('Your library is empty', skipOffstage: false);
      await Scrollable.ensureVisible(tester.element(empty), alignment: .5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(empty, findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.dispose);
    }
  });
}
