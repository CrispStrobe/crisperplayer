import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

enum DesktopSpeedProcessing {
  automatic('automatic', 'Automatic', MediaKitSpeedProcessor.automatic),
  legacyScaletempo(
    'legacyScaletempo',
    'Legacy scaletempo',
    MediaKitSpeedProcessor.legacyScaletempo,
  ),
  sonic('sonic', 'Sonic', MediaKitSpeedProcessor.sonic),
  wsola('wsola', 'WSOLA', MediaKitSpeedProcessor.wsola),
  signalsmith(
    'signalsmith',
    'Signalsmith Stretch',
    MediaKitSpeedProcessor.signalsmith,
  ),
  bungee('bungee', 'Bungee Basic', MediaKitSpeedProcessor.bungee),
  atempo('atempo', 'FFmpeg atempo', MediaKitSpeedProcessor.atempo);

  final String id;
  final String label;
  final MediaKitSpeedProcessor processor;

  const DesktopSpeedProcessing(this.id, this.label, this.processor);

  static DesktopSpeedProcessing parse(String value) =>
      values.firstWhere((mode) => mode.id == value, orElse: () => automatic);
}

enum AppleSpeedProcessing {
  timeDomain('timeDomain', 'Time Domain', DarwinTimePitchAlgorithm.timeDomain),
  spectral('spectral', 'Spectral', DarwinTimePitchAlgorithm.spectral),
  sonic(
    'sonic',
    'Sonic',
    DarwinTimePitchAlgorithm.timeDomain,
    processor: DarwinSpeedProcessor.sonic,
  ),
  wsola(
    'wsola',
    'WSOLA',
    DarwinTimePitchAlgorithm.timeDomain,
    processor: DarwinSpeedProcessor.wsola,
  ),
  signalsmith(
    'signalsmith',
    'Signalsmith Stretch',
    DarwinTimePitchAlgorithm.timeDomain,
    processor: DarwinSpeedProcessor.signalsmith,
  ),
  bungee(
    'bungee',
    'Bungee Basic',
    DarwinTimePitchAlgorithm.timeDomain,
    processor: DarwinSpeedProcessor.bungee,
  );

  final String id;
  final String label;
  final DarwinTimePitchAlgorithm algorithm;
  final DarwinSpeedProcessor? processor;

  const AppleSpeedProcessing(
    this.id,
    this.label,
    this.algorithm, {
    this.processor,
  });

  bool get isPortable => processor != null;

  static AppleSpeedProcessing parse(String value) =>
      values.firstWhere((mode) => mode.id == value, orElse: () => timeDomain);
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

  /// Probed from the actual loaded libmpv, not inferred from the host OS.
  static List<DesktopSpeedProcessing> get availableDesktopModes => [
    for (final mode in DesktopSpeedProcessing.values)
      if (JustAudioMediaKit.supportedSpeedProcessors.contains(mode.processor))
        mode,
  ];

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
    Set<MediaKitSpeedProcessor>? availableProcessors,
  }) {
    if (!supportsDesktopChoice(platform: platform, isWeb: isWeb)) return;
    final requested = DesktopSpeedProcessing.parse(savedMode);
    final available =
        availableProcessors ?? JustAudioMediaKit.supportedSpeedProcessors;
    // Keep the saved preference, but make startup usable if a different system
    // libmpv lacks the selected filter. The sheet shows the actual active mode
    // and explains that the saved choice is unavailable in this installation.
    final mode = available.contains(requested.processor)
        ? requested
        : DesktopSpeedProcessing.automatic;
    // This flag controls *independent pitch shifting*, not pitch preservation.
    // With false, media_kit changes mpv's speed while leaving its default
    // audio-pitch-correction enabled. Current mpv uses scaletempo2 for that path.
    // With true, media_kit instead installs legacy scaletempo and disables mpv's
    // automatic pitch correction. Both modes preserve pitch at the app's 1.0
    // pitch setting; CrisperPlayer does not expose independent pitch shifting.
    JustAudioMediaKit.pitch = mode == DesktopSpeedProcessing.legacyScaletempo;
    JustAudioMediaKit.speedProcessor = mode.processor;
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
            speedProcessor: activeAppleMode.processor,
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
        'Time Domain remains the Apple voice default; Spectral is an alternative '
            'for music and mixed audio. Sonic, WSOLA, Signalsmith Stretch and '
            'Bungee Basic are experimental alternatives for downloaded or local '
            'mono/stereo books. All preserve pitch when speed changes. '
            'Portable processors support the formats Apple can decode locally; '
            'choose an Apple processor for network streams.',
      TargetPlatform.linux || TargetPlatform.windows =>
        'Automatic uses the installed mpv engine’s default pitch-preserving '
            'processor. Current mpv versions use scaletempo2; the exact processor '
            'depends on the installed engine. Legacy uses the previous scaletempo '
            'path. Additional choices are shown when supported by the installed '
            'audio engine. Compare them with the same recording and speed.',
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
