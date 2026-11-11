import 'package:crisperplayer/services/audio/speed_processing.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all portable preferences persist without changing platform defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      expect(settings.appleSpeedProcessing, 'timeDomain');
      expect(settings.desktopSpeedProcessing, 'automatic');
      expect(settings.androidSpeedProcessing, 'sonic');
      for (final mode in AppleSpeedProcessing.values) {
        settings.appleSpeedProcessing = mode.id;
        expect(AppleSpeedProcessing.parse(settings.appleSpeedProcessing), mode);
      }
      for (final mode in DesktopSpeedProcessing.values) {
        settings.desktopSpeedProcessing = mode.id;
        expect(
          DesktopSpeedProcessing.parse(settings.desktopSpeedProcessing),
          mode,
        );
      }
      expect(settings.androidSpeedProcessing, 'sonic');
      settings.dispose();
    },
  );

  test('each Apple choice configures exactly one native playback path', () {
    final previous = SpeedProcessing.activeAppleMode;
    final previousPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      SpeedProcessing.configureAppleForStartup(
        previous.id,
        platform: TargetPlatform.iOS,
      );
      debugDefaultTargetPlatformOverride = previousPlatform;
    });
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final mode in AppleSpeedProcessing.values) {
        SpeedProcessing.configureAppleForStartup(mode.id);
        final control =
            SpeedProcessing.audioLoadConfiguration!.darwinLoadControl!;
        expect(control.speedProcessor, mode.processor);
        expect(control.audioTimePitchAlgorithm, mode.algorithm);
        expect(SpeedProcessing.supportsSkipSilence(), isFalse);
        expect(SpeedProcessing.processorLabel(), 'Apple · ${mode.label}');
      }
      SpeedProcessing.configureAppleForStartup('unknown');
      expect(
        SpeedProcessing
            .audioLoadConfiguration!
            .darwinLoadControl!
            .speedProcessor,
        isNull,
      );
      expect(SpeedProcessing.activeAppleMode, AppleSpeedProcessing.timeDomain);
    }
    expect(DarwinSpeedProcessor.values, hasLength(4));
  });

  test('desktop only selects engines present in the loaded native library', () {
    final previous = SpeedProcessing.activeDesktopMode;
    addTearDown(
      () => SpeedProcessing.configureForStartup(
        previous.id,
        platform: TargetPlatform.linux,
        availableProcessors: MediaKitSpeedProcessor.values.toSet(),
      ),
    );
    for (final mode in DesktopSpeedProcessing.values) {
      SpeedProcessing.configureForStartup(
        mode.id,
        platform: TargetPlatform.linux,
        availableProcessors: MediaKitSpeedProcessor.values.toSet(),
      );
      expect(SpeedProcessing.activeDesktopMode, mode);
      expect(JustAudioMediaKit.speedProcessor, mode.processor);
      expect(
        JustAudioMediaKit.pitch,
        mode == DesktopSpeedProcessing.legacyScaletempo,
      );
    }

    SpeedProcessing.configureForStartup(
      'signalsmith',
      platform: TargetPlatform.windows,
      availableProcessors: MediaKitSpeedProcessor.supportedBy(const []),
    );
    expect(SpeedProcessing.activeDesktopMode, DesktopSpeedProcessing.automatic);
    expect(JustAudioMediaKit.speedProcessor, MediaKitSpeedProcessor.automatic);
    expect(JustAudioMediaKit.pitch, isFalse);
  });

  test(
    'plain atempo cannot masquerade as a clock-correct mpv tempo filter',
    () {
      expect(
        MediaKitSpeedProcessor.supportedBy(['atempo']),
        isNot(contains(MediaKitSpeedProcessor.atempo)),
      );
      expect(
        MediaKitSpeedProcessor.supportedBy(['lavfi-tempo']),
        isNot(contains(MediaKitSpeedProcessor.atempo)),
      );
      expect(
        MediaKitSpeedProcessor.supportedBy(['lavfi-tempo', 'atempo']),
        contains(MediaKitSpeedProcessor.atempo),
      );
      final portable = MediaKitSpeedProcessor.supportedBy(['crisperdsp']);
      for (final processor in [
        MediaKitSpeedProcessor.sonic,
        MediaKitSpeedProcessor.wsola,
        MediaKitSpeedProcessor.signalsmith,
        MediaKitSpeedProcessor.bungee,
      ]) {
        expect(portable, contains(processor));
      }
    },
  );
}
