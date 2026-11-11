// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'cancellation.dart';
import 'decoder.dart';
import 'dsp.dart';
import 'library.dart';
import 'output.dart';
import 'source_clock.dart';
import 'types.dart';

class _Request {
  _Request(this.generation);
  final int generation;
  final completer = Completer<Object?>();
}

/// Decoder, DSP, and output handles live in one worker isolate. Native output
/// consumes its own bounded queue; no realtime callback enters Dart.
class NativeAudioPlayer {
  NativeAudioPlayer({
    this.engine = NativeSpeedEngine.sonic,
    String? libraryPath,
    this.testOutput = false,
    this.bufferFrames = 8192,
  }) {
    if (bufferFrames < 512 || bufferFrames > 65536) {
      throw RangeError.range(bufferFrames, 512, 65536, 'bufferFrames');
    }
    _messages.listen(_receive);
    _workerErrors.listen((Object? message) {
      _failed(NativeAudioError('Worker failed: $message', operation: 'worker'));
    });
    _workerExit.listen((_) {
      if (!_exited.isCompleted) _exited.complete();
      if (!_disposing && !_disposed) {
        _failed(
          const NativeAudioError('Audio worker exited', operation: 'worker'),
        );
      }
    });
    // Initialization can fail before the caller starts a transport request.
    unawaited(
      _ready.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    _spawnFuture = _spawn(libraryPath);
    unawaited(_spawnFuture);
  }

  final NativeSpeedEngine engine;
  final bool testOutput;
  final int bufferFrames;
  final _messages = ReceivePort();
  final _workerErrors = ReceivePort();
  final _workerExit = ReceivePort();
  final _ready = Completer<SendPort>();
  final _exited = Completer<void>();
  final _requests = <int, _Request>{};
  final _snapshots = StreamController<NativeAudioSnapshot>.broadcast(
    sync: true,
  );
  final _errors = StreamController<NativeAudioError>.broadcast(sync: true);
  NativeAudioSnapshot _snapshot = const NativeAudioSnapshot();
  NativeAudioError? _workerFailure;
  Isolate? _isolate;
  late final Future<void> _spawnFuture;
  NativeCancellation? _cancellation;
  int _nextId = 0, _generation = 0;
  bool _disposing = false, _disposed = false;
  Future<void>? _disposeFuture;

  Stream<NativeAudioSnapshot> get snapshots => _snapshots.stream;
  Stream<NativeAudioError> get errors => _errors.stream;
  NativeAudioSnapshot get snapshot => _snapshot;
  NativeAudioState get state => _snapshot.state;
  bool get playing => _snapshot.playing;
  Duration get position => _snapshot.position;
  Duration get duration => _snapshot.duration;
  int? get index => _snapshot.index;

  Future<void> _spawn(String? libraryPath) async {
    try {
      _cancellation = NativeCancellation(openNativeLibrary(path: libraryPath));
      _isolate = await Isolate.spawn<List<Object?>>(
        _workerMain,
        [
          _messages.sendPort,
          libraryPath,
          engine.index,
          testOutput,
          bufferFrames,
          _cancellation!.address,
        ],
        onError: _workerErrors.sendPort,
        onExit: _workerExit.sendPort,
        errorsAreFatal: true,
        debugName: 'crisper-audio',
      );
    } catch (error) {
      _failed(NativeAudioError('$error', operation: 'initialize'));
    }
  }

  void _failed(NativeAudioError error) {
    if (_workerFailure != null || _disposed) return;
    _workerFailure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _requests.values) {
      request.completer.completeError(error);
    }
    _requests.clear();
    _snapshot = NativeAudioSnapshot(
      position: _snapshot.position,
      duration: _snapshot.duration,
      index: _snapshot.index,
      speed: _snapshot.speed,
      volume: _snapshot.volume,
      error: error,
    );
    _snapshots.add(_snapshot);
    _errors.add(error);
  }

  void _receive(Object? message) {
    if (_disposed) return;
    if (message is SendPort) {
      if (!_ready.isCompleted) _ready.complete(message);
      return;
    }
    final data = message! as Map<Object?, Object?>;
    if (data['type'] == 'initializationError') {
      _failed(
        NativeAudioError(data['error']! as String, operation: 'initialize'),
      );
      return;
    }
    final current = data['generation'] == _generation;
    if (current && data['snapshot'] != null) {
      _snapshot = NativeAudioSnapshot.fromMessage(
        data['snapshot']! as Map<Object?, Object?>,
      );
      _snapshots.add(_snapshot);
    }
    if (data['type'] == 'error' && current) {
      _errors.add(
        NativeAudioError(
          data['error']! as String,
          operation: data['operation']! as String,
        ),
      );
    }
    if (data['type'] == 'response') {
      final request = _requests.remove(data['id']);
      if (request == null) return;
      if (data['error'] != null) {
        request.completer.completeError(
          NativeAudioError(
            data['error']! as String,
            operation: data['operation']! as String,
          ),
        );
      } else {
        request.completer.complete(data['value']);
      }
    }
  }

  Future<Object?> _request(
    String method, [
    Map<String, Object?> arguments = const {},
    bool supersedes = false,
  ]) async {
    if (_disposed || (_disposing && method != 'dispose')) {
      throw StateError('NativeAudioPlayer is disposed');
    }
    if (_workerFailure != null) throw _workerFailure!;
    if (supersedes) {
      _generation++;
      _cancellation?.generation = _generation;
      for (final request in _requests.values) {
        request.completer.completeError(const NativeAudioCancelled());
      }
      _requests.clear();
    }
    final generation = _generation;
    final port = await _ready.future;
    if (generation != _generation) throw const NativeAudioCancelled();
    final id = ++_nextId;
    final request = _Request(generation);
    _requests[id] = request;
    port.send({
      'id': id,
      'generation': generation,
      'method': method,
      ...arguments,
    });
    return request.completer.future;
  }

  Future<NativeAudioSnapshot> load(
    List<String> paths, {
    int index = 0,
    Duration position = Duration.zero,
  }) async {
    if (paths.isEmpty) {
      throw ArgumentError.value(paths, 'paths', 'Must not be empty');
    }
    if (index < 0 || index >= paths.length) {
      throw RangeError.index(index, paths);
    }
    if (position.isNegative) throw ArgumentError.value(position, 'position');
    await _request('load', {
      'paths': List<String>.of(paths),
      'index': index,
      'position': position.inMicroseconds,
    }, true);
    return _snapshot;
  }

  Future<void> play() async => _request('play');
  Future<void> pause() async => _request('pause');
  Future<void> stop() async => _request('stop', const {}, true);
  Future<void> seek(Duration position, {int? index}) async {
    if (position.isNegative) throw ArgumentError.value(position, 'position');
    if (index != null && index < 0) throw RangeError.value(index, 'index');
    await _request('seek', {
      'position': position.inMicroseconds,
      'index': index,
    }, true);
  }

  Future<void> setSpeed(double speed) async {
    if (!speed.isFinite || speed < 0.5 || speed > 3) {
      throw RangeError.value(speed, 'speed', 'Expected 0.5 through 3.0');
    }
    await _request('speed', {'speed': speed}, true);
  }

  Future<void> setVolume(double volume) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
    await _request('volume', {'volume': volume});
  }

  /// Advances the deterministic output sink. Available only with testOutput.
  Future<int> pump(int frames) async {
    if (!testOutput) throw StateError('Manual pump requires testOutput');
    if (frames < 0 || frames > 1 << 24) {
      throw RangeError.value(frames, 'frames');
    }
    return (await _request('pump', {'frames': frames}))! as int;
  }

  /// Captures callback PCM, including underrun silence. Only testOutput allows
  /// this operation; ordinary playback never copies PCM into the UI isolate.
  Future<NativeAudioTestBlock> renderForTest(int frames) async {
    if (!testOutput) throw StateError('Capture requires testOutput');
    if (frames < 1 || frames > 65536) throw RangeError.range(frames, 1, 65536);
    return (await _request('render', {'frames': frames}))!
        as NativeAudioTestBlock;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();
  Future<void> _dispose() async {
    _disposing = true;
    try {
      if (_workerFailure == null) await _request('dispose', const {}, true);
    } finally {
      // A worker may report initialization failure before Isolate.spawn's
      // Future assigns its handle. Join that creation before freeing its token.
      await _spawnFuture;
      if (_isolate != null) {
        if (_workerFailure != null) _isolate!.kill(priority: Isolate.immediate);
        await _exited.future;
      }
      _cancellation?.dispose();
      _disposed = true;
      _messages.close();
      _workerErrors.close();
      _workerExit.close();
      await _snapshots.close();
      await _errors.close();
    }
  }
}

void _workerMain(List<Object?> arguments) {
  final client = arguments[0]! as SendPort;
  try {
    final worker = _PlayerWorker(
      client,
      openNativeLibrary(path: arguments[1] as String?),
      NativeSpeedEngine.values[arguments[2]! as int],
      arguments[3]! as bool,
      arguments[4]! as int,
      arguments[5]! as int,
    );
    worker.run();
  } catch (error) {
    client.send({'type': 'initializationError', 'error': '$error'});
  }
}

class _PlayerWorker {
  _PlayerWorker(
    this.client,
    this.library,
    this.engine,
    this.manual,
    this.capacity,
    int cancellationAddress,
  ) : cancellation = NativeCancellation(
        library,
        borrowedAddress: cancellationAddress,
      );
  final SendPort client;
  final DynamicLibrary library;
  final NativeSpeedEngine engine;
  final bool manual;
  final int capacity;
  final NativeCancellation cancellation;
  final _port = ReceivePort();
  final _clock = SourceClock();
  Timer? _timer;
  PcmDecoder? _decoder;
  NativeDsp? _dsp;
  NativeOutput? _output;
  Pointer<Float> _input = nullptr, _pcm = nullptr;
  static const _block = 2048;
  int _inputFrames = 0, _inputOffset = 0, _pcmFrames = 0, _pcmOffset = 0;
  int _submitted = 0, _startFrame = 0, _positionFrame = 0, _totalFrames = 0;
  int _sampleRate = 0, _channels = 0, _generation = 0;
  int? _index;
  String? _format, _failure, _failureOperation;
  bool _eof = false, _finished = false, _playing = false;
  bool _interrupted = false;
  double _speed = 1, _volume = 1;
  List<String> _paths = [];
  NativeAudioState _state = NativeAudioState.idle;
  int _lastNotification = 0;

  void run() {
    _port.listen(
      (Object? message) => _command(message! as Map<Object?, Object?>),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      try {
        _tick();
      } on NativeAudioCancelled {
        _interrupt();
      } catch (error) {
        _fail(error, 'playback');
      }
    });
    client.send(_port.sendPort);
  }

  int _micros(int frames) =>
      _sampleRate == 0 ? 0 : frames * 1000000 ~/ _sampleRate;
  Map<String, Object?> _snapshot() => {
    'state': _state.index,
    'playing': _playing,
    'position': _micros(_positionFrame),
    'duration': _micros(_totalFrames),
    'index': _index,
    'speed': _speed,
    'volume': _volume,
    'sampleRate': _sampleRate,
    'channels': _channels,
    'format': _format,
    'outputLatency': _micros(_output?.latency ?? 0),
    'error': _failure,
    'operation': _failureOperation ?? 'playback',
  };
  void _notify({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastNotification < 25) return;
    _lastNotification = now;
    client.send({
      'type': 'snapshot',
      'generation': _generation,
      'snapshot': _snapshot(),
    });
  }

  void _fail(Object error, String operation) {
    if (_failure != null) return;
    _failure = '$error';
    _failureOperation = operation;
    _playing = false;
    _state = NativeAudioState.idle;
    _closePipeline();
    client.send({
      'type': 'error',
      'generation': _generation,
      'error': _failure,
      'operation': operation,
      'snapshot': _snapshot(),
    });
  }

  void _command(Map<Object?, Object?> command) {
    final method = command['method']! as String;
    _generation = command['generation']! as int;
    Object? value;
    String? error;
    try {
      _checkCancelled();
      if (_failure != null && !{'load', 'dispose', 'stop'}.contains(method)) {
        throw StateError(_failure!);
      }
      switch (method) {
        case 'load':
          _playing = false;
          _paths = List<String>.from(command['paths']! as List);
          _failure = _failureOperation = null;
          _open(command['index']! as int, command['position']! as int);
        case 'play':
          if (_paths.isEmpty) throw StateError('Load a source before playing');
          if (_decoder == null) {
            _open(_index ?? 0, 0, sourceFrame: _positionFrame);
          }
          _playing = true;
          if (_state != NativeAudioState.completed) {
            _fill();
            _output!.start();
            _tick();
          }
        case 'pause':
          _output?.pause();
          _updatePosition();
          _playing = false;
        case 'stop':
          _output?.pause();
          _updatePosition();
          _playing = false;
          _closePipeline();
          _interrupted = false;
          _state = NativeAudioState.idle;
        case 'seek':
          if (_paths.isEmpty) throw StateError('Load a source before seeking');
          _open(
            command['index'] as int? ?? _index ?? 0,
            command['position']! as int,
          );
        case 'speed':
          _updatePosition();
          _speed = command['speed']! as double;
          if (_decoder != null || _interrupted) {
            _open(_index ?? 0, 0, sourceFrame: _positionFrame);
          }
        case 'volume':
          _volume = command['volume']! as double;
          _output?.setVolume(_volume);
        case 'pump':
          if (!manual) throw StateError('Not a manual output');
          _tick();
          value = _output?.pump(command['frames']! as int) ?? 0;
          _tick();
        case 'render':
          if (!manual) throw StateError('Not a manual output');
          _tick();
          final count = command['frames']! as int;
          final channels = _channels;
          if (channels < 1 || _output == null) {
            throw StateError('No loaded PCM');
          }
          final capture = calloc<Float>(count * channels);
          try {
            final consumed = _output!.render(capture, count);
            value = NativeAudioTestBlock(
              Float32List.fromList(capture.asTypedList(count * channels)),
              consumed,
              channels,
            );
          } finally {
            calloc.free(capture);
          }
          _tick();
        case 'dispose':
          _playing = false;
          _closePipeline();
          _timer?.cancel();
          _port.close();
        default:
          throw ArgumentError('Unknown transport command $method');
      }
    } on NativeAudioCancelled {
      _interrupt();
      error = 'Transport request superseded';
    } catch (caught) {
      error = '$caught';
      _fail(caught, method);
    }
    client.send({
      'type': 'response',
      'id': command['id'],
      'generation': _generation,
      'value': value,
      'error': error,
      'operation': method,
      'snapshot': _snapshot(),
    });
  }

  void _closePipeline() {
    // Stop callbacks and release output before freeing queued DSP/source memory.
    _output?.dispose();
    _output = null;
    _dsp?.dispose();
    _dsp = null;
    _decoder?.dispose();
    _decoder = null;
    if (_input != nullptr) calloc.free(_input);
    if (_pcm != nullptr) calloc.free(_pcm);
    _input = _pcm = nullptr;
    _inputFrames = _inputOffset = _pcmFrames = _pcmOffset = 0;
    _submitted = 0;
    _clock.reset();
  }

  void _checkCancelled() {
    if (cancellation.generation != _generation) {
      throw const NativeAudioCancelled();
    }
  }

  void _interrupt() {
    _closePipeline();
    _interrupted = true;
  }

  void _open(int index, int microseconds, {int? sourceFrame}) {
    _checkCancelled();
    if (index < 0 || index >= _paths.length) {
      throw RangeError.index(index, _paths);
    }
    _closePipeline();
    _interrupted = false;
    _state = NativeAudioState.loading;
    // Publish loading before changing source identity: observers must stop
    // attributing presented positions to the previous track first.
    _notify(force: true);
    final epoch = _generation;
    final decoder = PcmDecoder.open(
      _paths[index],
      library: library,
      checkCancelled: () {
        if (cancellation.generation != epoch) {
          throw const NativeAudioCancelled();
        }
      },
    );
    _decoder = decoder;
    _index = index;
    _sampleRate = decoder.sampleRate;
    _channels = decoder.channels;
    _totalFrames = decoder.totalFrames;
    _format = decoder.format;
    if (_channels < 1 || _channels > 2 || _sampleRate <= 0) {
      throw FormatException(
        'Unsupported PCM format: $_sampleRate Hz, $_channels channels',
      );
    }
    decoder.seek(
      math.min(
        _totalFrames,
        sourceFrame ?? microseconds * _sampleRate ~/ 1000000,
      ),
    );
    _startFrame = _positionFrame = decoder.positionFrames;
    _dsp = NativeDsp(library, engine, _sampleRate, _channels, _speed);
    _output = NativeOutput(
      library,
      _sampleRate,
      _channels,
      capacity: capacity,
      manual: manual,
    );
    _output!.setVolume(_volume);
    _input = calloc<Float>(_block * _channels);
    _pcm = calloc<Float>(_block * _channels);
    _eof = _finished = false;
    _state = NativeAudioState.buffering;
    _fill();
    _state = NativeAudioState.ready;
    if (_playing) _output!.start();
    _notify(force: true);
  }

  void _updatePosition() {
    final output = _output;
    if (output == null) return;
    output.checkError();
    final presented = output.presented;
    if (presented > _submitted) {
      throw StateError('Native output clock exceeds submitted PCM');
    }
    _positionFrame = math.min(
      _totalFrames,
      _startFrame + _clock.presented(presented),
    );
  }

  void _fill() {
    final output = _output!, dsp = _dsp!, decoder = _decoder!;
    final budget = Stopwatch()..start();
    var stalled = 0;
    for (var step = 0; step < 96 && budget.elapsedMilliseconds < 8; step++) {
      _checkCancelled();
      if (_pcmOffset < _pcmFrames) {
        final accepted = output.write(
          _pcm + _pcmOffset * _channels,
          _pcmFrames - _pcmOffset,
        );
        _pcmOffset += accepted;
        _submitted += accepted;
        if (accepted == 0) break;
        continue;
      }
      final free = capacity - output.buffered;
      if (free <= 0) break;
      final frames = dsp.read(_pcm, math.min(_block, free));
      if (frames > 0) {
        _clock.append(dsp.outputFrames, dsp.sourceFrames);
        _pcmFrames = frames;
        _pcmOffset = 0;
        stalled = 0;
        continue;
      }
      if (dsp.ended) {
        _finished = true;
        break;
      }
      if (_inputOffset < _inputFrames) {
        final consumed = dsp.write(
          _input + _inputOffset * _channels,
          _inputFrames - _inputOffset,
        );
        _inputOffset += consumed;
        if (consumed == 0 && ++stalled > 8) {
          throw StateError('DSP input/output made no progress');
        }
        continue;
      }
      if (_eof) {
        if (++stalled > 8) throw StateError('DSP drain made no progress');
        dsp.finish();
        continue;
      }
      _inputFrames = decoder.readFrames(_input, _block);
      _inputOffset = 0;
      if (_inputFrames == 0) {
        _eof = true;
        dsp.finish();
      }
    }
  }

  void _tick() {
    if (_output == null || _failure != null) return;
    _updatePosition();
    if (_playing && _state != NativeAudioState.completed) {
      _fill();
      _updatePosition();
      if (_finished &&
          _pcmOffset == _pcmFrames &&
          _output!.presented == _submitted) {
        _positionFrame = _totalFrames;
        _notify(force: true);
        if (_index! + 1 < _paths.length) {
          _open(_index! + 1, 0);
        } else {
          _output!.pause();
          _state = NativeAudioState.completed;
          _notify(force: true);
        }
      } else {
        _state = _output!.buffered == 0 && _output!.presented == _submitted
            ? NativeAudioState.buffering
            : NativeAudioState.ready;
      }
    }
    _notify();
  }
}
