# crisper_audio

Direct Dart FFI playback for CrisperPlayer's Windows and Linux applications.
Dart owns transport and feeds a bounded decode → DSP → output pipeline in a
worker isolate. A native miniaudio callback consumes prepared float PCM from a
bounded ring. The callback never invokes Dart, decodes a file, runs a stretch
engine, allocates memory, or takes a control-thread lock.

The package builds one library, `crisper_audio.dll` or `libcrisper_audio.so`,
containing a decoder-only Glint source closure, the existing four-engine
`just_audio/native/crisper_dsp` core, and the output host. It does not use mpv,
FFmpeg, or SoLoud. Apple and Android keep their existing playback adapters;
this plugin is not registered on those platforms. The native CMake project
can also build on macOS for host tests.

## Native output contract

`native/crisper_output.h` defines ABI version 1. All counts are frames, with
interleaved float32 mono/stereo at 8–384 kHz. One Dart worker/control thread
owns a handle. The audio thread is its only consumer.

- `write` returns the number of accepted frames. The caller retains and
  retries the remainder. A full queue returns zero without overwriting or
  discarding earlier PCM.
- `start` begins/resumes consuming the ring. `pause` stops consuming new PCM
  and preserves queued audio. The already-submitted backend tail may finish;
  snapshots continue to account for that tail while paused.
- `reset` closes/reopens the backend, flushes the ring and all timing credits,
  and leaves paused with zero counters. Closing is necessary because
  miniaudio's PulseAudio `stop` corks the stream without flushing its PCM.
- Volume is a finite linear gain from zero to one. Muted PCM still advances
  the source position; underrun silence does not.
- Errors are explicit and sticky. A failed device, invalid PCM, reported
  route change, or interruption requires a new handle. The callback cannot
  silently fall back to unprocessed audio.

### Position and latency

Three values have different meanings:

| Value | Meaning |
|---|---|
| `buffered_frames` | Accepted PCM still in the application's bounded ring |
| `rendered_frames` | PCM handed to the native backend; excludes underrun zeros |
| `presented_frames` | Rendered PCM that has crossed an estimated backend delay |

The presentation estimate uses a preallocated per-frame credit delay line.
Every callback frame advances the device timeline, including pause and
underrun zeros. Only frames carrying queued PCM create source credits. This
lets the final audio drain after the ring empties and prevents a late write
after an underrun from jumping ahead on the source clock.

`latency_frames` exposes the delay used by that estimate. At open, it is
derived from miniaudio's actual backend period/count, WASAPI's actual buffer
size where available, the fixed callback buffer, and extra period allowance.
It intentionally trails the known buffering. It is **not a hardware or DAC
timestamp, and is not an absolute acoustic latency bound**: audio servers,
Bluetooth and device hardware may add latency the API does not report.
Nothing extrapolates source progress from a Dart wall clock. The Dart player
maps presented output frames through the DSP's source-frame spans.

Reported device route changes and interruptions fail closed so that a new
handle can establish a fresh timing epoch. Some miniaudio backends do not
report every possible device route event; physical-device checks remain
necessary for platform validation.

## Loading and packaging

`lib/src/library.dart` opens the exact packaged library beside the Windows
executable or inside the Linux bundle's `lib/` directory, then verifies
`ca_output_abi_version() == 1`. It does not search for arbitrary installed
Glint or DSP libraries. Tests can supply an explicit path or set
`CRISPER_AUDIO_LIBRARY_PATH`; an incompatible override fails visibly.

Flutter's Linux/Windows FFI plugin CMake wrappers build and bundle the same
native target. Its source dependencies are in the repository; no build step
downloads codecs, DSP engines, or audio output libraries.

## Native tests

From the repository root:

```sh
cmake -S packages/crisper_audio/native -B build/crisper_audio \
  -DCMAKE_BUILD_TYPE=Release -DCRISPER_AUDIO_TESTS=ON
cmake --build build/crisper_audio --config Release --parallel
ctest --test-dir build/crisper_audio -C Release --output-on-failure
```

The manual backend runs the exact callback pump deterministically, with
optional simulated latency. Tests verify frame order, stereo channels,
bounded partial writes and wraparound, pause/resume, volume/mute, seek/reset,
invalid PCM, underruns, delayed final tails, and late writes after silence.
A separate null-device test exercises a real native callback thread and the
start/pause/reset/reopen lifecycle without audio hardware. It is not a speaker
or device-latency test.

For Dart integration tests, set `CRISPER_AUDIO_LIBRARY_PATH` to the resulting
shared library and use the player's manual test output.

## Licenses and source pins

The new host and Dart glue are MIT. `native/vendor/miniaudio.manifest.json`
records the exact unchanged miniaudio 0.11.25 header obtained from CometBeat
commit `a9e4d0e553b94369ad883596c9e686e8581c62a2`, with SHA-256 checksums and
the full MIT-0/public-domain grants. Glint's manifest records its source pin
and any local decoder patches. The shared DSP core retains its own reviewed
vendor manifest and the original Sonic, Chromium WSOLA, Signalsmith Stretch,
Bungee Basic and supporting-library notices.
