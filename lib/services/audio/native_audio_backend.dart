import 'dart:async';

import 'package:crisper_audio/crisper_audio.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;

import 'audio_backend.dart';

/// Desktop transport. Dart owns decoding, seeking and the DSP pipeline; native
/// code owns the output callback. No just_audio desktop platform is registered.
class NativeAudioBackend implements AudioBackend {
  final NativeAudioPlayer _player;
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final _durations = StreamController<Duration?>.broadcast(sync: true);
  final _indices = StreamController<int?>.broadcast(sync: true);
  late final StreamSubscription<NativeAudioSnapshot> _snapshotSubscription;
  late final StreamSubscription<NativeAudioError> _errorSubscription;
  NativeAudioSnapshot? _previous;
  Future<void>? _disposing;

  NativeAudioBackend({
    NativeSpeedEngine engine = NativeSpeedEngine.sonic,
    NativeAudioPlayer? player,
  }) : _player = player ?? NativeAudioPlayer(engine: engine) {
    _snapshotSubscription = _player.snapshots.listen(_onSnapshot);
    _errorSubscription = _player.errors.listen(_states.addError);
  }

  void _onSnapshot(NativeAudioSnapshot next) {
    final previous = _previous;
    _previous = next;
    if (next.index != previous?.index) _indices.add(next.index);
    if (next.duration != previous?.duration) _durations.add(next.duration);
    if (next.position != previous?.position || next.index != previous?.index) {
      _positions.add(next.position);
    }
    if (next.state != previous?.state || next.playing != previous?.playing) {
      _states.add(_playerState(next));
    }
  }

  @override
  bool get supportsSkipSilence => false;
  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  int get currentIndex => _player.index ?? 0;
  @override
  bool get playing => _player.playing;
  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<PlayerState> get states => Stream<PlayerState>.multi((controller) {
    // Initialization can fail before PlaybackService subscribes. Each listener
    // receives the current transport state/error as well as subsequent events.
    final subscription = _states.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.onCancel = subscription.cancel;
    final current = _player.snapshot;
    controller.add(_playerState(current));
    if (current.error != null) controller.addError(current.error!);
  }, isBroadcast: true);
  @override
  Stream<Duration?> get durations => _durations.stream;
  @override
  Stream<int?> get indices => _indices.stream;

  @override
  Future<void> load(
    List<String> paths, {
    required int index,
    required Duration position,
  }) async {
    await _transport(_player.load(paths, index: index, position: position));
  }

  @override
  Future<void> play() => _transport(_player.play());
  @override
  Future<void> pause() => _transport(_player.pause());
  @override
  Future<void> stop() => _transport(_player.stop());
  @override
  Future<void> seek(Duration position, {int? index}) =>
      _transport(_player.seek(position, index: index));
  @override
  Future<void> setSpeed(double speed) => _transport(_player.setSpeed(speed));
  @override
  Future<void> setVolume(double volume) =>
      _transport(_player.setVolume(volume));
  @override
  Future<void> setSkipSilence(bool enabled) async {}

  Future<void> _transport<T>(Future<T> operation) async {
    try {
      await operation;
    } on NativeAudioCancelled {
      // A newer transport request owns playback. Real decoder/output failures
      // still reject the command and arrive on the states stream.
    }
  }

  PlayerState _playerState(NativeAudioSnapshot snapshot) =>
      PlayerState(snapshot.playing, switch (snapshot.state) {
        NativeAudioState.idle => ProcessingState.idle,
        NativeAudioState.loading => ProcessingState.loading,
        NativeAudioState.buffering => ProcessingState.buffering,
        NativeAudioState.ready => ProcessingState.ready,
        NativeAudioState.completed => ProcessingState.completed,
      });

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    try {
      await _player.dispose();
    } finally {
      await _snapshotSubscription.cancel();
      await _errorSubscription.cancel();
      await Future.wait([
        _positions.close(),
        _states.close(),
        _durations.close(),
        _indices.close(),
      ]);
    }
  }
}
