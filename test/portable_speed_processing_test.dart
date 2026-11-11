import 'package:crisperplayer/services/audio/speed_processing.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all portable preferences persist without changing platform defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      expect(settings.appleSpeedProcessing, 'timeDomain');
      expect(settings.desktopSpeedProcessing, 'sonic');
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

  test('desktop choices map to the shared native engines', () {
    final previous = SpeedProcessing.activeDesktopMode;
    addTearDown(() => SpeedProcessing.configureForStartup(
      previous.id, platform: TargetPlatform.linux));
    expect(DesktopSpeedProcessing.values, hasLength(4));
    for (final mode in DesktopSpeedProcessing.values) {
      SpeedProcessing.configureForStartup(mode.id, platform: TargetPlatform.linux);
      expect(SpeedProcessing.activeDesktopMode, mode);
      expect(SpeedProcessing.processorLabel(platform: TargetPlatform.windows),
        'Desktop · ${mode.label}');
    }
    expect(DesktopSpeedProcessing.values.map((mode) => mode.processor).toSet(), hasLength(4));
  });

  test('legacy desktop settings migrate to Sonic and retain portable choices', () async {
    for (final old in ['automatic', 'legacyScaletempo', 'atempo', 'unknown']) {
      SharedPreferences.setMockInitialValues({'desktop_speed_processing': old});
      final settings = SettingsService(await SharedPreferences.getInstance());
      expect(settings.desktopSpeedProcessing, 'sonic');
      expect(DesktopSpeedProcessing.parse(old), DesktopSpeedProcessing.sonic);
      expect(() => settings.desktopSpeedProcessing = old, throwsFormatException);
      settings.dispose();
    }
    for (final mode in DesktopSpeedProcessing.values) {
      SharedPreferences.setMockInitialValues({'desktop_speed_processing': mode.id});
      final settings = SettingsService(await SharedPreferences.getInstance());
      expect(settings.desktopSpeedProcessing, mode.id);
      settings.dispose();
    }
  });
}
