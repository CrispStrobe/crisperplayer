// SPDX-License-Identifier: MIT
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

typedef _CreateNative = Pointer<Void> Function(Int32, Int32, Int32, Double);
typedef _Create = Pointer<Void> Function(int, int, int, double);
typedef _IoNative = Int32 Function(Pointer<Void>, Pointer<Float>, Int32);
typedef _Io = int Function(Pointer<Void>, Pointer<Float>, int);
typedef _IntNative = Int32 Function(Pointer<Void>);
typedef _Int = int Function(Pointer<Void>);
typedef _CountNative = Int64 Function(Pointer<Void>);
typedef _Count = int Function(Pointer<Void>);

class NativeDsp {
  NativeDsp(
    DynamicLibrary library,
    NativeSpeedEngine engine,
    int sampleRate,
    int channels,
    double speed,
  ) {
    _error = library
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'cp_dsp_last_error',
        );
    _write = library.lookupFunction<_IoNative, _Io>('cp_dsp_write_f32');
    _read = library.lookupFunction<_IoNative, _Io>('cp_dsp_read_f32');
    _finish = library.lookupFunction<_IntNative, _Int>('cp_dsp_finish');
    _ended = library.lookupFunction<_IntNative, _Int>('cp_dsp_ended');
    _source = library.lookupFunction<_CountNative, _Count>(
      'cp_dsp_source_frames',
    );
    _output = library.lookupFunction<_CountNative, _Count>(
      'cp_dsp_output_frames',
    );
    _destroy = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('cp_dsp_destroy');
    const ids = <NativeSpeedEngine, int>{
      NativeSpeedEngine.sonic: 0,
      NativeSpeedEngine.bungee: 1,
      NativeSpeedEngine.signalsmith: 2,
      NativeSpeedEngine.wsola: 3,
    };
    _handle = library.lookupFunction<_CreateNative, _Create>('cp_dsp_create')(
      ids[engine]!,
      sampleRate,
      channels,
      speed,
    );
    if (_handle == nullptr) throw StateError(_error().toDartString());
  }
  late Pointer<Void> _handle;
  late final Pointer<Utf8> Function() _error;
  late final _Io _write, _read;
  late final _Int _finish, _ended;
  late final _Count _source, _output;
  late final void Function(Pointer<Void>) _destroy;

  int _check(int value) {
    if (value < 0) throw StateError(_error().toDartString());
    return value;
  }

  int write(Pointer<Float> samples, int frames) =>
      _check(_write(_handle, samples, frames));
  int read(Pointer<Float> samples, int frames) =>
      _check(_read(_handle, samples, frames));
  void finish() => _check(_finish(_handle));
  bool get ended => _check(_ended(_handle)) != 0;
  int get sourceFrames => _check(_source(_handle));
  int get outputFrames => _check(_output(_handle));
  void dispose() {
    if (_handle != nullptr) _destroy(_handle);
    _handle = nullptr;
  }
}
