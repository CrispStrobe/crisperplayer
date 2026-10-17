import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// iOS Control Center / lockscreen handler for CrisperPlayer.
///
/// Provides:
/// - Background audio via audio_service (MPNowPlayingInfoCenter on iOS)
/// - Lock screen artwork via MediaItem.artUri (file:// URI from CoverExtractor)
/// - Remote commands: play/pause, next/prev track, seek, skip ±30s,
///   stop, speed, and headset button handling.
/// - Queue support for multi-file audiobooks (one MediaItem per file).
///
/// PlaybackService attaches via callbacks so that play/pause still trigger
/// history, bookmark and progress logic instead of bypassing them.
class CrisperAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;

  // Optional delegates — set by PlaybackService.attachAudioHandler to ensure
  // history/bookmark/session logic runs even when user taps Control Center.
  Future<void> Function()? onPlayDelegate;
  Future<void> Function()? onPauseDelegate;
  Future<void> Function()? onStopDelegate;
  Future<void> Function(Duration pos)? onSeekDelegate;
  Future<void> Function()? onSkipNextDelegate;
  Future<void> Function()? onSkipPrevDelegate;

  // Current queue for index-aware updates.
  List<MediaItem> _currentQueue = [];

  CrisperAudioHandler(
    this.player, {
    this.onPlayDelegate,
    this.onPauseDelegate,
    this.onStopDelegate,
    this.onSeekDelegate,
    this.onSkipNextDelegate,
    this.onSkipPrevDelegate,
  }) {
    // Mirror just_audio events to audio_service playbackState for
    // Control Center / lock screen / headset buttons (iOS + Android).
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  /// Bind delegate callbacks from PlaybackService without creating a
  /// circular import (handler must not import playback_service.dart).
  void setDelegates({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onStop,
    Future<void> Function(Duration pos)? onSeek,
    Future<void> Function()? onSkipNext,
    Future<void> Function()? onSkipPrev,
  }) {
    onPlayDelegate = onPlay;
    onPauseDelegate = onPause;
    onStopDelegate = onStop;
    onSeekDelegate = onSeek;
    onSkipNextDelegate = onSkipNext;
    onSkipPrevDelegate = onSkipPrev;
  }

  PlaybackState _transformEvent(PlaybackEvent e) {
    final playing = player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        // iOS shows rewind/play/forward as skipToPrevious/play/skipToNext;
        // also handle seekForward/Backward for ±30s via systemActions.
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: e.currentIndex,
      // Keep repeat/shuffle off for audiobooks.
      repeatMode: AudioServiceRepeatMode.none,
      shuffleMode: AudioServiceShuffleMode.none,
    );
  }

  // ── Queue / MediaItem API (called by PlaybackService) ──────────────────

  /// Set the full queue for a book. Each file gets its own MediaItem so
  /// iOS shows correct per-track info and supports next/prev chapter.
  Future<void> setQueueItems(List<MediaItem> items) async {
    _currentQueue = List.unmodifiable(items);
    queue.add(_currentQueue);
    // Also publish the first item as current if not already set.
    if (_currentQueue.isNotEmpty && mediaItem.valueOrNull == null) {
      mediaItem.add(_currentQueue.first);
    } else if (_currentQueue.isEmpty) {
      // Clear stale media item when queue cleared.
      // audio_service doesn't expose clear, so push empty queue and leave mediaItem as-is;
      // PlaybackService will call updateMediaItem next.
    }
  }

  /// Legacy alias for existing call sites.
  Future<void> setQueue(List<MediaItem> items) => setQueueItems(items);

  /// Update the currently displayed book/track (lockscreen artwork refresh).
  /// Call whenever book loads, track changes, or duration becomes known.
  Future<void> updateMediaItem(MediaItem item) async {
    // Keep queue in sync if item matches a queued entry (by id).
    final idx = _currentQueue.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      // Replace in queue to keep duration/artwork consistent for that track.
      final updated = List<MediaItem>.from(_currentQueue);
      updated[idx] = item;
      _currentQueue = List.unmodifiable(updated);
      queue.add(_currentQueue);
    }
    mediaItem.add(item);
  }

  /// Update media item with new duration (when probed duration arrives).
  Future<void> updateCurrentDuration(Duration duration) async {
    final current = mediaItem.valueOrNull;
    if (current != null) {
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  /// Switch current track's mediaItem when currentIndex changes (multi-file).
  Future<void> setCurrentIndex(int index) async {
    if (index >= 0 && index < _currentQueue.length) {
      mediaItem.add(_currentQueue[index]);
    }
  }

  // ── Playback controls (routed via delegates when attached) ──────────────

  @override
  Future<void> play() => onPlayDelegate?.call() ?? player.play();

  @override
  Future<void> pause() => onPauseDelegate?.call() ?? player.pause();

  @override
  Future<void> stop() async {
    if (onStopDelegate != null) {
      await onStopDelegate!.call();
    } else {
      await player.stop();
    }
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) =>
      onSeekDelegate?.call(position) ?? player.seek(position);

  @override
  Future<void> skipToNext() =>
      onSkipNextDelegate?.call() ?? player.seekToNext();

  @override
  Future<void> skipToPrevious() =>
      onSkipPrevDelegate?.call() ?? player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    // Update lockscreen immediately so user sees track change before seek completes.
    mediaItem.add(_currentQueue[index]);
    await player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> seekForward(bool begin) async {
    // Audiobook skip forward 30s (iOS Control Center fast-forward).
    if (begin) return;
    final pos = player.position + const Duration(seconds: 30);
    await seek(pos);
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) return;
    final pos = player.position - const Duration(seconds: 30);
    await seek(pos < Duration.zero ? Duration.zero : pos);
  }

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // Audiobooks don't repeat; enforce none.
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // No shuffle for audiobooks.
  }

  @override
  Future<void> seekTo(Duration position) => seek(position);

  @override
  Future<void> rewind() async {
    final pos = player.position - const Duration(seconds: 10);
    await seek(pos < Duration.zero ? Duration.zero : pos);
  }

  @override
  Future<void> fastForward() async {
    await seek(player.position + const Duration(seconds: 10));
  }

  // For onClick handling (e.g., notification tap) — just bring app to foreground
  // which Flutter does automatically; no extra work needed.
}
