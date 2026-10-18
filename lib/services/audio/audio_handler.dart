import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Publishes native media controls. Every command delegates to PlaybackService.
class CrisperAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player;
  late final StreamSubscription<PlaybackEvent> _events;
  Future<void> Function()? _play,
      _pause,
      _stop,
      _next,
      _previous,
      _forward,
      _backward;
  Future<void> Function(Duration)? _seek;
  Future<void> Function(int, [Duration])? _seekIndex;
  Future<void> Function(double)? _speed;
  CrisperAudioHandler(this.player) {
    _events = player.playbackEventStream.listen((event) {
      playbackState.add(PlaybackState(
        controls: [
          MediaControl.rewind,
          if (player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          MediaControl.stop
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
      ));
    }, onError: (Object error) {
      playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorCode: 1,
          errorMessage: error.toString()));
    });
  }
  void setDelegates(
      {required Future<void> Function() onPlay,
      required Future<void> Function() onPause,
      required Future<void> Function() onStop,
      required Future<void> Function(Duration) onSeek,
      required Future<void> Function() onSkipNext,
      required Future<void> Function() onSkipPrev,
      required Future<void> Function(int, [Duration]) onSeekIndex,
      required Future<void> Function(double) onSpeed,
      required Future<void> Function() onForward,
      required Future<void> Function() onBackward}) {
    _play = onPlay;
    _pause = onPause;
    _stop = onStop;
    _seek = onSeek;
    _next = onSkipNext;
    _previous = onSkipPrev;
    _seekIndex = onSeekIndex;
    _speed = onSpeed;
    _forward = onForward;
    _backward = onBackward;
  }

  Future<void> setQueueItems(List<MediaItem> items) async {
    queue.add(List.unmodifiable(items));
    mediaItem.add(items.isEmpty ? null : items.first);
  }

  Future<void> setCurrentIndex(int index) async {
    final items = queue.value;
    if (index >= 0 && index < items.length) mediaItem.add(items[index]);
  }

  @override
  Future<void> play() async {
    await _play?.call();
  }

  @override
  Future<void> pause() async {
    await _pause?.call();
  }

  @override
  Future<void> stop() async {
    await _stop?.call();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _seek?.call(position);
  }

  @override
  Future<void> skipToNext() async {
    await _next?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await _previous?.call();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _seekIndex?.call(index);
  }

  @override
  Future<void> seekForward(bool begin) async {
    if (!begin) await _forward?.call();
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (!begin) await _backward?.call();
  }

  @override
  Future<void> fastForward() async {
    await _forward?.call();
  }

  @override
  Future<void> rewind() async {
    await _backward?.call();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _speed?.call(speed);
  }

  Future<void> dispose() async {
    await _events.cancel();
    await super.stop();
  }
}
