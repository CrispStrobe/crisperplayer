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

enum AndroidSpeedProcessing {
  sonic('sonic', 'Sonic', AndroidSpeedProcessor.sonic),
  bungee('bungee', 'Bungee Basic', AndroidSpeedProcessor.bungee),
  signalsmith(
    'signalsmith',
    'Signalsmith Stretch',
    AndroidSpeedProcessor.signalsmith,
  ),
  wsola('wsola', 'WSOLA', AndroidSpeedProcessor.wsola);

  final String id;
  final String label;
  final AndroidSpeedProcessor processor;

  const AndroidSpeedProcessing(this.id, this.label, this.processor);

  bool get supportsSkipSilence => this == sonic;

  static AndroidSpeedProcessing parse(String value) => switch (value) {
    'bungee' => bungee,
    'signalsmith' => signalsmith,
    'wsola' => wsola,
    _ => sonic,
  };
}

/// The installed app's supported speed processors. A selection applies
/// before constructing the audio player, never to an already running player.
abstract final class SpeedProcessing {
  // The vendored native core and Media3/JNI bridges pass their host integration
  // checks. These alternatives remain an explicit experimental opt-in; host
  // checks do not establish audio quality or performance on every Android device.
  static const experimentalAndroidProcessorsAvailable = true;
  // Match the adapter's upstream default until startup explicitly configures it.
  static DesktopSpeedProcessing _activeDesktopMode =
      DesktopSpeedProcessing.legacyScaletempo;
  static AppleSpeedProcessing _activeAppleMode =
      AppleSpeedProcessing.timeDomain;
  static AndroidSpeedProcessing _activeAndroidMode =
      AndroidSpeedProcessing.sonic;

  static DesktopSpeedProcessing get activeDesktopMode => _activeDesktopMode;
  static AppleSpeedProcessing get activeAppleMode => _activeAppleMode;
  static AndroidSpeedProcessing get activeAndroidMode => _activeAndroidMode;

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

  static bool supportsAndroidChoice({TargetPlatform? platform, bool? isWeb}) =>
      experimentalAndroidProcessorsAvailable &&
      !(isWeb ?? kIsWeb) &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android;

  static bool supportsSkipSilence({TargetPlatform? platform, bool? isWeb}) =>
      !(isWeb ?? kIsWeb) &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android &&
      activeAndroidMode.supportsSkipSilence;

  static bool supportsChoice({TargetPlatform? platform, bool? isWeb}) =>
      supportsDesktopChoice(platform: platform, isWeb: isWeb) ||
      supportsAppleChoice(platform: platform, isWeb: isWeb) ||
      supportsAndroidChoice(platform: platform, isWeb: isWeb);

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

  static void configureAndroidForStartup(
    String savedMode, {
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if ((isWeb ?? kIsWeb) ||
        (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return;
    }
    final mode = AndroidSpeedProcessing.parse(savedMode);
    if (mode != AndroidSpeedProcessing.sonic &&
        !experimentalAndroidProcessorsAvailable) {
      throw StateError('Experimental Android audio processors are unavailable');
    }
    _activeAndroidMode = mode;
  }

  /// Each player keeps its startup configuration even if a preference changes.
  /// Android's Sonic default leaves the upstream configuration unchanged.
  static AudioLoadConfiguration? get audioLoadConfiguration {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return activeAndroidMode == AndroidSpeedProcessing.sonic
          ? null
          : AudioLoadConfiguration(
              androidLoadControl: AndroidLoadControl(
                speedProcessor: activeAndroidMode.processor,
              ),
            );
    }
    return appleLoadConfiguration;
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
      TargetPlatform.android => 'Android · ${activeAndroidMode.label}',
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
        experimentalAndroidProcessorsAvailable
            ? 'Sonic is the default for speech. Bungee Basic, Signalsmith Stretch and WSOLA '
                  'are experimental alternatives that may use more CPU and '
                  'increase battery use. They support mono and stereo audio. '
                  'Results depend on the recording and '
                  'speed. Skip silence is available only with Sonic.'
            : 'Sonic changes playback speed while preserving the narrator’s '
                  'pitch. Additional processors are not available in this build.',
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
