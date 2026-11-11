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

## Player and decoder support

`NativeAudioPlayer` supports load, play/pause, stop, source-time seek, volume,
and pitch-preserving speed changes from 0.50× to 3.00×. Choose Sonic, Chromium
WSOLA, Signalsmith Stretch or Bungee Basic when constructing the player. The
worker owns decoder, DSP and output handles, checks cancellation during long
scans, and closes its resources before disposal completes. Metadata and
waveform probes use the same bounded decoder.

| Input | Current supported scope |
| --- | --- |
| WAV | Mono/stereo integer PCM 8/16/24/32-bit and float 32/64-bit, including compatible extensible WAV |
| MP3 | MPEG-1/2/2.5 Layer III; Xing/LAME delay and padding; reservoir and synthesis preroll for seeks |
| ADTS AAC | Mono/stereo AAC-LC with supported coding tools; packet-frame duration and seek preroll |
| M4A/M4B/MP4 | Local, unencrypted, non-fragmented AAC-LC; paged sample tables, 64-bit chunk offsets and supported `elst`/`stts` presentation trims |
| Native FLAC | Mono/stereo, 4–24-bit PCM, known STREAMINFO length; bounded frame decoding and CRC-validated frame seeking |

Playback is limited by the shared DSP's 8–192 kHz sample-rate range. The
decoder never holds a whole book's compressed data or PCM. MP3/ADTS indexes
retain at most 16,384 checkpoints. FLAC retains a 2 MiB compressed window and
one block of at most 65,535 frames; larger compressed frames fail explicitly.

HE-AAC/SBR/PS, ALAC, encrypted/fragmented MP4, multichannel audio, complex edit
lists, Ogg Vorbis/Opus/Ogg-FLAC, unknown-length or 32-bit FLAC, and negative
FLAC LPC shifts are outside this decoder's current scope. MP4 gapless trimming
uses edit/sample timing; metadata present only in `iTunSMPB` is not applied.
Unsupported streams report an error. Apple/Android codec support is unchanged
because those platforms use their own playback adapters.

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

The owned miniaudio configuration disables optional JACK loading. Windows
uses native Windows output APIs; Linux retains its host PulseAudio/ALSA
backends. Those Linux client libraries have their own system licenses and
are not relicensed by the miniaudio wrapper.

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

Glint declares MIT. Its AAC numerical tables are now generated offline from
two hash-checked files at a pinned Apache-2.0 vo-aacenc revision, with the full
license and notices retained. All 45 arrays and 3,229 values match the original
table body; the retained patch changes attribution and the generator's inputs.
The provenance record distinguishes this reproducible source identity from the
unknown original generator invocation. Matching sources and functional tests
do not replace review of the exact distributed artifacts.

`scripts/audit_native_audio.py` inspects the actual desktop bundle, rejects
bundled mpv/FFmpeg-family binaries, records the native artifact and source
hashes, and executes the real processor/decoder/output ABI in a child process.
The direct-native CI workflow builds on Linux, Windows and macOS, then runs
the Dart decoder/player/app-adapter tests with a required native library. It
also builds real Linux/Windows Flutter bundles and reruns those tests against
the library inside the bundle. These checks exercise a manual/null output
device; they do not establish physical audio-device latency.
