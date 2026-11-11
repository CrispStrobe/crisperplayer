# CrisperPlayer native time-stretch adapter

This streaming PCM core supplies optional processors for Android, Apple
local-file playback and direct Dart/native desktop playback. It compiles Sonic C,
Bungee Basic and Signalsmith Stretch from pinned, unmodified sources, plus a
maintained portable **Chromium WSOLA** fork. The same code also runs in host
tests and WAV comparisons. The streaming adapter is MIT licensed; the
Chromium-derived port is BSD-3-Clause. Each upstream implementation keeps its
license, recorded in
[vendor/manifest.json](vendor/manifest.json).

Android's default remains Media3's Sonic processor. The native Sonic C processor
serves the optional Apple/desktop paths and the host comparison harness; it is
**not** a bit-exact replica of Media3 Sonic. Apple Time Domain remains its platform default; desktop uses Sonic C by default. Bungee, Signalsmith and WSOLA are
optional listening choices, not a claim that one wins for every voice or speed. Signalsmith's
upstream guidance concentrates on moderate time stretch, roughly 0.75–1.5×.
The adapter's tested functional range is 0.5–3×.

## Build and test without downloading dependencies

From the application repository root:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/build_host.py --jobs 2
python3 packages/just_audio/native/crisper_dsp/tools/test_streaming.py \
  --library build/native-dsp/libcrisper_dsp.so \
  --report build/native-dsp/test-report.json
python3 packages/just_audio/native/crisper_dsp/tools/render_ab.py \
  --output-dir build/dsp-ab --rate 1.5
```

The host build needs Python 3, a C compiler and a C++20 compiler. It verifies every
vendored file against the manifest, compiles exactly the CMake source closure and
writes the compiler arguments, source hashes and binary hash to
`build/native-dsp/build-report.json`. It uses no FFmpeg, MPV, downloaded runtime
binary or build-time dependency fetch. Android adds this directory through CMake
and links target `crisper_dsp`. DSP optimization remains enabled in debug builds.
The build also compiles/runs eight WSOLA search regression fixtures, including
all-negative correlations, signed/excluded endpoints, silence, anti-phase stereo
and a silent first channel. Git-file snapshots verify both SHA-256 and the exact
upstream Git blob ID; existing archive source pins remain unchanged.

The CMake target also supports `CRISPER_DSP_SHARED=ON` and
`CRISPER_DSP_TESTS=ON` for the Linux, macOS and Windows native CI matrix. The
shared library is a testable processing core; loading it alone does not connect
an application's decoder or audio output.

The host tests exercise the actual compiled library, including:

- 44.1/48 kHz mono/stereo at 0.5, 1, 1.25, 1.5, 2 and 3×; exact output frame totals,
  source clock accounting and retained tone pitch.
- Empty input and clips of 1, 2, 7, 127, 511, 512, 513, 1,000 and 4,097 frames;
  tiny input chunks and finite repeated end-of-stream calls.
- Start, middle and end transients; first/last tone bursts; arbitrary input/read
  chunk sizes producing identical results; 8/192 kHz corner configurations.
- PCM16 output, bit-exact unity playback, reset isolation, invalid arguments and
  non-finite input, bounded backpressure, and clocks that exclude queued audio.
- WSOLA shared alignment for opposite-phase stereo and a silent first channel;
  DC/silence, fractional rates, uncommon sample rates, and exact final samples
  across full/partial output-hop boundaries and different chunk sizes.
- Recorded WSOLA host workloads for ordinary/high-speed stereo and 192 kHz PCM.
  These include Python transport time and are not Android CPU/battery results.

Sonic can discard an isolated impulse at high speed when it removes a pitch
period. The report keeps that baseline measurement; it does not hide it or turn
it into a claim about intelligibility. The three optional engines must preserve
these particular markers in the test. All four must preserve boundary tone bursts. Synthetic
signals test timing and signal handling, not human speech quality, battery use
or a particular Android device's real-time reliability.

## Compare the same spoken passage

Use your own uncompressed mono/stereo signed PCM16 WAV:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/render_ab.py \
  --input /absolute/path/passage.wav \
  --output-dir build/my-dsp-comparison --rate 1.5
```

It streams the same source through all four processors and writes separate WAVs
plus `render-report.json`. That report records input/binary/output hashes, input
and output frame counts, peak and saturated PCM samples, and host render time.
Without `--input`, the tool generates six seconds of harmonic bursts, silence
and transient markers, explicitly labeled as synthetic. It never presents those
sounds as speech or a perceptual benchmark.

Listen at equal perceived loudness. Compare consonants, breath sounds, first and
last words, pauses, background music and stereo image at the speeds you use.
Host timing includes Python I/O and is not an Android CPU or battery result.

## Native playback integrations

Android's Media3/JNI adapter retains its existing PCM sink and processing-chain
integration. It replaces the default speed stage for the selected alternatives;
it does not run a second stretcher after Sonic. Android's default Sonic path
continues to use Media3 without loading the optional JNI processor.

The Apple adapter decodes supported local files with `AVAudioFile`, streams PCM
through this core and schedules the processed buffers through `AVAudioEngine`.
Its delivered/output-device position maps back to original source time.
`CrisperDspStream` supplies the shared bridge for all four engines. CocoaPods
compiles thin translation units that include these exact source files. SwiftPM
uses the local [CrisperDsp package](Package.swift) with an explicit source list.
The SwiftPM target requires Swift 6.2, available in the app's Xcode 26 toolchain.
It retains the same optimization and signed-integer wrapping settings as the
other build routes; Bungee's phase arithmetic relies on that wrapping behavior.
There is no second vendored copy of the DSP closure. The ordinary AVPlayer Time
Domain and Spectral paths remain available for the platform default and URLs
outside the optional local-file backend's scope.

The desktop [crisper_audio package](../../../crisper_audio/) links this core
through FFI. Dart owns file/container reads, Glint decoding and transport;
a native callback consumes processed PCM from a bounded queue. The adapter maps
estimated presented output back to source-frame spans. Partial writes, finite
drain and seek/rate resets keep separate processing epochs. All four engines
are compiled into the desktop library and no mpv filter is involved.

See [portable platform coverage](../../../../docs/PORTABLE_AUDIO_PROCESSORS.md)
for build recipes, limits and validation boundaries. The separate browser
player has no new integration of this core.

## Streaming contract

The public C ABI is [crisper_dsp.h](crisper_dsp.h). All counts are **frames**, with
one or two interleaved channels and an unchanged 8–192 kHz sample rate. Pitch
stays at 1.0. Rates outside 0.5–3.0 are rejected. A 1.0 rate bypasses DSP exactly.
Handles are confined to one audio thread.

`write_*` consumes at most the returned count, and can return zero when the
caller must read output first. A caller must retain all unconsumed input. The
input/output rings have fixed capacities of 131,072/65,536 frames; algorithm
lookahead and scratch buffers are bounded at configuration. There is no
whole-book buffering. Errors return -1 (or null for create), with a thread-local
message available immediately through `cp_dsp_last_error`.

`finish` marks the end of real input. The caller continues reading until `ended`
returns true. The output is exactly `round(real_input_frames / rate)` frames.
Bungee removes preroll using the source positions attached to each grain and
feeds zero-valued lookahead at the end. Signalsmith uses upstream `outputSeek`
and `flush` to preserve the beginning and drain the end. Sonic's short residual
rounding is padded through its processor and trimmed to the same duration.
WSOLA retains bounded input lookahead until EOS is known. Its final output hop
uses a smooth complementary blend from ordinary WSOLA continuation to the real
ending source segment, reaching the actual last sample without changing the
exact output frame total. This boundary rule is independent of the signal
content and applies to full, partial and short hops.

`source_frames` counts the original frames represented by **output already
read**, capped at accepted input. Queued output, input lookahead, preroll and
padding do not advance that clock. `output_frames` counts delivered frames.
Neither is a counter of decoded input. `latency_frames` is a conservative
configured lookahead bound, not a device latency measurement or clock offset.

A reset validates and constructs the replacement processor first, then drops all
old input, lookahead, output and counters. Android drains before a speed change,
and resets on seek/flush. The app selects a different algorithm at startup. The
native modes do not implement silence skipping or pitch shifting.

## Maintained Chromium WSOLA fork

The portable implementation in [wsola/](wsola/) derives from Chromium's BSD
`wsola_internals` helpers and documented audio-renderer WSOLA loop at immutable
commit `ddd30ef8aa98443509bf4ce006cb36b4e2296c0b`. Exact unmodified originals are
retained for provenance under `vendor/chromium-wsola`. The fork uses a 20 ms Hann
window, 10 ms synthesis hop, 30 ms candidate interval, normalized per-channel
correlation, five-frame coarse search plus interpolated/refined candidates, and
the source-continuation transition window. It has no Chromium `base`, media
renderer, browser, codec or FFmpeg build dependency.

Both stereo channels share a single selected source offset; their normalized
scores are combined without downmixing, so opposite-phase audio does not cancel
out the alignment signal. All scratch memory is allocated at configuration.
Compile-time SSE2/NEON is used where available, with a portable scalar fallback.
The initial hop retains the real onset instead of fading against nonexistent
preceding audio. Source locations and output position use 64-bit coordinates,
while only bounded window-relative offsets become `int` indices.

Local fixes include valid all-negative correlation candidates, signed exclusion
intervals, nonnegative double-precision rolling energy, explicit endpoint and
interpolated-candidate evaluation, and deterministic closest-to-nominal tie
selection for silence. This is a maintained fork, not bit-exact Chromium browser
playback. The derivation and independent upstream comparisons are documented in
[wsola/UPSTREAM.md](wsola/UPSTREAM.md).

Bungee uses its granular interface with a rebased input origin for every grain.
It does not use the cumulative 32-bit `Stream` input position, so a long audiobook
can pass the 2³¹-frame boundary without that counter wrapping.

## Exact upstream closure and distribution

| Component | Revision | Selected license |
| --- | --- | --- |
| Sonic | `b93885dcb70aae50c6f76b0fe4e0868f029a077e` | Apache-2.0 |
| Signalsmith Stretch | `88061fd4eda56a2353c5d65c74aa3f4ccf76f9da` | MIT |
| Signalsmith Linear | `7bb1c8f36794d6980080ce817c91f8da8fe56a66` | MIT |
| Bungee Basic | `61f52bf34be577d189d388772ddfa3696dee77d8` | MPL-2.0 |
| Eigen Core | `c29c800126982c561e8d0b9255dc65474cd98de3` | MPL-2.0; included BSD/Apache notices retained |
| PFFFT/FFTPACK | `02fe7715a5bf8bfd914681c53429600f94e0f536` | Permissive NCAR/UCAR FFTPACK notice |
| Chromium WSOLA source snapshot | `ddd30ef8aa98443509bf4ce006cb36b4e2296c0b` | BSD-3-Clause |

Eigen is limited to `Core`, its internal core headers, plugins and miscellaneous
support. `EIGEN_MPL2_ONLY` is always defined. Unsupported modules, GPL-only
modules, Bungee Pro, CLI code/cxxopts, Sonic's experimental Speedy integration and
optional external FFT backends are excluded. Upstream license/copyright headers
are unchanged, and every selected file has a SHA-256 entry in the manifest.
PFFFT's exact notice is retained under a local `LicenseRef-PFFFT-FFTPACK` instead
of substituting an inaccurately named standard license.

The app's shared DSP notice includes these license texts and the corresponding
source location on all native platforms; its historical `ANDROID-DSP.txt`
filename is retained. Distribution must preserve notices and make the
MPL-covered source and modifications available under MPL-2.0. The inventory
requires source-manifest review for Android, iOS, macOS, Linux and Windows,
while keeping their individual artifact validation pending. Host signal tests
do not verify an APK's NDK/Maven closure, an Apple application bundle or a
desktop native audio package; those remain separate release checks.
