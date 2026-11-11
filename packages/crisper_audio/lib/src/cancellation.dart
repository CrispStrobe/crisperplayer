// SPDX-License-Identifier: MIT
import 'dart:ffi';

/// A main-isolate-owned atomic generation, borrowed until ordered worker
/// cleanup. It can interrupt synchronous scans without abandoning FFI handles.
class NativeCancellation {
  NativeCancellation(DynamicLibrary library, {int? borrowedAddress}) {
    _set = library
        .lookupFunction<
          Void Function(Pointer<Void>, Uint64),
          void Function(Pointer<Void>, int)
        >('ca_cancel_set');
    _get = library
        .lookupFunction<
          Uint64 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('ca_cancel_get');
    _destroy = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('ca_cancel_destroy');
    _owned = borrowedAddress == null;
    _handle = borrowedAddress == null
        ? library.lookupFunction<
            Pointer<Void> Function(),
            Pointer<Void> Function()
          >('ca_cancel_create')()
        : Pointer<Void>.fromAddress(borrowedAddress);
    if (_handle == nullptr) {
      throw StateError('Could not allocate cancellation token');
    }
  }
  late Pointer<Void> _handle;
  late final bool _owned;
  late final void Function(Pointer<Void>, int) _set;
  late final int Function(Pointer<Void>) _get;
  late final void Function(Pointer<Void>) _destroy;
  int get address => _handle.address;
  int get generation => _get(_handle);
  set generation(int value) => _set(_handle, value);
  void dispose() {
    if (_owned && _handle != nullptr) _destroy(_handle);
    _handle = nullptr;
  }
}
