import 'package:flutter/foundation.dart';
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

/// The installed app's supported speed processors. A desktop selection applies
/// before constructing the audio player, never to an already running player.
abstract final class SpeedProcessing {
  // Match the adapter's upstream default until startup explicitly configures it.
  static DesktopSpeedProcessing _activeDesktopMode =
      DesktopSpeedProcessing.legacyScaletempo;

  static DesktopSpeedProcessing get activeDesktopMode => _activeDesktopMode;

  static bool supportsChoice({TargetPlatform? platform, bool? isWeb}) =>
      !(isWeb ?? kIsWeb) &&
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.linux || TargetPlatform.windows => true,
        _ => false,
      };

  static void configureForStartup(
    String savedMode, {
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (!supportsChoice(platform: platform, isWeb: isWeb)) return;
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

  static String processorLabel({TargetPlatform? platform, bool? isWeb}) {
    if (isWeb ?? kIsWeb) return 'Browser audio processing';
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android => 'Android · Sonic',
      TargetPlatform.iOS || TargetPlatform.macOS => 'Apple · Time Domain',
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
        'Apple’s Time Domain processor preserves voice pitch at different speeds. '
            'This Apple player does not expose a choice of algorithm.',
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
