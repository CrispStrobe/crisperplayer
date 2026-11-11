// SPDX-License-Identifier: MIT
import 'dart:ffi';
import 'dart:io';

typedef _AbiNative = Int32 Function();
typedef _Abi = int Function();

/// Opens the bundled native library and verifies its output ABI.
///
/// Tests may pass an absolute [path] or CRISPER_AUDIO_LIBRARY_PATH. An explicit
/// override is authoritative: an incompatible library produces an error and
/// never silently falls back to a different installed version.
DynamicLibrary openNativeLibrary({String? path}) {
  DynamicLibrary checked(String file) {
    final library = DynamicLibrary.open(file);
    final version = library.lookupFunction<_AbiNative, _Abi>(
      'ca_output_abi_version',
    )();
    if (version != 1) {
      throw StateError(
        'Unsupported crisper_audio output ABI $version in $file',
      );
    }
    return library;
  }

  final override = path ?? Platform.environment['CRISPER_AUDIO_LIBRARY_PATH'];
  if (override != null && override.isNotEmpty) return checked(override);

  final executable = File(Platform.resolvedExecutable).parent;
  final separator = Platform.pathSeparator;
  final candidates = <String>[
    if (Platform.isWindows) '${executable.path}${separator}crisper_audio.dll',
    if (Platform.isLinux) ...[
      '${executable.path}/lib/libcrisper_audio.so',
      '${executable.path}/libcrisper_audio.so',
    ],
    // Standalone macOS CMake/FFI tests are supported. The Flutter app keeps
    // its existing Apple backend and does not compile this plugin there.
    if (Platform.isMacOS) ...[
      '${executable.path}/libcrisper_audio.dylib',
      '${executable.parent.path}/Frameworks/crisper_audio.framework/crisper_audio',
    ],
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return checked(candidate);
  }
  throw StateError(
    'The bundled crisper_audio library was not found for '
    '${Platform.operatingSystem}. Build the desktop application, or set '
    'CRISPER_AUDIO_LIBRARY_PATH for native tests.',
  );
}
