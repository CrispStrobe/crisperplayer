import 'package:just_audio/just_audio.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed, error }

class PlaybackState {
  final PlaybackStatus status;
  final Duration position;
  final Duration buffered;
  final Duration duration;
  final double speed;
  final double volume;
  final int currentIndex; // index in queue
  final String? currentFile;
  final String? error;

  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.currentIndex = 0,
    this.currentFile,
    this.error,
  });

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? buffered,
    Duration? duration,
    double? speed,
    double? volume,
    int? currentIndex,
    String? currentFile,
    String? error,
  }) =>
      PlaybackState(
        status: status ?? this.status,
        position: position ?? this.position,
        buffered: buffered ?? this.buffered,
        duration: duration ?? this.duration,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        currentIndex: currentIndex ?? this.currentIndex,
        currentFile: currentFile ?? this.currentFile,
        error: error,
      );

  double get progress => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}

extension PlayerStateX on PlayerState {
  PlaybackStatus toStatus() {
    if (processingState == ProcessingState.loading ||
        processingState == ProcessingState.buffering) {
      return PlaybackStatus.loading;
    }
    if (processingState == ProcessingState.completed) {
      return PlaybackStatus.completed;
    }
    return playing ? PlaybackStatus.playing : PlaybackStatus.paused;
  }
}
