import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/audio/speed_processing.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/widgets/speed_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'support/playback_harness.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  } while (!ready() && deadline.elapsed < const Duration(seconds: 5));
  expect(ready(), isTrue, reason: 'The playback command must complete');
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _show(WidgetTester tester, PlaybackService svc) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSpeedSheet(context, svc),
            child: const Text('Open speed'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open speed'));
  await tester.pumpAndSettle();
}

Future<void> _close(
  WidgetTester tester,
  Future<void> Function() dispose,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  Object? failure;
  dispose().then(
    (_) => closed = true,
    onError: (Object error) {
      failure = error;
      closed = true;
    },
  );
  await _waitFor(tester, () => closed);
  expect(failure, isNull);
}

class _RejectingSpeedBackend extends FakeAudioBackend {
  bool reject = false;

  @override
  Future<void> setSpeed(double speed) async {
    if (reject) throw StateError('Speed adjustment is unavailable');
    await super.setSpeed(speed);
  }
}

void main() {
  test(
    'exact rates validate format and fine steps do not drift or exceed bounds',
    () {
      expect(parsePlaybackSpeed('1.13'), 1.13);
      expect(parsePlaybackSpeed(' 1,15 '), 1.15);
      expect(parsePlaybackSpeed('.5'), .5);
      expect(parsePlaybackSpeed('3.00'), 3);
      for (final value in [
        '0.49',
        '3.01',
        'NaN',
        'Infinity',
        '1e0',
        '-1',
        '',
        '1.234',
        '1,2.3',
      ]) {
        expect(
          () => parsePlaybackSpeed(value),
          throwsFormatException,
          reason: value,
        );
      }
      var speed = .5;
      for (var i = 0; i < 50; i++) {
        speed = stepPlaybackSpeed(speed, 1);
      }
      expect(speed, 3);
      expect(stepPlaybackSpeed(speed, 1), 3);
      expect(stepPlaybackSpeed(.5, -1), .5);
      expect(stepPlaybackSpeed(1.13, 1), 1.18);
    },
  );

  test(
    'desktop startup selects supported adapter path and never changes Apple or web',
    () {
      final previous = SpeedProcessing.activeDesktopMode;
      addTearDown(
        () => SpeedProcessing.configureForStartup(
          previous.id,
          platform: TargetPlatform.linux,
        ),
      );
      SpeedProcessing.configureForStartup(
        'legacyScaletempo',
        platform: TargetPlatform.windows,
      );
      expect(JustAudioMediaKit.pitch, isTrue);
      expect(
        SpeedProcessing.activeDesktopMode,
        DesktopSpeedProcessing.legacyScaletempo,
      );
      SpeedProcessing.configureForStartup(
        'automatic',
        platform: TargetPlatform.iOS,
      );
      expect(JustAudioMediaKit.pitch, isTrue);
      SpeedProcessing.configureForStartup(
        'automatic',
        platform: TargetPlatform.windows,
        isWeb: true,
      );
      expect(JustAudioMediaKit.pitch, isTrue);
      SpeedProcessing.configureForStartup(
        'automatic',
        platform: TargetPlatform.linux,
      );
      expect(
        JustAudioMediaKit.pitch,
        isFalse,
        reason:
            'Disable independent pitch shifting so mpv retains its own pitch-corrected speed path',
      );
      expect(
        SpeedProcessing.activeDesktopMode,
        DesktopSpeedProcessing.automatic,
      );
      expect(
        SpeedProcessing.supportsChoice(platform: TargetPlatform.android),
        isFalse,
      );
      expect(
        SpeedProcessing.supportsChoice(platform: TargetPlatform.macOS),
        isFalse,
      );
      expect(
        SpeedProcessing.processorLabel(platform: TargetPlatform.android),
        contains('Sonic'),
      );
      expect(
        SpeedProcessing.processorLabel(platform: TargetPlatform.macOS),
        contains('Time Domain'),
      );
    },
  );

  testWidgets(
    'fine and exact controls persist per book, validate, and follow external changes',
    (tester) async {
      final h = PlaybackHarness();
      await tester.runAsync(() async {
        await h.init();
        await h.book('speed', [3600]);
        await h.playback.loadBook('speed');
      });
      try {
        await _show(tester, h.playback);
        final increase = find.byKey(const ValueKey('speed-increase'));
        await tester.ensureVisible(increase);
        await tester.tap(increase);
        await _waitFor(
          tester,
          () =>
              h.backend.speed == 1.05 &&
              tester.widget<IconButton>(increase).onPressed != null,
        );
        final input = find.byKey(const ValueKey('speed-exact-input'));
        await tester.ensureVisible(input);
        await tester.enterText(input, '3.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('Enter a speed from 0.50 to 3.00.'), findsOneWidget);
        expect(h.backend.speed, 1.05);
        await tester.enterText(input, '1,13');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _waitFor(
          tester,
          () =>
              h.backend.speed == 1.13 &&
              tester
                      .widget<OutlinedButton>(
                        find.byKey(const ValueKey('speed-apply-exact')),
                      )
                      .onPressed !=
                  null,
        );
        final preferences = await tester.runAsync(
          () => h.library.preferences('speed'),
        );
        expect(preferences!['speed'], 1.13);
        await tester.runAsync(
          () => h.playback.setSpeed(2, expectedBookId: 'speed'),
        );
        await _waitFor(
          tester,
          () =>
              tester
                  .widget<Text>(
                    find.byKey(const ValueKey('speed-current-value')),
                  )
                  .data ==
              '2.00×',
        );
        expect(tester.widget<TextFormField>(input).controller!.text, '2.00');
        expect(
          find.text(
            '30:00 of listening left in this book at 2.00×.\n1:00:00 at normal speed.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('speed-slider')))
              .divisions,
          50,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h.dispose);
      }
    },
  );

  testWidgets(
    'desktop preference is honest about restart and does not change active audio',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final previous = SpeedProcessing.activeDesktopMode;
      addTearDown(
        () => SpeedProcessing.configureForStartup(
          previous.id,
          platform: TargetPlatform.linux,
        ),
      );
      SpeedProcessing.configureForStartup('automatic');
      final h = PlaybackHarness();
      await tester.runAsync(h.init);
      try {
        await _show(tester, h.playback);
        final panel = find.byKey(const ValueKey('speed-processing-panel'));
        await tester.ensureVisible(panel);
        await tester.tap(panel);
        await tester.pumpAndSettle();
        final legacy = find.byKey(
          const ValueKey('speed-processing-legacyScaletempo'),
        );
        await tester.ensureVisible(legacy);
        await tester.tap(legacy);
        await tester.pumpAndSettle();
        expect(h.settings.desktopSpeedProcessing, 'legacyScaletempo');
        expect(JustAudioMediaKit.pitch, isFalse);
        expect(
          SpeedProcessing.activeDesktopMode,
          DesktopSpeedProcessing.automatic,
        );
        expect(
          find.text(
            'Saved for next launch: Legacy scaletempo. Restart CrisperPlayer to apply. Currently using Automatic.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await _close(tester, h.dispose);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    },
  );

  testWidgets('native-only processor information hides unavailable choices', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final h = PlaybackHarness();
    await tester.runAsync(h.init);
    try {
      await _show(tester, h.playback);
      final panel = find.byKey(const ValueKey('speed-processing-panel'));
      await tester.ensureVisible(panel);
      await tester.tap(panel);
      await tester.pumpAndSettle();
      expect(find.text('Apple · Time Domain'), findsOneWidget);
      expect(find.byType(RadioListTile<DesktopSpeedProcessing>), findsNothing);
      expect(
        find.textContaining('does not expose a choice of algorithm'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await _close(tester, h.dispose);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets(
    'decoder errors stay visible and a stale sheet cannot change another book',
    (tester) async {
      final h = PlaybackHarness();
      final backend = _RejectingSpeedBackend();
      late PlaybackService playback;
      await tester.runAsync(() async {
        await h.init();
        await h.book('speed', [120]);
        await h.book('other', [180]);
        playback = PlaybackService(
          db: h.db,
          library: h.library,
          bookmarks: BookmarkService(h.db),
          history: HistoryService(h.db),
          backend: backend,
          settings: h.settings,
          now: () => h.clock,
        );
        await playback.init();
        await playback.loadBook('speed');
        backend.reject = true;
      });
      try {
        await _show(tester, playback);
        final increase = find.byKey(const ValueKey('speed-increase'));
        await tester.ensureVisible(increase);
        await tester.tap(increase);
        await _waitFor(
          tester,
          () => find
              .textContaining('Speed could not be changed')
              .evaluate()
              .isNotEmpty,
        );
        expect(backend.speed, 1);
        expect(playback.state.speed, 1);
        backend.reject = false;
        await tester.runAsync(() => playback.loadBook('other'));
        await tester.pump();
        expect(find.textContaining('The playing book changed'), findsOneWidget);
        expect(tester.widget<IconButton>(increase).onPressed, isNull);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('speed-exact-input')),
              )
              .enabled,
          isFalse,
        );
        expect(backend.speed, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, () async {
          await playback.dispose();
          await h.dispose();
        });
      }
    },
  );
}
