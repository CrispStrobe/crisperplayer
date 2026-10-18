import 'package:crisperplayer/services/audio/android_audio_effects.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAudioEffects.channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAudioEffects.channel, null),
  );
  test(
    'default effects do not instantiate native resources; active effects release with the session',
    () async {
      final effects = AndroidAudioEffects();
      await effects.configure(17, 0, 'off');
      expect(calls, isEmpty);
      await effects.configure(17, 6, 'speech');
      expect(calls.single.arguments['sessionId'], 17);
      expect(calls.single.arguments['boostDb'], 6);
      await effects.configure(null, 0, 'off');
      expect(calls.last.arguments['sessionId'], 0);
    },
  );
  test(
    'unsupported hardware fails softly and later configuration still works',
    () async {
      final effects = AndroidAudioEffects();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AndroidAudioEffects.channel,
            (_) async => throw PlatformException(code: 'EFFECTS_UNAVAILABLE'),
          );
      await effects.configure(17, 6, 'speech');
      expect(effects.error, isNotNull);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AndroidAudioEffects.channel,
            (_) async => null,
          );
      await effects.configure(18, 3, 'warm');
      expect(effects.error, isNull);
      await effects.dispose();
    },
  );
  test(
    'effects inherit defaults and per-book overrides without affecting other books',
    () async {
      final h = PlaybackHarness();
      await h.init();
      try {
        await h.book('a', [60]);
        await h.book('b', [60]);
        h.settings.boostDb = 3;
        h.settings.equalizer = 'warm';
        await h.playback.loadBook('a');
        expect(h.backend.boostDb, 3);
        expect(h.backend.equalizer, 'warm');
        await h.playback.updateBookPreferences('a', {
          'boostDb': 6,
          'equalizer': 'speech',
        });
        expect(h.backend.boostDb, 6);
        expect(h.backend.equalizer, 'speech');
        await h.playback.loadBook('b');
        expect(h.backend.boostDb, 3);
        expect(h.backend.equalizer, 'warm');
        await expectLater(
          h.playback.updateBookPreferences('b', {'boostDb': 20}),
          throwsFormatException,
        );
      } finally {
        await h.dispose();
      }
    },
  );
}
