import 'package:crisperplayer/models/book_preferences.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/settings_screen.dart';
import 'package:crisperplayer/services/audio/audio_backend.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/audio/speed_processing.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:crisperplayer/widgets/book_preferences_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/playback_harness.dart';

/// Exercises the public Dart API and its real method-channel serialization.
/// Native processing is verified separately by the C++ and Android bridge tests.
class _NativeTransport {
  final requests = <Map<Object?, Object?>>[];
  final calls = <MethodCall>[];
  final channels = <MethodChannel>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const codec = StandardMethodCodec();

  void install() {
    _handle(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    _handle(const MethodChannel('com.ryanheise.just_audio.methods'), (
      call,
    ) async {
      if (call.method == 'init') {
        final request = Map<Object?, Object?>.from(call.arguments as Map);
        requests.add(request);
        final id = request['id']! as String;
        final configuration = request['audioLoadConfiguration'] as Map?;
        final loadControl = configuration?['androidLoadControl'] as Map?;
        final processor = loadControl?['speedProcessor'] as String? ?? 'sonic';
        _handle(
          MethodChannel('com.ryanheise.just_audio.events.$id'),
          (_) async => null,
        );
        _handle(
          MethodChannel('com.ryanheise.just_audio.data.$id'),
          (_) async => null,
        );
        _handle(MethodChannel('com.ryanheise.just_audio.methods.$id'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'setSkipSilence' &&
              (call.arguments as Map)['enabled'] == true &&
              processor != 'sonic') {
            throw PlatformException(code: 'unsupported_skip_silence');
          }
          if (call.method == 'load') {
            await messenger.handlePlatformMessage(
              'com.ryanheise.just_audio.events.$id',
              codec.encodeSuccessEnvelope({
                'processingState': 3,
                'updateTime': DateTime.now().millisecondsSinceEpoch,
                'updatePosition': 0,
                'bufferedPosition': 120000000,
                'duration': 120000000,
                'currentIndex': 0,
              }),
              null,
            );
            return {'duration': 120000000};
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  }

  void _handle(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
    channels.add(channel);
    messenger.setMockMethodCallHandler(channel, handler);
  }

  void close() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

AudioPlayer _player(AudioLoadConfiguration? configuration) => AudioPlayer(
  handleInterruptions: false,
  androidApplyAudioAttributes: false,
  handleAudioSessionActivation: false,
  audioLoadConfiguration: configuration,
);

class _NoSkipSilenceBackend extends FakeAudioBackend {
  @override
  bool get supportsSkipSilence => false;
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 5));
  } while (!ready() && elapsed.elapsed < const Duration(seconds: 5));
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SpeedProcessing.configureAndroidForStartup('sonic');
  });
  tearDown(() {
    SpeedProcessing.configureAndroidForStartup('sonic');
    debugDefaultTargetPlatformOverride = null;
  });

  for (final mode in AndroidSpeedProcessor.values) {
    test(
      'native init transports $mode without dropping existing buffer controls',
      () async {
        final transport = _NativeTransport()..install();
        final player = _player(
          AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
              speedProcessor: mode,
              minBufferDuration: const Duration(seconds: 7),
              maxBufferDuration: const Duration(seconds: 12),
              bufferForPlaybackDuration: const Duration(milliseconds: 500),
              bufferForPlaybackAfterRebufferDuration: const Duration(
                seconds: 2,
              ),
              targetBufferBytes: 123456,
              prioritizeTimeOverSizeThresholds: true,
              backBufferDuration: const Duration(seconds: 3),
            ),
          ),
        );
        try {
          await player.setAudioSources([
            AudioSource.uri(Uri.file('/fixture-a.wav')),
          ]);
          await player.setSpeed(1.5);
          await player.stop();
          await player.setAudioSources([
            AudioSource.uri(Uri.file('/fixture-b.wav')),
          ]);
          expect(transport.requests, hasLength(2));
          for (final request in transport.requests) {
            final configuration = request['audioLoadConfiguration']! as Map;
            expect(configuration['androidLoadControl'], {
              'speedProcessor': mode.name,
              'minBufferDuration': 7000000,
              'maxBufferDuration': 12000000,
              'bufferForPlaybackDuration': 500000,
              'bufferForPlaybackAfterRebufferDuration': 2000000,
              'targetBufferBytes': 123456,
              'prioritizeTimeOverSizeThresholds': true,
              'backBufferDuration': 3000000,
            });
            expect(configuration['darwinLoadControl'], isNull);
            expect(configuration['androidLivePlaybackSpeedControl'], isNull);
          }
          expect(player.speed, 1.5);
        } finally {
          await player.dispose();
          transport.close();
        }
      },
    );
  }

  test('Sonic keeps the upstream default and skip-silence support', () async {
    expect(
      const AndroidLoadControl().speedProcessor,
      AndroidSpeedProcessor.sonic,
    );
    expect(SpeedProcessing.audioLoadConfiguration, isNull);
    expect(SpeedProcessing.appleLoadConfiguration, isNull);
    final transport = _NativeTransport()..install();
    final backend = JustAudioBackend(
      _player(SpeedProcessing.audioLoadConfiguration),
    );
    try {
      await backend.load(['/fixture.wav'], index: 0, position: Duration.zero);
      expect(transport.requests.single['audioLoadConfiguration'], isNull);
      expect(backend.supportsSkipSilence, isTrue);
      await backend.setSkipSilence(true);
      expect(backend.player.skipSilenceEnabled, isTrue);
      expect(
        transport.calls
            .where((c) => c.method == 'setSkipSilence')
            .last
            .arguments,
        {'enabled': true},
      );
    } finally {
      await backend.dispose();
      transport.close();
    }
  });

  test(
    'Android startup selection is isolated from Apple, desktop, and web',
    () {
      final apple = SpeedProcessing.activeAppleMode;
      final desktop = SpeedProcessing.activeDesktopMode;
      final desktopPitch = JustAudioMediaKit.pitch;
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        SpeedProcessing.configureAndroidForStartup('wsola', platform: platform);
        expect(SpeedProcessing.activeAndroidMode, AndroidSpeedProcessing.sonic);
        expect(
          SpeedProcessing.supportsAndroidChoice(platform: platform),
          isFalse,
        );
        expect(
          SpeedProcessing.supportsSkipSilence(platform: platform),
          isFalse,
        );
      }
      SpeedProcessing.configureAndroidForStartup('wsola', isWeb: true);
      expect(SpeedProcessing.activeAndroidMode, AndroidSpeedProcessing.sonic);
      SpeedProcessing.configureAndroidForStartup('corrupt');
      expect(SpeedProcessing.activeAndroidMode, AndroidSpeedProcessing.sonic);
      expect(SpeedProcessing.activeAppleMode, apple);
      expect(SpeedProcessing.activeDesktopMode, desktop);
      expect(JustAudioMediaKit.pitch, desktopPitch);
      expect(SpeedProcessing.supportsAndroidChoice(isWeb: true), isFalse);
      expect(SpeedProcessing.supportsSkipSilence(isWeb: true), isFalse);
    },
  );

  for (final mode in [
    AndroidSpeedProcessing.bungee,
    AndroidSpeedProcessing.signalsmith,
    AndroidSpeedProcessing.wsola,
  ]) {
    test(
      'saved skip silence is retained but never enabled for ${mode.label}',
      () async {
        SharedPreferences.setMockInitialValues({
          'skip_silence': true,
          'android_speed_processing': mode.id,
        });
        final settings = SettingsService(await SharedPreferences.getInstance());
        SpeedProcessing.configureAndroidForStartup(
          settings.androidSpeedProcessing,
        );
        final configuration = SpeedProcessing.audioLoadConfiguration!;
        final transport = _NativeTransport()..install();
        final backend = JustAudioBackend(_player(configuration));
        try {
          await backend.load(
            ['/fixture-a.wav'],
            index: 0,
            position: Duration.zero,
          );
          await backend.setSkipSilence(settings.skipSilence);
          expect(backend.supportsSkipSilence, isFalse);
          expect(backend.player.skipSilenceEnabled, isFalse);
          expect(settings.skipSilence, isTrue);
          settings.androidSpeedProcessing = 'sonic';
          expect(SpeedProcessing.activeAndroidMode, mode);
          expect(backend.supportsSkipSilence, isFalse);
          // Simulate another launch. An existing player retains its immutable
          // processor and matching capabilities, including after stop/load.
          SpeedProcessing.configureAndroidForStartup(
            settings.androidSpeedProcessing,
          );
          expect(SpeedProcessing.supportsSkipSilence(), isTrue);
          expect(backend.supportsSkipSilence, isFalse);
          await backend.stop();
          await backend.load(
            ['/fixture-b.wav'],
            index: 0,
            position: Duration.zero,
          );
          await backend.setSkipSilence(settings.skipSilence);
          expect(transport.requests, hasLength(2));
          for (final request in transport.requests) {
            final control =
                (request['audioLoadConfiguration'] as Map)['androidLoadControl']
                    as Map;
            expect(control['speedProcessor'], mode.id);
          }
          expect(
            transport.calls
                .where((c) => c.method == 'setSkipSilence')
                .every((c) => (c.arguments as Map)['enabled'] == false),
            isTrue,
          );
          expect(settings.skipSilence, isTrue);
        } finally {
          await backend.dispose();
          settings.dispose();
          transport.close();
        }
      },
      skip: !SpeedProcessing.experimentalAndroidProcessorsAvailable,
    );
  }

  testWidgets(
    'unavailable skip-silence controls preserve app and book preferences',
    (tester) async {
      final h = PlaybackHarness();
      late PlaybackService playback;
      await tester.runAsync(() async {
        await h.init(
          preferences: {
            'skip_silence': true,
            'android_speed_processing': 'bungee',
          },
        );
        await h.book('custom', [120]);
        await h.playback.updateBookPreferences('custom', {'skipSilence': true});
        SpeedProcessing.configureAndroidForStartup(
          h.settings.androidSpeedProcessing,
        );
        playback = PlaybackService(
          db: h.db,
          library: h.library,
          bookmarks: BookmarkService(h.db),
          history: HistoryService(h.db),
          settings: h.settings,
          backend: _NoSkipSilenceBackend(),
        );
        await playback.init();
        await playback.loadBook('custom');
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(h.db),
          playbackProvider.overrideWithValue(playback),
          settingsProvider.overrideWith((ref) => h.settings),
        ],
      );
      Widget app(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      );
      try {
        await tester.pumpWidget(app(const SettingsScreen()));
        await tester.pumpAndSettle();
        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('settings-skip-silence')),
        );
        expect(toggle.onChanged, isNull);
        expect(toggle.value, isFalse);
        expect(
          find.text('Available with Sonic. Your saved preference is kept.'),
          findsOneWidget,
        );
        expect(h.settings.skipSilence, isTrue);
        // A pending Sonic selection must not enable controls for a custom player.
        h.settings.androidSpeedProcessing = 'sonic';
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('settings-skip-silence')),
              )
              .onChanged,
          isNull,
        );
        final book = await tester.runAsync(() => h.db.getBook('custom'));
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showBookPreferences(context, book!),
                  child: const Text('Book preferences'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Book preferences'));
        await tester.pumpAndSettle();
        final dropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('book-skip-silence')),
        );
        expect(dropdown.onChanged, isNull);
        expect(dropdown.initialValue, 'true');
        expect(
          find.text('Available with Sonic. Your saved preference is kept.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Save'));
        await _wait(
          tester,
          () => find.text('Playback for this book').evaluate().isEmpty,
        );
        final saved = await tester.runAsync(() => h.db.getBook('custom'));
        expect(
          BookPreferences.decode(saved!.playbackPreferencesJson)['skipSilence'],
          isTrue,
        );
        expect(h.settings.skipSilence, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        var closed = false;
        Object? failure;
        () async {
          await playback.dispose();
          await h.playback.dispose();
          await h.db.close();
          container.dispose();
          await h.root.delete(recursive: true);
        }().then<void>(
          (_) {
            closed = true;
          },
          onError: (Object error) {
            failure = error;
            closed = true;
          },
        );
        await _wait(tester, () => closed);
        expect(failure, isNull);
        SpeedProcessing.configureAndroidForStartup('sonic');
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: !SpeedProcessing.experimentalAndroidProcessorsAvailable,
  );
}
