import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

/// The player boundary used by playback coordination and its regression tests.
abstract interface class AudioBackend {
  bool get supportsSkipSilence;
  Duration get position;
  Duration? get duration;
  int get currentIndex;
  bool get playing;
  Stream<Duration> get positions;
  Stream<PlayerState> get states;
  Stream<Duration?> get durations;
  Stream<int?> get indices;
  Future<void> load(List<String> paths,
      {required int index, required Duration position});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {int? index});
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> setSkipSilence(bool enabled);
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  final AudioPlayer player;
  JustAudioBackend(this.player);
  @override
  bool get supportsSkipSilence =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Duration get position => player.position;
  @override
  Duration? get duration => player.duration;
  @override
  int get currentIndex => player.currentIndex ?? 0;
  @override
  bool get playing => player.playing;
  @override
  Stream<Duration> get positions => player.positionStream;
  @override
  Stream<PlayerState> get states => player.playerStateStream;
  @override
  Stream<Duration?> get durations => player.durationStream;
  @override
  Stream<int?> get indices => player.currentIndexStream;
  @override
  Future<void> load(List<String> paths,
      {required int index, required Duration position}) async {
    await player.setAudioSources(
      paths.map((path) => AudioSource.uri(Uri.file(path))).toList(),
      initialIndex: index,
      initialPosition: position,
    );
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position, {int? index}) =>
      player.seek(position, index: index);
  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<void> setSkipSilence(bool enabled) async {
    if (supportsSkipSilence) await player.setSkipSilenceEnabled(enabled);
  }

  @override
  Future<void> dispose() => player.dispose();
}
