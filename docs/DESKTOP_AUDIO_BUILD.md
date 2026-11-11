# Direct native desktop audio

Windows and Linux use the local `crisper_audio` Flutter FFI package. It builds
one shared library from checked-in Glint decoder sources, the four-engine DSP
core and miniaudio output. No mpv/FFmpeg archive or codec binary is downloaded
by this build. Flutter still resolves its ordinary SDK and Dart dependencies.

## Build the application

Use the repository's pinned Flutter 3.44.4 and normal native Flutter toolchain:

```sh
flutter pub get
dart run build_runner build --build-filter lib/services/db/app_database.g.dart
flutter build linux --release
# Or on Windows with the supported Visual Studio C++ toolchain:
flutter build windows --release
```

Linux requires the GTK/libsecret development packages used by the application,
a C++20 compiler and CMake 3.22 or later. Device output uses an available native
backend such as PulseAudio or ALSA. Windows uses its native audio APIs through
miniaudio. The package does not require a system libmpv installation. Flutter's
plugin-symlink build resolves the real package source before finding the shared
DSP sibling directory.

The expected bundled libraries are:

| Target | Packaged native audio library |
| --- | --- |
| Linux | `build/linux/x64/release/bundle/lib/libcrisper_audio.so` |
| Windows | `build/windows/x64/runner/Release/crisper_audio.dll` |

The Dart loader opens these exact names relative to the executable and checks
ABI version 1. An explicit `CRISPER_AUDIO_LIBRARY_PATH` is intended for tests and
must pass the same ABI check. Missing or incompatible libraries fail visibly.

## Test the same native source independently

```sh
cmake -S packages/crisper_audio/native -B build/crisper_audio \
  -DCMAKE_BUILD_TYPE=Release -DCRISPER_AUDIO_TESTS=ON
cmake --build build/crisper_audio --config Release --parallel 2
ctest --test-dir build/crisper_audio -C Release --output-on-failure

# Linux. Use the corresponding .dylib or Release/crisper_audio.dll on other hosts.
CRISPER_REQUIRE_NATIVE_AUDIO=1 \
  CRISPER_AUDIO_LIBRARY_PATH="$PWD/build/crisper_audio/libcrisper_audio.so" \
  flutter test packages/crisper_audio/test

python scripts/audit_native_audio.py \
  --bundle build/linux/x64/release/bundle \
  --output build/license-evidence/native-audio.json
```

The source audit verifies pinned Glint/miniaudio/DSP files. The artifact audit
hashes and loads the actual library, checks the output/decoder/DSP ABIs and
rejects bundled mpv/FFmpeg-family payloads. It does not infer complete runtime
license clearance from a filename or a passing functional test.

The deterministic manual output backend uses the real callback pump. Tests
exercise partial writes, underrun silence, pause/resume, seeking, speed epochs,
end-of-file drain, cancellation, multi-track transitions and exact source-frame
accounting through every engine. A native null-device test also runs an actual
callback thread. Neither substitutes for real output-device qualification.

MP3/AAC/FLAC regression fixtures are synthetic and have recorded generation commands
and hashes. FFmpeg may be used to generate/reference test media; it is not a
runtime dependency or shipped codec in this path.

## Playback and migration limits

The direct decoder covers WAV, MP3, AAC-LC ADTS, AAC-LC M4A/M4B/MP4 and native FLAC;
see [portable coverage](PORTABLE_AUDIO_PROCESSORS.md) and the package README for
updated codec scope. It does not claim arbitrary FFmpeg codec support.
Unsupported profiles/containers produce an explicit error. Existing desktop
Automatic/Legacy/atempo preferences migrate to Sonic; all four portable choices
are available in the native library. Apple and Android defaults are unchanged.

The output position includes estimated native buffering, not a hardware/DAC
clock. The estimate excludes underrun silence and decoded lookahead, but cannot
measure unreported Bluetooth/audio-server latency. Test speakers, device changes,
interruptions and long-book behavior on each target before release.

## Provenance and distribution

Source and notices live beside the new package. The original portable DSP
closure is reused without duplicating vendor files. Glint's AAC tables now
regenerate offline from pinned Apache-2.0 vo-aacenc inputs with the complete
license/notices. The table values are unchanged and the source history is
recorded in the Glint provenance manifest.
The normal distribution checker still blocks unreviewed artifacts and missing
source/notice obligations. Removing the audio mpv/FFmpeg path does not remove
unrelated LGPL system/application dependencies.

Earlier controlled-mpv source-build evidence remains historical in
`licensing/evidence/portable_linux_*_2026-11-11.json` and commit
`30718ac0da888ccb77966d1500a22b49f716fce4`. The adapters and build recipes from
that experiment are removed from the current source path.
