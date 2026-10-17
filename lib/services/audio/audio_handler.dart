import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class CrispAudioHandler extends BaseAudioHandler {
  final AudioPlayer player;
  CrispAudioHandler(this.player) {
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    // forward player errors
  }

  PlaybackState _transformEvent(PlaybackEvent e) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0,1,2],
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
      queueIndex: e.currentIndex,
    );
  }

  Future<void> setQueue(List<MediaItem> items) async {
    queue.add(items);
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() async { await player.stop(); await super.stop(); }
  @override
  Future<void> seek(Duration pos) => player.seek(pos);
  @override
  Future<void> skipToNext() => player.seekToNext();
  @override
  Future<void> skipToPrevious() => player.seekToPrevious();
  @override
  Future<void> setSpeed(double s) => player.setSpeed(s);
}
