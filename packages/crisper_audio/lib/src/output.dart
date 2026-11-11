// SPDX-License-Identifier: MIT
import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _CreateNative =
    Pointer<Void> Function(Int32, Int32, Uint32, Uint32, Int32);
typedef _Create = Pointer<Void> Function(int, int, int, int, int);
typedef _CommandNative = Int32 Function(Pointer<Void>);
typedef _Command = int Function(Pointer<Void>);
typedef _CountNative = Uint64 Function(Pointer<Void>);
typedef _Count = int Function(Pointer<Void>);
typedef _SizeNative = Uint32 Function(Pointer<Void>);
typedef _Size = int Function(Pointer<Void>);

class NativeOutput {
  NativeOutput(
    DynamicLibrary library,
    int sampleRate,
    int channels, {
    required this.capacity,
    bool manual = false,
  }) {
    _error = library
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>),
          Pointer<Utf8> Function(Pointer<Void>)
        >('ca_output_error');
    _start = library.lookupFunction<_CommandNative, _Command>(
      'ca_output_start',
    );
    _pause = library.lookupFunction<_CommandNative, _Command>(
      'ca_output_pause',
    );
    _reset = library.lookupFunction<_CommandNative, _Command>(
      'ca_output_reset',
    );
    _buffered = library.lookupFunction<_SizeNative, _Size>(
      'ca_output_buffered_frames',
    );
    _latency = library.lookupFunction<_SizeNative, _Size>(
      'ca_output_latency_frames',
    );
    _presented = library.lookupFunction<_CountNative, _Count>(
      'ca_output_presented_frames',
    );
    _underrun = library.lookupFunction<_CountNative, _Count>(
      'ca_output_underrun_frames',
    );
    _write = library
        .lookupFunction<
          Uint32 Function(Pointer<Void>, Pointer<Float>, Uint32),
          int Function(Pointer<Void>, Pointer<Float>, int)
        >('ca_output_write');
    _pump = library
        .lookupFunction<
          Uint32 Function(Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int)
        >('ca_output_pump');
    _render = library
        .lookupFunction<
          Uint32 Function(Pointer<Void>, Pointer<Float>, Uint32),
          int Function(Pointer<Void>, Pointer<Float>, int)
        >('ca_output_test_render');
    _volume = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Float),
          int Function(Pointer<Void>, double)
        >('ca_output_set_volume');
    _destroy = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('ca_output_destroy');
    _handle = library.lookupFunction<_CreateNative, _Create>(
      'ca_output_create',
    )(sampleRate, channels, capacity, 512, manual ? 2 : 0);
    if (_handle == nullptr) throw StateError(_error(_handle).toDartString());
  }
  final int capacity;
  late Pointer<Void> _handle;
  late final Pointer<Utf8> Function(Pointer<Void>) _error;
  late final _Command _start, _pause, _reset;
  late final _Size _buffered, _latency;
  late final _Count _presented, _underrun;
  late final int Function(Pointer<Void>, Pointer<Float>, int) _write;
  late final int Function(Pointer<Void>, int) _pump;
  late final int Function(Pointer<Void>, Pointer<Float>, int) _render;
  late final int Function(Pointer<Void>, double) _volume;
  late final void Function(Pointer<Void>) _destroy;

  void checkError() {
    final error = _error(_handle).toDartString();
    if (error.isNotEmpty) throw StateError(error);
  }

  void _check(int result) {
    if (result < 0) {
      checkError();
      throw StateError('Native audio output command failed');
    }
  }

  void start() => _check(_start(_handle));
  void pause() => _check(_pause(_handle));
  void reset() => _check(_reset(_handle));
  void setVolume(double value) => _check(_volume(_handle, value));
  int write(Pointer<Float> samples, int frames) {
    final count = _write(_handle, samples, frames);
    checkError();
    return count;
  }

  int pump(int frames) {
    final count = _pump(_handle, frames);
    checkError();
    return count;
  }

  int render(Pointer<Float> samples, int frames) {
    final count = _render(_handle, samples, frames);
    checkError();
    return count;
  }

  int get buffered => _buffered(_handle);
  int get latency => _latency(_handle);
  int get presented => _presented(_handle);
  int get underrun => _underrun(_handle);
  void dispose() {
    if (_handle != nullptr) _destroy(_handle);
    _handle = nullptr;
  }
}
