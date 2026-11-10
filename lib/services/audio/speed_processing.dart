import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

enum DesktopSpeedProcessing {
  automatic('automatic', 'Automatic'),
  legacyScaletempo('legacyScaletempo', 'Legacy scaletempo');

  final String id;
  final String label;

  const DesktopSpeedProcessing(this.id, this.label);

  static DesktopSpeedProcessing parse(String value) =>
      value == legacyScaletempo.id ? legacyScaletempo : automatic;
}

enum AppleSpeedProcessing {
  timeDomain('timeDomain', 'Time Domain', DarwinTimePitchAlgorithm.timeDomain),
  spectral('spectral', 'Spectral', DarwinTimePitchAlgorithm.spectral);

  final String id;
  final String label;
  final DarwinTimePitchAlgorithm algorithm;

  const AppleSpeedProcessing(this.id, this.label, this.algorithm);

  static AppleSpeedProcessing parse(String value) =>
      value == spectral.id ? spectral : timeDomain;
}

/// The installed app's supported speed processors. A desktop selection applies
/// before constructing the audio player, never to an already running player.
abstract final class SpeedProcessing {
  // Match the adapter's upstream default until startup explicitly configures it.
  static DesktopSpeedProcessing _activeDesktopMode =
      DesktopSpeedProcessing.legacyScaletempo;
  static AppleSpeedProcessing _activeAppleMode =
      AppleSpeedProcessing.timeDomain;

  static DesktopSpeedProcessing get activeDesktopMode => _activeDesktopMode;
  static AppleSpeedProcessing get activeAppleMode => _activeAppleMode;

  static bool supportsDesktopChoice({TargetPlatform? platform, bool? isWeb}) =>
      !(isWeb ?? kIsWeb) &&
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.linux || TargetPlatform.windows => true,
        _ => false,
      };

  static bool supportsAppleChoice({TargetPlatform? platform, bool? isWeb}) =>
      !(isWeb ?? kIsWeb) &&
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => true,
        _ => false,
      };

  static bool supportsChoice({TargetPlatform? platform, bool? isWeb}) =>
      supportsDesktopChoice(platform: platform, isWeb: isWeb) ||
      supportsAppleChoice(platform: platform, isWeb: isWeb);

  static void configureForStartup(
    String savedMode, {
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (!supportsDesktopChoice(platform: platform, isWeb: isWeb)) return;
    final mode = DesktopSpeedProcessing.parse(savedMode);
    // This flag controls *independent pitch shifting*, not pitch preservation.
    // With false, media_kit changes mpv's speed while leaving its default
    // audio-pitch-correction enabled. Current mpv uses scaletempo2 for that path.
    // With true, media_kit instead installs legacy scaletempo and disables mpv's
    // automatic pitch correction. Both modes preserve pitch at the app's 1.0
    // pitch setting; CrisperPlayer does not expose independent pitch shifting.
    JustAudioMediaKit.pitch = mode == DesktopSpeedProcessing.legacyScaletempo;
    _activeDesktopMode = mode;
  }

  static void configureAppleForStartup(
    String savedMode, {
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (!supportsAppleChoice(platform: platform, isWeb: isWeb)) return;
    _activeAppleMode = AppleSpeedProcessing.parse(savedMode);
  }

  /// Pass this immutable configuration when creating the shared audio player.
  /// Other platforms keep their existing native configuration.
  static AudioLoadConfiguration? get appleLoadConfiguration =>
      supportsAppleChoice()
      ? AudioLoadConfiguration(
          darwinLoadControl: DarwinLoadControl(
            audioTimePitchAlgorithm: activeAppleMode.algorithm,
          ),
        )
      : null;

  static String processorLabel({TargetPlatform? platform, bool? isWeb}) {
    if (isWeb ?? kIsWeb) return 'Browser audio processing';
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android => 'Android · Sonic',
      TargetPlatform.iOS ||
      TargetPlatform.macOS => 'Apple · ${activeAppleMode.label}',
      TargetPlatform.linux ||
      TargetPlatform.windows => 'Desktop · ${activeDesktopMode.label}',
      _ => 'Platform audio processing',
    };
  }

  static String description({TargetPlatform? platform, bool? isWeb}) {
    if (isWeb ?? kIsWeb) {
      return 'The browser selects its audio processor.';
    }
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android =>
        'Sonic changes playback speed while preserving the narrator’s pitch. '
            'This Android player does not expose a choice of algorithm.',
      TargetPlatform.iOS || TargetPlatform.macOS =>
        'Both Apple processors preserve pitch when speed changes. Time Domain '
            'is designed for voice. Spectral is an alternative for music and '
            'mixed audio, and uses more processing power. Choose what sounds '
            'best for the recording.',
      TargetPlatform.linux || TargetPlatform.windows =>
        'Automatic uses the installed mpv engine’s default pitch-preserving '
            'processor. Current mpv versions use scaletempo2; the exact processor '
            'depends on the installed engine. Legacy uses the previous scaletempo '
            'path. Try it if a recording sounds better that way.',
      _ => 'Playback speed is handled by the platform audio player.',
    };
  }
}

/// Exact entry accepts hundredths, including a decimal comma, within the same
/// supported range as the coordinator. No exponent, NaN or infinity inputs.
double parsePlaybackSpeed(String value) {
  final text = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^(?:\d+(?:\.\d{1,2})?|\.\d{1,2})$').hasMatch(text)) {
    throw const FormatException('Enter a speed from 0.50 to 3.00.');
  }
  final speed = double.parse(text);
  if (!speed.isFinite || speed < .5 || speed > 3) {
    throw const FormatException('Enter a speed from 0.50 to 3.00.');
  }
  return speed;
}

double stepPlaybackSpeed(double speed, int steps) =>
    ((speed * 100).round() + steps * 5).clamp(50, 300) / 100;
