// SPDX-License-Identifier: MIT
import 'types.dart';

class NativeAudioPlayer {
  NativeAudioPlayer({
    this.engine = NativeSpeedEngine.sonic,
    String? libraryPath,
    this.testOutput = false,
    this.bufferFrames = 8192,
  });
  final NativeSpeedEngine engine;
  final bool testOutput;
  final int bufferFrames;
  Never _unsupported() => throw UnsupportedError(
    'Native PCM playback requires a native desktop platform',
  );
  Stream<NativeAudioSnapshot> get snapshots => const Stream.empty();
  Stream<NativeAudioError> get errors => const Stream.empty();
  NativeAudioSnapshot get snapshot => const NativeAudioSnapshot();
  NativeAudioState get state => snapshot.state;
  bool get playing => snapshot.playing;
  Duration get position => snapshot.position;
  Duration get duration => snapshot.duration;
  int? get index => snapshot.index;
  Future<NativeAudioSnapshot> load(
    List<String> paths, {
    int index = 0,
    Duration position = Duration.zero,
  }) async => _unsupported();
  Future<void> play() async => _unsupported();
  Future<void> pause() async => _unsupported();
  Future<void> stop() async => _unsupported();
  Future<void> seek(Duration position, {int? index}) async => _unsupported();
  Future<void> setSpeed(double speed) async => _unsupported();
  Future<void> setVolume(double volume) async => _unsupported();
  Future<int> pump(int frames) async => _unsupported();
  Future<NativeAudioTestBlock> renderForTest(int frames) async =>
      _unsupported();
  Future<void> dispose() async {}
}
