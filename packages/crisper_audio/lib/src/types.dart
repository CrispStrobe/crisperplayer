// SPDX-License-Identifier: MIT
import 'dart:typed_data';

enum NativeSpeedEngine { sonic, wsola, signalsmith, bungee }

enum NativeAudioState { idle, loading, buffering, ready, completed }

class NativeAudioError implements Exception {
  const NativeAudioError(this.message, {this.operation = 'playback'});
  final String message;
  final String operation;
  @override
  String toString() => 'NativeAudioError($operation): $message';
}

/// A transport request was replaced by a newer load, seek, stop, or rate change.
class NativeAudioCancelled extends NativeAudioError {
  const NativeAudioCancelled()
    : super('Transport request superseded', operation: 'cancel');
}

class NativeAudioSnapshot {
  const NativeAudioSnapshot({
    this.state = NativeAudioState.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.index,
    this.speed = 1,
    this.volume = 1,
    this.sampleRate = 0,
    this.channels = 0,
    this.format,
    this.outputLatency = Duration.zero,
    this.error,
  });

  final NativeAudioState state;

  /// The requested play state; stays true at natural completion until paused.
  final bool playing;

  /// Source time represented by presented PCM, never decoder read-ahead.
  final Duration position;
  final Duration duration;
  final int? index;
  final double speed;
  final double volume;
  final int sampleRate;
  final int channels;
  final String? format;

  /// Backend queue-delay estimate; downstream device latency can be greater.
  final Duration outputLatency;
  final NativeAudioError? error;

  factory NativeAudioSnapshot.fromMessage(Map<Object?, Object?> message) {
    final error = message['error'] as String?;
    return NativeAudioSnapshot(
      state: NativeAudioState.values[message['state'] as int],
      playing: message['playing'] as bool,
      position: Duration(microseconds: message['position'] as int),
      duration: Duration(microseconds: message['duration'] as int),
      index: message['index'] as int?,
      speed: message['speed'] as double,
      volume: message['volume'] as double,
      sampleRate: message['sampleRate'] as int,
      channels: message['channels'] as int,
      format: message['format'] as String?,
      outputLatency: Duration(microseconds: message['outputLatency'] as int),
      error: error == null
          ? null
          : NativeAudioError(error, operation: message['operation'] as String),
    );
  }
}

class NativeAudioMetadata {
  const NativeAudioMetadata({
    required this.sampleRate,
    required this.channels,
    required this.totalFrames,
    required this.format,
  });
  final int sampleRate;
  final int channels;
  final int totalFrames;
  final String format;
  Duration get duration => Duration(
    microseconds: (totalFrames * Duration.microsecondsPerSecond) ~/ sampleRate,
  );
}

class NativeAudioWaveform {
  const NativeAudioWaveform({required this.metadata, required this.peaks});
  final NativeAudioMetadata metadata;

  /// Maximum absolute sample amplitude in each bin, clamped to 0..1.
  final List<double> peaks;
}

/// Captured manual-output frames for deterministic PCM regression tests.
class NativeAudioTestBlock {
  const NativeAudioTestBlock(this.samples, this.consumedFrames, this.channels);
  final Float32List samples;
  final int consumedFrames;
  final int channels;
}
